-- Direct-message controls: expiry, pinning, edit history, and per-user receipts.
alter table public.conversations
  add column if not exists message_expiry interval not null default interval '0';

alter table public.messages
  add column if not exists expires_at timestamptz,
  add column if not exists pinned_at timestamptz,
  add column if not exists edited_at timestamptz,
  add column if not exists original_content text;

create index if not exists messages_expiry_idx
  on public.messages (expires_at) where expires_at is not null;

create table if not exists public.message_reads (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
alter table public.message_reads enable row level security;
drop policy if exists "Conversation members read receipts" on public.message_reads;
create policy "Conversation members read receipts" on public.message_reads
  for select to authenticated using (
    exists (select 1 from public.messages m join public.conversation_participants cp
      on cp.conversation_id = m.conversation_id
      where m.id = message_id and cp.user_id = auth.uid())
  );
drop policy if exists "Users create own read receipts" on public.message_reads;
create policy "Users create own read receipts" on public.message_reads
  for insert to authenticated with check (
    user_id = auth.uid() and exists (
      select 1 from public.messages m join public.conversation_participants cp
        on cp.conversation_id = m.conversation_id
      where m.id = message_id and cp.user_id = auth.uid() and m.sender_id <> auth.uid()
    )
  );

-- Expired rows are excluded at read time; this scheduled function physically removes them.
create or replace function public.delete_expired_messages()
returns bigint language plpgsql security definer set search_path = '' as $$
declare deleted_count bigint;
begin
  delete from public.messages where expires_at is not null and expires_at <= now();
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

-- Server-side guard: only the author can edit, within 15 minutes, and only content changes.
create or replace function public.guard_message_update()
returns trigger language plpgsql set search_path = '' as $$
begin
  if auth.uid() is null or auth.uid() <> old.sender_id then
    raise exception 'only the message author may update this message';
  end if;
  if new.conversation_id <> old.conversation_id or new.sender_id <> old.sender_id
     or new.created_at <> old.created_at then
    raise exception 'message identity fields cannot be changed';
  end if;
  if new.content is distinct from old.content then
    if old.created_at < now() - interval '15 minutes' then
      raise exception 'message edit window has expired';
    end if;
    new.original_content := coalesce(old.original_content, old.content);
    new.edited_at := now();
  end if;
  return new;
end;
$$;
drop trigger if exists guard_message_update on public.messages;
create trigger guard_message_update before update on public.messages
  for each row execute function public.guard_message_update();

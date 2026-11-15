-- 2026-11-13 — Issue #77: Message Management — Edit history tracking

-- Track every edit so users can view the full history of a message.
create table if not exists public.message_edit_history (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  previous_content text not null,
  new_content text not null,
  edited_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.message_edit_history enable row level security;

-- Anyone who can see the message can see its edit history
drop policy if exists "View edit history" on public.message_edit_history;
create policy "View edit history" on public.message_edit_history
  for select to authenticated
  using (
    exists (
      select 1 from public.messages m
      join public.conversation_participants cp
        on cp.conversation_id = m.conversation_id
      where m.id = message_edit_history.message_id
        and cp.user_id = auth.uid()
    )
  );

-- Only the message sender can create edit history entries
drop policy if exists "Create edit history" on public.message_edit_history;
create policy "Create edit history" on public.message_edit_history
  for insert to authenticated
  with check (
    exists (
      select 1 from public.messages m
      where m.id = message_edit_history.message_id
        and m.sender_id = auth.uid()
    )
  );

-- Index for fast lookups by message_id
create index if not exists idx_message_edit_history_message_id
  on public.message_edit_history(message_id, edited_at desc);

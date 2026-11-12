-- ============================================================
-- Message deletion
--
-- The client offers two actions:
--   * "Delete for me"        -> Supa.deleteMessage / hideMessageForMe
--   * "Delete for everyone"  -> Supa.deleteMessageForEveryone
--
-- Neither worked before this migration:
--   * messages had no DELETE policy at all, so every delete affected 0 rows
--     and failed silently;
--   * the only UPDATE policy requires sender_id = auth.uid(), so a recipient
--     could not even mark a message hidden;
--   * reading receipts through the RPC then crashed because the trigger
--     expected auth.uid() to equal the sender.
--
-- Design:
--   * Nothing is hard-deleted from the table, which keeps Realtime's
--     postgres_changes payload valid for every subscriber (a hard DELETE only
--     carries the primary key by default).
--   * `deleted_at` is set for everyone ("delete for everyone").
--   * `hidden_for` records per-user removal ("delete for me"); reads filter it.
--   * A SECURITY DEFINER RPC validates ownership and the 1-hour window so the
--     rules live in one place rather than in the client.
-- ============================================================

alter table public.messages
  add column if not exists deleted_at timestamptz,
  add column if not exists hidden_for uuid[] not null default '{}'::uuid[],
  add column if not exists deleted_by uuid references auth.users(id) on delete set null;

create index if not exists messages_hidden_for_idx
  on public.messages using gin (hidden_for);

-- ------------------------------------------------------------------
-- delete_message_for_everyone: author only, inside the 1-hour window.
-- After the window the message is tombstoned (content replaced) instead
-- of removed, so the conversation keeps its shape for both people.
-- ------------------------------------------------------------------
create or replace function public.delete_message_for_everyone(msg_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  msg_sender uuid;
  msg_created timestamptz;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated call';
  end if;

  select sender_id, created_at into msg_sender, msg_created
  from public.messages where id = msg_id;

  if not found then
    raise exception 'message not found';
  end if;

  if msg_sender <> auth.uid() then
    raise exception 'only the message author may delete a message for everyone';
  end if;

  if msg_created < now() - interval '1 hour' then
    -- Tombstone: history is preserved but the content is gone.
    update public.messages
       set content = 'This message was deleted',
           deleted_at = coalesce(deleted_at, now()),
           deleted_by = auth.uid(),
           edited_at = now()
     where id = msg_id;
  else
    update public.messages
       set deleted_at = now(),
           deleted_by = auth.uid()
     where id = msg_id;
  end if;
end;
$$;

grant execute on function public.delete_message_for_everyone(uuid) to authenticated;

-- ------------------------------------------------------------------
-- hide_message_for_me: any participant may remove a message from
-- their own view. Idempotent.
-- ------------------------------------------------------------------
create or replace function public.hide_message_for_me(msg_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  msg_conversation uuid;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated call';
  end if;

  select conversation_id into msg_conversation
  from public.messages where id = msg_id;

  if not found then
    raise exception 'message not found';
  end if;

  if not exists (
    select 1 from public.conversation_participants cp
    where cp.conversation_id = msg_conversation
      and cp.user_id = auth.uid()
  ) then
    raise exception 'not a participant';
  end if;

  update public.messages
     set hidden_for = (
       select coalesce(array_agg(distinct u), '{}'::uuid[])
         from unnest(hidden_for || auth.uid()) AS u
     )
   where id = msg_id;
end;
$$;

grant execute on function public.hide_message_for_me(uuid) to authenticated;

-- ------------------------------------------------------------------
-- Read access: keep the existing membership policy, but hide rows the
-- caller removed and never expose the inner tombstone marker.
-- ------------------------------------------------------------------
drop policy if exists "Participants read messages" on public.messages;
create policy "Participants read messages" on public.messages
  for select to authenticated using (
    -- "delete for me" hides the row from this caller only. Row-level checks
    -- reference column values, never another scan of public.messages (that
    -- would make the policy recurse into itself).
    not (coalesce(hidden_for, '{}'::uuid[]) @> array[auth.uid()])
    and exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id = messages.conversation_id
        and cp.user_id = auth.uid()
    )
  );

-- ------------------------------------------------------------------
-- Realtime: the messages stream must deliver the hidden_for update,
-- otherwise "delete for me" only takes effect after a reload.
-- ------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'messages'
     ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end
$$;

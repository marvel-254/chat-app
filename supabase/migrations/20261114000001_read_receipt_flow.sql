-- ============================================================
-- Fix read-receipt flow: populate message_reads and enable realtime
-- Fixes issue #7.
--
-- Problems fixed:
-- 1. mark_messages_read RPC did not insert into message_reads,
--    so the sender's readByPeer check (which queries message_reads)
--    never saw the peer's read state.
-- 2. message_reads table was not published for Supabase Realtime,
--    so the sender's chat stream never refreshed when the recipient
--    read messages.
-- ============================================================

-- 1. Rewrite mark_messages_read to also upsert into message_reads.
--    The upsert ensures idempotency: calling the RPC multiple times
--    for the same conversation does not create duplicate rows.
drop function if exists public.mark_messages_read(uuid);

create or replace function public.mark_messages_read(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  my_uid uuid := auth.uid();
  latest_read timestamptz := now();
begin
  -- Reject unauthenticated calls
  if my_uid is null then
    raise exception 'unauthenticated call';
  end if;

  -- Verify membership
  if not exists (
    select 1 from public.conversation_participants
    where conversation_id = p_conversation_id
      and user_id = my_uid
  ) then
    raise exception 'not a participant';
  end if;

  -- Mark inbound unread messages as read (only those sent by others)
  update public.messages
     set read_at = latest_read
   where conversation_id = p_conversation_id
     and sender_id <> my_uid
     and read_at is null;

  -- Insert read receipts into message_reads so the sender can see them.
  -- Uses ON CONFLICT to be idempotent.
  insert into public.message_reads (message_id, user_id, read_at)
  select m.id, my_uid, latest_read
    from public.messages m
   where m.conversation_id = p_conversation_id
     and m.sender_id <> my_uid
  on conflict (message_id, user_id)
  do update set read_at = excluded.read_at;

  -- Advance the caller's cursor (NULL becomes now, effectively marking all prior as read)
  update public.conversation_participants
     set last_read_at = latest_read
   where conversation_id = p_conversation_id
     and user_id = my_uid;
end;
$$;

grant execute on function public.mark_messages_read(uuid) to authenticated;

-- 2. Publish message_reads for Supabase Realtime so the sender's
--    watchMessages stream picks up read-receipt changes live.
drop publication if exists supabase_realtime_message_reads;
alter publication supabase_realtime add table public.message_reads;

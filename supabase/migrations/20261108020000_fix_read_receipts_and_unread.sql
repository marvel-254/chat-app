-- ============================================================
-- Fix read-receipt RLS and NULL unread cursors
-- Fixes issue #47.
--
-- Provides a transactional RPC for marking messages read that:
-- - Binds to auth.uid()
-- - Verifies conversation membership
-- - Allows only the recipient to mark inbound messages read
-- - Advances only that caller's last_read_at cursor
-- - Treats NULL cursor as unread-from-the-beginning
-- ============================================================

-- 1. Add UPDATE policy on conversation_participants for own last_read_at
--    (only the participant can update their own cursor)
create policy "Participants update own last_read_at" on public.conversation_participants
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- 2. Allow recipients to set read_at on inbound messages
--    (only for messages they received, not sent)
create policy "Recipients mark messages read" on public.messages
  for update using (
    sender_id <> auth.uid()
    and exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id = messages.conversation_id
        and cp.user_id = auth.uid()
    )
  )
  with check (
    sender_id <> auth.uid()
    and read_at is not null
    and exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id = messages.conversation_id
        and cp.user_id = auth.uid()
    )
  );

-- 3. Transactional RPC to mark messages as read and advance cursor
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

  -- Advance the caller's cursor (NULL becomes now, effectively marking all prior as read)
  update public.conversation_participants
     set last_read_at = latest_read
   where conversation_id = p_conversation_id
     and user_id = my_uid;
end;
$$;

grant execute on function public.mark_messages_read(uuid) to authenticated;

-- 4. Fix unread count calculation in get_conversations_for_user to handle NULL last_read_at
--    The function is redefined in 20261106000000_privacy_and_fixes.sql and 20261102000000_chat_media_calls.sql
--    We need to update the latest version. Since migrations are applied in order, we drop and recreate.
drop function if exists public.get_conversations_for_user();

create or replace function public.get_conversations_for_user()
returns table (
  conversation_id uuid,
  created_at timestamptz,
  updated_at timestamptz,
  peer_id uuid,
  peer_username text,
  peer_display_name text,
  peer_avatar_url text,
  last_message text,
  last_message_at timestamptz,
  unread_count bigint
)
language sql
stable
security invoker
as $$
  select
    v.id,
    v.created_at,
    v.updated_at,
    v.peer_id,
    v.peer_username,
    v.peer_display_name,
    v.peer_avatar_url,
    v.last_message,
    v.last_message_at,
    v.unread_count
  from
    (select
      c.id,
      c.created_at,
      c.updated_at,
      -- the other participant (not the caller)
      (select p.id from public.visible_profiles p
         join public.conversation_participants cp on cp.user_id = p.id
        where cp.conversation_id = c.id and cp.user_id <> auth.uid()
        limit 1) as peer_id,
      (select p.username from public.visible_profiles p
         join public.conversation_participants cp on cp.user_id = p.id
        where cp.conversation_id = c.id and cp.user_id <> auth.uid()
        limit 1) as peer_username,
      (select p.display_name from public.visible_profiles p
         join public.conversation_participants cp on cp.user_id = p.id
        where cp.conversation_id = c.id and cp.user_id <> auth.uid()
        limit 1) as peer_display_name,
      (select p.avatar_url from public.visible_profiles p
         join public.conversation_participants cp on cp.user_id = p.id
        where cp.conversation_id = c.id and cp.user_id <> auth.uid()
        limit 1) as peer_avatar_url,
      (select m.content from public.messages m
        where m.conversation_id = c.id
        order by m.created_at desc limit 1) as last_message,
      (select m.created_at from public.messages m
        where m.conversation_id = c.id
        order by m.created_at desc limit 1) as last_message_at,
      -- unread = messages not yet read by the caller, newer than their last_read_at
      -- Treat NULL last_read_at as unread-from-the-beginning (epoch)
      (select count(*) from public.messages m
        where m.conversation_id = c.id
          and m.sender_id <> auth.uid()
          and m.read_at is null
          and m.created_at > coalesce((
            select cp.last_read_at from public.conversation_participants cp
            where cp.conversation_id = c.id and cp.user_id = auth.uid()
          ), '-infinity'::timestamptz)
      ) as unread_count
    from public.conversations c
    where exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id = c.id and cp.user_id = auth.uid()
    )) as v
    order by v.last_message_at nulls first, v.updated_at desc;
$$;

grant execute on function public.get_conversations_for_user() to authenticated;
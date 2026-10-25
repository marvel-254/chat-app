-- ============================================================
-- Conversation enrichment: peer identity + unread count
-- Fixes issues #30 (resolve peer name/avatar) and #34 (unread badges).
-- ============================================================

-- Returns one row per conversation the caller participates in, with the
-- other participant's profile and the count of unread messages for the caller.
-- Runs as a normal (RLS-checked) function; the caller must be a participant,
-- which is enforced by the conversations/participants SELECT policies.
create or replace function get_conversations_for_user()
returns table (
  conversation_id uuid,
  created_at timestamptz,
  updated_at timestamptz,
  peer_id uuid,
  peer_username text,
  peer_display_name text,
  last_message text,
  last_message_at timestamptz,
  unread_count bigint
) language sql
stable
security invoker
as $$
  select
    c.id,
    c.created_at,
    c.updated_at,
    -- the other participant (not the caller)
    (select p.id from profiles p
       join conversation_participants cp on cp.user_id = p.id
      where cp.conversation_id = c.id and cp.user_id <> auth.uid()
      limit 1) as peer_id,
    (select p.username from profiles p
       join conversation_participants cp on cp.user_id = p.id
      where cp.conversation_id = c.id and cp.user_id <> auth.uid()
      limit 1) as peer_username,
    (select p.display_name from profiles p
       join conversation_participants cp on cp.user_id = p.id
      where cp.conversation_id = c.id and cp.user_id <> auth.uid()
      limit 1) as peer_display_name,
    (select m.content from messages m
      where m.conversation_id = c.id
      order by m.created_at desc limit 1) as last_message,
    (select m.created_at from messages m
      where m.conversation_id = c.id
      order by m.created_at desc limit 1) as last_message_at,
    -- unread = messages not yet read by the caller, newer than their last_read_at
    (select count(*) from messages m
      where m.conversation_id = c.id
        and m.sender_id <> auth.uid()
        and m.read_at is null
        and (
          not exists (
            select 1 from conversation_participants cp
            where cp.conversation_id = c.id and cp.user_id = auth.uid()
          )
          or m.created_at > (
            select cp.last_read_at from conversation_participants cp
            where cp.conversation_id = c.id and cp.user_id = auth.uid()
          )
        )
    ) as unread_count
  from conversations c
  where exists (
    select 1 from conversation_participants cp
    where cp.conversation_id = c.id and cp.user_id = auth.uid()
  )
  order by last_message_at nulls first, c.updated_at desc;
$$;

-- ============================================================
-- Add is_locked field to get_conversations_for_user RPC
-- This allows the UI to show lock icons on locked conversations
-- ============================================================

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
  unread_count bigint,
  is_locked boolean
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
    v.unread_count,
    v.is_locked
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
      ) as unread_count,
      -- Check if conversation is locked for current user
      (exists (
        select 1 from public.conversation_locks cl
        where cl.conversation_id = c.id
          and cl.user_id = auth.uid()
      )) as is_locked
    from public.conversations c
    where exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id = c.id and cp.user_id = auth.uid()
    )) as v
    order by v.last_message_at nulls first, v.updated_at desc;
$$;

grant execute on function public.get_conversations_for_user() to authenticated;

-- ============================================================
-- Peer identity: let members read co-participants of their conversations
-- Fixes #51 (and the live recurrence of #30).
--
-- Root cause: conversation_participants had a single SELECT policy,
--   "Users see own participations" using (user_id = auth.uid())
-- so every other member's row was invisible to clients.
--
-- get_conversations_for_user() is SECURITY INVOKER, so RLS applies to the
-- peer subqueries inside it:
--   (select p.username from visible_profiles p
--      join conversation_participants cp on cp.user_id = p.id
--     where cp.conversation_id = c.id and cp.user_id <> auth.uid())
-- With the old policy those subqueries matched nothing, so peer_id /
-- peer_username / peer_display_name / peer_avatar_url were always NULL and
-- the chat list fell back to "Chat" with a "?" avatar. ChatScreen._loadPeer()
-- queries the same table for user_id != me, so the chat header had the same
-- problem.
--
-- Fix: widen SELECT to co-participants of a shared conversation.
--
-- NOTE: the naive self-referencing form
--   using (exists (select 1 from conversation_participants cp2
--                 where cp2.conversation_id = conversation_participants.conversation_id
--                   and cp2.user_id = auth.uid()))
-- raises "infinite recursion detected in policy for relation
-- conversation_participants" (42P17): evaluating the policy needs a read of
-- the very table the policy protects, which re-enters the policy. The
-- membership test is therefore wrapped in a SECURITY DEFINER function, which
-- runs as the table owner and bypasses RLS, breaking the recursion.
--
-- This does not expose the whole table: a user only sees rows belonging to
-- conversations they are themselves a member of (plus their own rows).
-- ============================================================

create or replace function public.is_conversation_member(conv uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.conversation_participants cp
     where cp.conversation_id = conv
       and cp.user_id = auth.uid()
  );
$$;

revoke execute on function public.is_conversation_member(uuid) from public;
grant execute on function public.is_conversation_member(uuid) to authenticated;

drop policy if exists "Users see own participations" on public.conversation_participants;

create policy "Members see co-participants" on public.conversation_participants
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.is_conversation_member(conversation_id)
  );

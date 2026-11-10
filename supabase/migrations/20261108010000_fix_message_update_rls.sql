-- ============================================================
-- Fix message UPDATE RLS: require membership in target conversation
-- Fixes issue #45.
--
-- The previous policy only checked sender_id = auth.uid(), allowing
-- a sender to UPDATE a message into a conversation they don't belong
-- to (though the guard_message_update trigger blocks conversation_id
-- changes, RLS should also enforce membership for defense in depth).
-- ============================================================

drop policy if exists "Sender updates own message" on public.messages;

create policy "Sender updates own message" on public.messages
  for update using (
    sender_id = auth.uid()
    and exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id = messages.conversation_id
        and cp.user_id = auth.uid()
    )
  )
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id = messages.conversation_id
        and cp.user_id = auth.uid()
    )
  );
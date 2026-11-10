-- ============================================================
-- Fix conversations UPDATE RLS: allow participants to update settings
-- Fixes issue where Supa.setMessageExpiry() and getOrCreateDM() fail
-- due to missing UPDATE policy on conversations table.
-- ============================================================

create policy "Participants update conversation settings" on public.conversations
  for update to authenticated
  using (
    exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id = conversations.id
        and cp.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id = conversations.id
        and cp.user_id = auth.uid()
    )
  );

-- ============================================================
-- Refresh chat list activity from message events
-- Fixes issue #10 and #44.
--
-- The conversations table is published for Supabase Realtime so
-- watchConversations() can use a live stream instead of polling.
-- A database trigger automatically bumps conversations.updated_at
-- whenever a new message is inserted, so the chat list ordering
-- stays correct even if the client-side update is rate-limited.
-- ============================================================

-- 1. Publish conversations for realtime.
do $$
begin
  alter publication supabase_realtime add table public.conversations;
exception
  when duplicate_object then null;
end $$;

-- 2. Trigger: bump conversations.updated_at on new messages.
--    This is a safety net — the client also updates updated_at in
--    MessageSafety.send(), but a server-side trigger guarantees the
--    timestamp always advances regardless of client connectivity.
create or replace function public._bump_conversation_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversations
     set updated_at = now()
   where id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists bump_conversation_updated_at on public.messages;
create trigger bump_conversation_updated_at
  after insert on public.messages
  for each row
  execute function public._bump_conversation_updated_at();

-- ============================================================
-- Per-user draft text for each conversation.
-- Saved while typing so drafts survive navigation and restart.
-- ============================================================

alter table public.conversation_participants
  add column if not exists draft text;

-- ============================================================
-- Add auto_lock_timer to profiles for conversation auto-lock settings
-- ============================================================

alter table public.profiles
  add column if not exists auto_lock_timer interval not null default interval '0';

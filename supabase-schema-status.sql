-- status schema
alter table profiles add column if not exists status text;
alter table profiles add column if not exists status_emoji text;
alter table profiles add column if not exists status_expires_at timestamp with time zone;

-- optional: realtime presence for "active now" style indicators
-- (handled via Supabase Realtime presence channel in app, not stored)
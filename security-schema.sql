-- 1. Security/Block Schema
create table blocked_users (
  blocker_id uuid references auth.users(id) on delete cascade not null,
  blocked_id uuid references auth.users(id) on delete cascade not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  primary key (blocker_id, blocked_id)
);

-- 2. Security Metadata for E2EE (in profiles)
alter table profiles add column if not exists public_key text;

-- 3. Conversation Lock Status
alter table conversation_participants add column if not exists is_locked boolean default false;

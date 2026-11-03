-- Chat features: read receipts preference, default message expiry, and conversation lock tracking
alter table public.profiles
  add column if not exists read_receipts_enabled boolean not null default true,
  add column if not exists default_message_expiry interval not null default interval '0';

create table if not exists public.conversation_locks (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
alter table public.conversation_locks enable row level security;

drop policy if exists "Users manage own conversation locks" on public.conversation_locks;
create policy "Users manage own conversation locks" on public.conversation_locks
  for all to authenticated using (user_id = auth.uid())
  with check (user_id = auth.uid());

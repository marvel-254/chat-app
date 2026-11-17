-- ============================================================
-- Scheduled messages: store messages that should be delivered
-- at a future time.
-- Fixes issue #55.
--
-- A scheduled message is inserted into this table instead of
-- the messages table. A background worker (or the client on
-- wake-up) moves it to messages when the scheduled time arrives.
-- ============================================================

create table if not exists public.scheduled_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  content text not null,
  attachment_url text,
  attachment_mime text,
  reply_to_id uuid references public.messages(id) on delete set null,
  scheduled_at timestamptz not null,
  created_at timestamptz not null default now(),

  -- Prevent scheduling in the past
  check (scheduled_at >= now())
);

alter table public.scheduled_messages enable row level security;

-- Users can view their own scheduled messages
drop policy if exists "Users view own scheduled messages" on public.scheduled_messages;
create policy "Users view own scheduled messages"
  on public.scheduled_messages for select
  to authenticated using (sender_id = auth.uid());

-- Users can insert their own scheduled messages
drop policy if exists "Users insert own scheduled messages" on public.scheduled_messages;
create policy "Users insert own scheduled messages"
  on public.scheduled_messages for insert
  to authenticated with check (sender_id = auth.uid());

-- Users can delete their own scheduled messages
drop policy if exists "Users delete own scheduled messages" on public.scheduled_messages;
create policy "Users delete own scheduled messages"
  on public.scheduled_messages for delete
  to authenticated using (sender_id = auth.uid());

-- Index for the background worker that scans for due messages
create index if not exists idx_scheduled_messages_scheduled_at
  on public.scheduled_messages (scheduled_at);

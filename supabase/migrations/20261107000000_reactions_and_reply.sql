-- ============================================================
-- Emoji Reactions + Reply-to Messages
-- ============================================================

-- -----------------------------------------------------------------
-- message_reactions: emoji reactions on messages
-- -----------------------------------------------------------------
create table if not exists public.message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  unique (message_id, user_id, emoji)
);

-- Index for fetching reactions per message
create index if not exists message_reactions_message_id_idx
  on public.message_reactions (message_id);

-- RLS: participants can view reactions
alter table public.message_reactions enable row level security;

create policy "Participants can view reactions"
  on public.message_reactions
  for select
  to authenticated
  using (
    exists (
      select 1 from public.messages m
      join public.conversation_participants cp on cp.conversation_id = m.conversation_id
      where m.id = message_reactions.message_id
        and cp.user_id = auth.uid()
    )
  );

-- RLS: authenticated users can add their own reactions
create policy "Users can add own reactions"
  on public.message_reactions
  for insert
  to authenticated
  with check (user_id = auth.uid());

-- RLS: users can remove their own reactions
create policy "Users can remove own reactions"
  on public.message_reactions
  for delete
  to authenticated
  using (user_id = auth.uid());


-- -----------------------------------------------------------------
-- reply_to_id: self-referential FK for reply-to messages
-- -----------------------------------------------------------------
alter table public.messages
  add column if not exists reply_to_id uuid references public.messages(id) on delete set null;

create index if not exists messages_reply_to_id_idx
  on public.messages (reply_to_id);

-- Note: reply_to_id validation (must be in same conversation) enforced by application logic


-- -----------------------------------------------------------------
-- Realtime publication for reactions
-- -----------------------------------------------------------------
alter publication supabase_realtime add table public.message_reactions;
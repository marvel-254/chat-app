-- ============================================================
-- Bro Circles: Link Circles to Conversations
--
-- Maps circles to actual chat conversations so groups can have
-- real-time messaging, polls, and other features.
-- ============================================================

-- Add circle_id to conversation_participants if needed
-- (Using jsonb for flexibility in storing additional group settings)
create or replace function public.link_circle_to_conversation(
  p_circle_id uuid,
  p_conversation_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  insert into public.conversation_participants_extra (conversation_id, circle_id)
  values (p_conversation_id, p_circle_id)
  on conflict (conversation_id)
  do update set circle_id = p_circle_id
  returning circle_id;
$$;

-- Remove circle association from conversation
create or replace function public.unlink_circle_from_conversation(
  p_conversation_id uuid
)
returns void
language sql
stable
security definer
set search_path = ''
as $$
  delete from public.conversation_participants_extra
  where conversation_id = p_conversation_id;
$$;

-- Get conversation associated with a circle
create or replace function public.get_conversation_for_circle(
  p_circle_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select cp.conversation_id
  from public.conversation_participants_extra cp
  where cp.circle_id = p_circle_id
  limit 1;
$$;

-- Create a new conversation paired with a circle
create or replace function public.create_conversation_for_circle(
  p_circle_id uuid,
  p_name text
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  -- First create or get the circle if it doesn't exist
  insert into public.circles (id, name, creator_id)
  values (p_circle_id, p_name, auth.uid())
  on conflict (id) do nothing
  returning id;
$$;

-- ============================================================
-- Conversations list enhanced for circles
-- ============================================================

-- Create or replace get_conversations_for_user to include circles
create or replace function public.get_conversations_for_user()
returns table (
  conversation_id uuid,
  created_at timestamp with time zone,
  updated_at timestamp with time zone,
  peer_id uuid,
  peer_username text,
  peer_display_name text,
  peer_avatar_url text,
  last_message text,
  last_message_at timestamp with time zone,
  unread_count int,
  is_locked boolean,
  is_circle boolean,
  circle_id uuid,
  circle_name text,
  circle_avatar_path text
)
language sql
stable
security definer
set search_path = ''
as $$
  with circle_conversations as (
    select
      cp.conversation_id,
      c.name as circle_name,
      c.avatar_path as circle_avatar_path
    from public.circles c
    join public.conversation_participants_extra cp on cp.circle_id = c.id
    where exists (
      select 1
      from public.conversation_participants
      where conversation_id = cp.conversation_id
        and user_id = auth.uid()
    )
  )
  select
    c.conversation_id,
    c.created_at,
    c.updated_at,
    c.peer_id,
    c.peer_username,
    c.peer_display_name,
    c.peer_avatar_url,
    c.last_message,
    c.last_message_at,
    c.unread_count,
    c.is_locked,
    true as is_circle,
    cc.circle_id,
    cc.circle_name,
    cc.circle_avatar_path
  from public.converse_rows c
  cross join circle_conversations cc
  where not exists (
    -- Exclude duplicates: only show the first matching conversation
    select 1
    from circle_conversations cc2
    where cc2.conversation_id = c.conversation_id
      and cc2.circle_id > cc.circle_id
  );
$$;

-- Helper function to get all conversations including both DMs and circles
create or replace function public.get_all_conversations_for_user()
returns table (
  conversation_id uuid,
  created_at timestamp with time zone,
  updated_at timestamp with time zone,
  peer_id uuid,
  peer_username text,
  peer_display_name text,
  peer_avatar_url text,
  last_message text,
  last_message_at timestamp with time zone,
  unread_count int,
  is_locked boolean,
  is_circle boolean,
  circle_id uuid,
  circle_name text,
  circle_avatar_path text
)
language sql
stable
security definer
set search_path = ''
as $$
  -- Regular conversations (DMs and non-circle group chats)
  select
    c.conversation_id,
    c.created_at,
    c.updated_at,
    c.peer_id,
    c.peer_username,
    c.peer_display_name,
    c.peer_avatar_url,
    c.last_message,
    c.last_message_at,
    c.unread_count,
    c.is_locked,
    false as is_circle,
    null as circle_id,
    null as circle_name,
    null as circle_avatar_path
  from public.converse_rows c

  union all

  -- Circle conversations
  select
    cc.conversation_id,
    c.created_at,
    c.updated_at,
    cc.circle_id as peer_id,
    cc.circle_name as peer_username,
    null as peer_display_name,
    cc.circle_avatar_path as peer_avatar_url,
    c.last_message,
    c.last_message_at,
    c.unread_count,
    c.is_locked,
    true as is_circle,
    cc.circle_id,
    cc.circle_name,
    cc.circle_avatar_path
  from public.circles c
  join public.conversation_participants_extra cp on cp.circle_id = c.id
  join public.converse_rows cr on cr.conversation_id = cp.conversation_id
  cross join circle_conversations cc
  where exists (
    select 1
    from public.conversation_participants
    where conversation_id = cp.conversation_id
      and user_id = auth.uid()
  )
  and not exists (
    select 1
    from public.converse_rows c2
    where c2.conversation_id = cp.conversation_id
      and c2.last_message_at IS NOT NULL
  );
$$;

-- ============================================================
-- Conversation partipants enhancement for circles
-- ============================================================

create table if not exists public.conversation_participants_extra (
  conversation_id uuid primary key,
  circle_id uuid references public.circles(id) on delete cascade
);

-- RLS Policies
alter table public.conversation_participants_extra enable row level security;

create policy "Users can view their circle conversations"
  on public.conversation_participants_extra for select
  using (
    exists (
      select 1
      from public.conversation_participants
      where conversation_id = public.conversation_participants_extra.conversation_id
        and user_id = auth.uid()
    )
  );

create policy "Users can update their own extra data"
  on public.conversation_participants_extra for update
  using (
    public.conversation_participants_extra.conversation_id in (
      select conversation_id
      from public.conversation_participants
      where user_id = auth.uid()
    )
  )
  with check (
    public.conversation_participants_extra.conversation_id in (
      select conversation_id
      from public.conversation_participants
      where user_id = auth.uid()
    )
  );
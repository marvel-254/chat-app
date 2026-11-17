-- ============================================================
-- Bro Circles: Link Circles to Conversations
--
-- Maps circles to actual chat conversations so groups can have
-- real-time messaging, polls, and other features.
-- ============================================================

-- ============================================================
-- Conversation participants enhancement for circles
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

-- Base view that enriches conversations with peer identity and last message
-- (replaces the inline logic previously in get_conversations_for_user)
create or replace view public.converse_rows as
select
  c.id as conversation_id,
  c.created_at,
  c.updated_at,
  (select p.id from profiles p
     join conversation_participants cp on cp.user_id = p.id
    where cp.conversation_id = c.id and cp.user_id <> auth.uid()
    limit 1) as peer_id,
  (select p.username from profiles p
     join conversation_participants cp on cp.user_id = p.id
    where cp.conversation_id = c.id and cp.user_id <> auth.uid()
    limit 1) as peer_username,
  (select p.display_name from profiles p
     join conversation_participants cp on cp.user_id = p.id
    where cp.conversation_id = c.id and cp.user_id <> auth.uid()
    limit 1) as peer_display_name,
  (select p.avatar_url from profiles p
     join conversation_participants cp on cp.user_id = p.id
    where cp.conversation_id = c.id and cp.user_id <> auth.uid()
    limit 1) as peer_avatar_url,
  (select m.content from messages m
    where m.conversation_id = c.id
    order by m.created_at desc limit 1) as last_message,
  (select m.created_at from messages m
    where m.conversation_id = c.id
    order by m.created_at desc limit 1) as last_message_at,
  (select count(*) from messages m
    where m.conversation_id = c.id
      and m.sender_id <> auth.uid()
      and m.read_at is null
  ) as unread_count,
  (exists (
    select 1 from conversation_locks cl
    where cl.conversation_id = c.id and cl.user_id = auth.uid()
  )) as is_locked
from conversations c
where exists (
  select 1 from conversation_participants cp
  where cp.conversation_id = c.id and cp.user_id = auth.uid()
);

-- Drop existing function if it has a different signature
drop function if exists public.get_conversations_for_user();

-- Get all conversations for the current user (DMs + circle groups)
create function public.get_conversations_for_user()
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
    null::uuid as circle_id,
    null::text as circle_name,
    null::text as circle_avatar_path
  from public.converse_rows c
$$;

-- Helper function to get all conversations including both DMs and circles
drop function if exists public.get_all_conversations_for_user();

create function public.get_all_conversations_for_user()
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
  -- Regular conversations (DMs)
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
    null::uuid as circle_id,
    null::text as circle_name,
    null::text as circle_avatar_path
  from public.converse_rows c

  union all

  -- Circle conversations (groups linked to circles)
  select
    cp.conversation_id,
    cr.created_at,
    cr.updated_at,
    ci.id as peer_id,
    ci.name as peer_username,
    null as peer_display_name,
    ci.avatar_path as peer_avatar_url,
    cr.last_message,
    cr.last_message_at,
    cr.unread_count,
    cr.is_locked,
    true as is_circle,
    ci.id as circle_id,
    ci.name as circle_name,
    ci.avatar_path as circle_avatar_path
  from public.conversation_participants_extra cp
  join public.circles ci on ci.id = cp.circle_id
  left join public.converse_rows cr on cr.conversation_id = cp.conversation_id
  where exists (
    select 1
    from public.conversation_participants
    where conversation_id = cp.conversation_id
      and user_id = auth.uid()
  );
$$;

-- (Table and policies already defined at the top of this file)
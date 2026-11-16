-- ============================================================
-- Bro Circles: Groups and Communities
-- Issue #53: Bro Circles — Groups and Communities
--
-- Core schema for circles/groups:
-- - circles: groups/channels with metadata (name, description, avatar, privacy)
-- - circle_participants: users in each circle (maps circles to conversations)
--
-- A circle links to a conversation ID. Each conversation in a circle
-- can have multiple participants, but we maintain a "primary" participant
-- mapping for simplicity.
-- ============================================================

-- Tables
create table if not exists public.circles (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) >= 1 and length(trim(name)) <= 100),
  description text,
  avatar_path text,
  is_private boolean default false,
  creator_id uuid references auth.users(id) on delete cascade,
  created_at timestamp with time zone default timezone('utc', now()) not null,
  updated_at timestamp with time zone default timezone('utc', now()) not null
);

create table if not exists public.circle_participants (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamp with time zone default timezone('utc', now()) not null,
  is_admin boolean default false,
  unique(circle_id, user_id)
);

-- Indexes
create index if not exists idx_circles_creator_id on public.circles(creator_id);
create index if not exists idx_circles_created_at on public.circles(created_at desc);
create index if not exists idx_circles_is_private on public.circles(is_private);
create index if not exists idx_circle_participants_circle_id on public.circle_participants(circle_id);
create index if not exists idx_circle_participants_user_id on public.circle_participants(user_id);
create index if not exists idx_circle_participants_joined_at on public.circle_participants(joined_at);

-- Functions

-- Create a new circle managed by the current user
create or replace function public.create_circle(
  p_name text,
  p_description text default null,
  p_is_private boolean default false,
  p_avatar_path text default null
)
returns uuid
language sql
volatile
security definer
set search_path = ''
as $$
  insert into public.circles (name, description, is_private, avatar_path, creator_id)
  values (
    p_name,
    p_description,
    p_is_private,
    p_avatar_path,
    auth.uid()
  )
  returning id;
$$;

-- Join a circle as a participant
create or replace function public.join_circle(p_circle_id uuid)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into public.circle_participants (circle_id, user_id, is_admin)
  values (p_circle_id, auth.uid(), false)
  on conflict (circle_id, user_id) do nothing;
$$;

-- Leave a circle
create or replace function public.leave_circle(p_circle_id uuid)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  delete from public.circle_participants
  where circle_id = p_circle_id and user_id = auth.uid();
$$;

-- Get circles for the current user: circles they belong to plus public ones
create or replace function public.get_user_circles(
  p_user_id uuid default auth.uid()
)
returns table (
  circle_id uuid,
  name text,
  description text,
  avatar_path text,
  is_private boolean,
  creator_id uuid,
  created_at timestamp with time zone,
  updated_at timestamp with time zone,
  member_count int,
  is_member boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    c.id as circle_id,
    c.name,
    c.description,
    c.avatar_path,
    c.is_private,
    c.creator_id,
    c.created_at,
    c.updated_at,
    (
      select count(*)::int
      from public.circle_participants cp
      where cp.circle_id = c.id
    ) as member_count,
    exists (
      select 1
      from public.circle_participants cp_me
      where cp_me.circle_id = c.id and cp_me.user_id = auth.uid()
    ) as is_member
  from public.circles c
  where c.is_private = false
     or c.creator_id = auth.uid()
     or exists (
       select 1 from public.circle_participants cp_me
       where cp_me.circle_id = c.id and cp_me.user_id = auth.uid()
     )
  order by c.created_at desc;
$$;

-- Get all members of a circle
create or replace function public.get_circle_members(p_circle_id uuid)
returns table (
  user_id uuid,
  display_name text,
  username text,
  avatar_url text,
  joined_at timestamp with time zone,
  is_admin boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    cp.user_id,
    vp.display_name,
    vp.username,
    vp.avatar_url,
    cp.joined_at,
    cp.is_admin
  from public.circle_participants cp
  join public.visible_profiles vp on vp.id = cp.user_id
  where cp.circle_id = p_circle_id
  order by cp.is_admin desc nulls last, cp.joined_at;
$$;

-- RLS Policies

-- Circles: users can see all circles (including private ones for members)
create policy "Users can view circles"
  on public.circles for select
  using (auth.uid() is not null);

-- Creators can update their circles
create policy "Circle creators can update circles"
  on public.circles for update
  using (creator_id = auth.uid())
  with check (creator_id = auth.uid());

-- Users can create circles
create policy "Users can create circles"
  on public.circles for insert
  with check (creator_id = auth.uid());

-- Anyone can delete their own circles
create policy "Circle owners can delete circles"
  on public.circles for delete
  using (creator_id = auth.uid());

-- Circle participants: members see co-members; public circles are open
create policy "Members can view circle participants"
  on public.circle_participants for select
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.circles c
      where c.id = circle_participants.circle_id
        and (
          c.is_private = false
          or c.creator_id = auth.uid()
          or exists (
            select 1
            from public.circle_participants cp_self
            where cp_self.circle_id = c.id
              and cp_self.user_id = auth.uid()
          )
        )
    )
  );

-- Users can insert their own participation
create policy "Users can join circles"
  on public.circle_participants for insert
  with check (user_id = auth.uid());

-- Users can delete their own participation
create policy "Users can leave circles"
  on public.circle_participants for delete
  using (user_id = auth.uid());

-- Triggers for updated_at
create or replace function public.update_updated_at_column()
returns trigger as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$ language plpgsql;

create trigger handle_updated_at before update
  on public.circles
  for each row execute function public.update_updated_at_column();
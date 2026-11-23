-- Circle invitations and server-side member management.
-- The mobile/web client must not write circle_participants directly: membership
-- changes need an authorization check that cannot be bypassed by a modified
-- client. All functions are SECURITY DEFINER with an empty search_path and are
-- granted only to authenticated users.

create table if not exists public.circle_invites (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  invitee_id uuid not null references auth.users(id) on delete cascade,
  inviter_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  unique (circle_id, invitee_id)
);

create index if not exists circle_invites_invitee_idx
  on public.circle_invites (invitee_id, status, created_at desc);
create index if not exists circle_invites_circle_idx
  on public.circle_invites (circle_id, status);

alter table public.circle_invites enable row level security;
revoke all on public.circle_invites from public, anon, authenticated;
grant select on public.circle_invites to authenticated;

drop policy if exists "Circle invite participants read" on public.circle_invites;
create policy "Circle invite participants read" on public.circle_invites
  for select to authenticated using (
    invitee_id = (select auth.uid())
    or inviter_id = (select auth.uid())
    or exists (
      select 1 from public.circle_participants cp
      where cp.circle_id = public.circle_invites.circle_id
        and cp.user_id = (select auth.uid())
        and cp.is_admin is true
    )
  );

-- Invite a user to a circle. Only the creator or an admin may invite.
create or replace function public.invite_to_circle(
  p_circle_id uuid,
  p_user_id uuid
) returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_circle public.circles;
  v_invite_id uuid;
begin
  if me is null then
    raise exception using errcode = '42501', message = 'Not authenticated';
  end if;
  if p_user_id is null or p_user_id = me then
    raise exception using errcode = '22023', message = 'Choose another user';
  end if;

  select * into v_circle from public.circles where id = p_circle_id;
  if not found then
    raise exception using errcode = '42501', message = 'Circle unavailable';
  end if;
  if v_circle.creator_id <> me and not exists (
    select 1 from public.circle_participants cp
    where cp.circle_id = p_circle_id and cp.user_id = me and cp.is_admin is true
  ) then
    raise exception using errcode = '42501', message = 'Only circle admins can invite';
  end if;
  if not exists (select 1 from auth.users where id = p_user_id) then
    raise exception using errcode = '22023', message = 'User not found';
  end if;
  if exists (
    select 1 from public.circle_participants cp
    where cp.circle_id = p_circle_id and cp.user_id = p_user_id
  ) then
    raise exception using errcode = '22023', message = 'Already a member';
  end if;
  if exists (
    select 1 from public.blocked_users b
    where (b.blocker_id, b.blocked_id) in ((me, p_user_id), (p_user_id, me))
  ) then
    raise exception using errcode = '42501', message = 'Invite unavailable';
  end if;

  insert into public.circle_invites (circle_id, invitee_id, inviter_id, status, created_at, responded_at)
  values (p_circle_id, p_user_id, me, 'pending', now(), null)
  on conflict (circle_id, invitee_id) do update
    set inviter_id = excluded.inviter_id,
        status = 'pending',
        created_at = excluded.created_at,
        responded_at = null
  returning id into v_invite_id;
  return v_invite_id;
end $$;

-- Invites addressed to the signed-in user, with the circle context the UI needs.
create or replace function public.circle_pending_invites()
returns table (
  invite_id uuid,
  circle_id uuid,
  circle_name text,
  avatar_path text,
  inviter_name text,
  created_at timestamptz
)
language sql
volatile
security definer
set search_path = ''
as $$
  select i.id, c.id, c.name, c.avatar_path,
         coalesce(nullif(p.display_name, ''), p.username, 'Someone') as inviter_name,
         i.created_at
  from public.circle_invites i
  join public.circles c on c.id = i.circle_id
  left join public.profiles p on p.id = i.inviter_id
  where i.invitee_id = auth.uid() and i.status = 'pending'
  order by i.created_at desc;
$$;

-- Pending invites for a circle, for its creator and admins.
create or replace function public.circle_invites_for_circle(p_circle_id uuid)
returns table (
  invite_id uuid,
  invitee_id uuid,
  invitee_name text,
  created_at timestamptz
)
language sql
volatile
security definer
set search_path = ''
as $$
  select i.id, i.invitee_id,
         coalesce(nullif(p.display_name, ''), p.username, 'Someone') as invitee_name,
         i.created_at
  from public.circle_invites i
  left join public.profiles p on p.id = i.invitee_id
  where i.circle_id = p_circle_id and i.status = 'pending'
    and (
      exists (select 1 from public.circles c
              where c.id = p_circle_id and c.creator_id = auth.uid())
      or exists (select 1 from public.circle_participants cp
                 where cp.circle_id = p_circle_id
                   and cp.user_id = auth.uid() and cp.is_admin is true)
    )
  order by i.created_at desc;
$$;

create or replace function public.accept_circle_invite(p_invite_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_invite public.circle_invites;
begin
  select * into v_invite from public.circle_invites where id = p_invite_id for update;
  if not found or v_invite.invitee_id <> auth.uid() or v_invite.status <> 'pending' then
    raise exception using errcode = '42501', message = 'Invite unavailable';
  end if;
  if exists (
    select 1 from public.blocked_users b
    where (b.blocker_id, b.blocked_id) in
      ((v_invite.inviter_id, auth.uid()), (auth.uid(), v_invite.inviter_id))
  ) then
    raise exception using errcode = '42501', message = 'Invite unavailable';
  end if;

  insert into public.circle_participants (circle_id, user_id, is_admin)
  values (v_invite.circle_id, auth.uid(), false)
  on conflict (circle_id, user_id) do nothing;

  update public.circle_invites
    set status = 'accepted', responded_at = now()
  where id = p_invite_id;
end $$;

create or replace function public.decline_circle_invite(p_invite_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  update public.circle_invites
    set status = 'declined', responded_at = now()
  where id = p_invite_id and invitee_id = auth.uid() and status = 'pending';
  if not found then
    raise exception using errcode = '42501', message = 'Invite unavailable';
  end if;
end $$;

-- Admin-only removal. The creator cannot be removed from their own circle.
create or replace function public.remove_circle_member(
  p_circle_id uuid,
  p_user_id uuid
) returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_circle public.circles;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Not authenticated';
  end if;
  select * into v_circle from public.circles where id = p_circle_id;
  if not found then
    raise exception using errcode = '42501', message = 'Circle unavailable';
  end if;
  if v_circle.creator_id <> auth.uid() and not exists (
    select 1 from public.circle_participants cp
    where cp.circle_id = p_circle_id and cp.user_id = auth.uid() and cp.is_admin is true
  ) then
    raise exception using errcode = '42501', message = 'Only circle admins can remove members';
  end if;
  if p_user_id = v_circle.creator_id then
    raise exception using errcode = '42501', message = 'The creator cannot be removed';
  end if;

  delete from public.circle_participants
    where circle_id = p_circle_id and user_id = p_user_id;
  delete from public.circle_invites
    where circle_id = p_circle_id and invitee_id = p_user_id and status = 'pending';
end $$;

-- Single-circle read. Avoids fetching every visible circle to find one row.
create or replace function public.get_circle(p_circle_id uuid)
returns table (
  circle_id uuid,
  name text,
  description text,
  avatar_path text,
  is_private boolean,
  creator_id uuid,
  created_at timestamptz,
  updated_at timestamptz,
  member_count int,
  is_member boolean
)
language sql
volatile
security definer
set search_path = ''
as $$
  select c.id, c.name, c.description, c.avatar_path, c.is_private,
         c.creator_id, c.created_at, c.updated_at,
         (select count(*)::int from public.circle_participants cp
          where cp.circle_id = c.id) as member_count,
         exists (select 1 from public.circle_participants cp
                 where cp.circle_id = c.id and cp.user_id = auth.uid()) as is_member
  from public.circles c
  where c.id = p_circle_id
    and (
      c.is_private is not true
      or c.creator_id = auth.uid()
      or exists (select 1 from public.circle_participants cp
                 where cp.circle_id = c.id and cp.user_id = auth.uid())
    );
$$;

revoke all on function
  public.invite_to_circle(uuid, uuid),
  public.circle_pending_invites(),
  public.circle_invites_for_circle(uuid),
  public.accept_circle_invite(uuid),
  public.decline_circle_invite(uuid),
  public.remove_circle_member(uuid, uuid),
  public.get_circle(uuid)
  from public, anon;
grant execute on function
  public.invite_to_circle(uuid, uuid),
  public.circle_pending_invites(),
  public.circle_invites_for_circle(uuid),
  public.accept_circle_invite(uuid),
  public.decline_circle_invite(uuid),
  public.remove_circle_member(uuid, uuid),
  public.get_circle(uuid)
  to authenticated;

alter table public.profiles
  add column if not exists about text,
  add column if not exists photo_visibility text not null default 'everyone'
    check (photo_visibility in ('everyone', 'contacts', 'nobody')),
  add column if not exists status_visibility text not null default 'everyone'
    check (status_visibility in ('everyone', 'contacts', 'nobody')),
  add column if not exists about_visibility text not null default 'everyone'
    check (about_visibility in ('everyone', 'contacts', 'nobody')),
  add column if not exists last_seen_at timestamptz;

create table if not exists public.user_follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  followed_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followed_id),
  check (follower_id <> followed_id)
);
alter table public.user_follows enable row level security;
drop policy if exists "Users read follow edges" on public.user_follows;
create policy "Users read follow edges" on public.user_follows
  for select to authenticated using (true);
drop policy if exists "Users manage own follows" on public.user_follows;
create policy "Users manage own follows" on public.user_follows
  for all to authenticated using (follower_id = auth.uid())
  with check (follower_id = auth.uid());

create table if not exists public.statuses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  content text,
  media_path text,
  mood text,
  privacy text not null default 'contacts'
    check (privacy in ('everyone', 'contacts', 'followers')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours',
  check (content is not null or media_path is not null or mood is not null)
);
create index if not exists statuses_expiry_idx on public.statuses(expires_at);
alter table public.statuses enable row level security;
drop policy if exists "Users read visible active statuses" on public.statuses;
create policy "Users read visible active statuses" on public.statuses
  for select to authenticated using (
    expires_at > now() and (user_id = auth.uid() or privacy = 'everyone' or
      (privacy = 'contacts' and exists (
        select 1 from public.conversation_participants a
        join public.conversation_participants b using (conversation_id)
        where a.user_id = auth.uid() and b.user_id = statuses.user_id
      )) or (privacy = 'followers' and exists (
        select 1 from public.user_follows f
        where f.follower_id = auth.uid() and f.followed_id = statuses.user_id
      )))
  );
drop policy if exists "Users create own statuses" on public.statuses;
create policy "Users create own statuses" on public.statuses
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "Users delete own statuses" on public.statuses;
create policy "Users delete own statuses" on public.statuses
  for delete to authenticated using (user_id = auth.uid());

create or replace function public.record_last_seen()
returns void language sql security definer set search_path = '' as $$
  update public.profiles set last_seen_at = now()
  where id = auth.uid();
$$;

-- Close Friends lists for status audiences.
create table if not exists public.close_friend_members (
  owner_id uuid not null references auth.users(id) on delete cascade,
  friend_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, friend_id),
  check (owner_id <> friend_id)
);

alter table public.close_friend_members enable row level security;

drop policy if exists "Users manage own close friends" on public.close_friend_members;
create policy "Users manage own close friends" on public.close_friend_members
  for all to authenticated
  using (owner_id = auth.uid() or friend_id = auth.uid())
  with check (owner_id = auth.uid());

alter table public.statuses drop constraint if exists statuses_privacy_check;
alter table public.statuses
  add constraint statuses_privacy_check
  check (privacy in ('everyone', 'contacts', 'followers', 'close_friends'));

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
      )) or (privacy = 'close_friends' and exists (
        select 1 from public.close_friend_members c
        where c.owner_id = statuses.user_id and c.friend_id = auth.uid()
      )))
  );

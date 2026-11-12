-- ============================================================
-- Block / report / contacts
--
-- Supa.blockUser, Supa.reportUser, Supa.areContacts and Supa.addContact were
-- added with the Block/Report feature, but the tables they write to were never
-- created. PostgREST answered every call with
--   "relation public.blocked_users does not exist"
-- so blocking and message-request detection silently failed at runtime.
-- ============================================================

-- ------------------------------------------------------------------
-- blocked_users
-- ------------------------------------------------------------------
create table if not exists public.blocked_users (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocked_users_not_self check (blocker_id <> blocked_id)
);

create index if not exists blocked_users_blocked_idx
  on public.blocked_users (blocked_id);

alter table public.blocked_users enable row level security;

drop policy if exists "Users read own blocks" on public.blocked_users;
create policy "Users read own blocks" on public.blocked_users
  for select to authenticated using (blocker_id = auth.uid());

drop policy if exists "Users create own blocks" on public.blocked_users;
create policy "Users create own blocks" on public.blocked_users
  for insert to authenticated with check (blocker_id = auth.uid());

drop policy if exists "Users delete own blocks" on public.blocked_users;
create policy "Users delete own blocks" on public.blocked_users
  for delete to authenticated using (blocker_id = auth.uid());

-- ------------------------------------------------------------------
-- user_reports (write-only from the app's point of view)
-- ------------------------------------------------------------------
create table if not exists public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_id uuid not null references auth.users(id) on delete cascade,
  reason text not null,
  details text,
  created_at timestamptz not null default now(),
  constraint user_reports_not_self check (reporter_id <> reported_id)
);

create index if not exists user_reports_reported_idx
  on public.user_reports (reported_id, created_at desc);

alter table public.user_reports enable row level security;

drop policy if exists "Users create own reports" on public.user_reports;
create policy "Users create own reports" on public.user_reports
  for insert to authenticated with check (reporter_id = auth.uid());

drop policy if exists "Users read own reports" on public.user_reports;
create policy "Users read own reports" on public.user_reports
  for select to authenticated using (reporter_id = auth.uid());

-- ------------------------------------------------------------------
-- contacts: accepted connections used by the message-requests check.
-- `areContacts` queries with an OR across both directions, so a single
-- accepted row is enough.
-- ------------------------------------------------------------------
create table if not exists public.contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  contact_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'accepted'
    check (status in ('pending', 'accepted', 'declined', 'blocked')),
  created_at timestamptz not null default now(),
  unique (user_id, contact_id),
  constraint contacts_not_self check (user_id <> contact_id)
);

create index if not exists contacts_contact_idx
  on public.contacts (contact_id);

alter table public.contacts enable row level security;

drop policy if exists "Users read own contacts" on public.contacts;
create policy "Users read own contacts" on public.contacts
  for select to authenticated using (
    user_id = auth.uid() or contact_id = auth.uid()
  );

drop policy if exists "Users create own contacts" on public.contacts;
create policy "Users create own contacts" on public.contacts
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "Users update own contacts" on public.contacts;
create policy "Users update own contacts" on public.contacts
  for update to authenticated using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "Users delete own contacts" on public.contacts;
create policy "Users delete own contacts" on public.contacts
  for delete to authenticated using (user_id = auth.uid());

-- ------------------------------------------------------------------
-- Enforce blocks inside DM creation and message inserts so a blocked
-- user cannot keep talking just because the UI stopped rendering.
-- ------------------------------------------------------------------
create or replace function public.is_blocked_pair(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.blocked_users
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a)
  );
$$;

grant execute on function public.is_blocked_pair(uuid, uuid) to authenticated;

create or replace function public.reject_blocked_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- A block hides the conversation from the blocker and stops the blocked
  -- person from writing into it. Only the blocked side is rejected here: the
  -- blocker keeps their own send path so the UI does not dead-end if they
  -- reopen the chat before unblocking.
  if exists (
    select 1
      from public.conversation_participants cp
      join public.blocked_users bu
        on bu.blocker_id = cp.user_id
       and bu.blocked_id = new.sender_id
     where cp.conversation_id = new.conversation_id
       and cp.user_id <> new.sender_id
  ) then
    raise exception 'this conversation is unavailable';
  end if;
  return new;
end;
$$;

drop trigger if exists reject_blocked_message on public.messages;
create trigger reject_blocked_message
  before insert on public.messages
  for each row execute function public.reject_blocked_message();

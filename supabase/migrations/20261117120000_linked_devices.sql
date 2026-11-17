-- Durable, user-scoped registry for BRO installations.
-- Registry rows describe known devices; they do not contain or revoke auth tokens.
create table if not exists public.linked_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  device_name text not null,
  platform text not null,
  created_at timestamptz not null default timezone('utc'::text, now()),
  last_seen_at timestamptz not null default timezone('utc'::text, now()),
  revoked_at timestamptz,
  unique (user_id, device_id)
);

comment on table public.linked_devices is
  'User-visible device registry. It is not an auth session/token store.';
comment on column public.linked_devices.revoked_at is
  'When this registry entry was removed or invalidated by the account owner.';

alter table public.linked_devices enable row level security;

drop policy if exists "Users read own linked devices" on public.linked_devices;
create policy "Users read own linked devices"
  on public.linked_devices
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "Users register own devices" on public.linked_devices;
create policy "Users register own devices"
  on public.linked_devices
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "Users update own linked devices" on public.linked_devices;
create policy "Users update own linked devices"
  on public.linked_devices
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update on public.linked_devices to authenticated;

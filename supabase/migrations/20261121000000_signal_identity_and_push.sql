-- BRO Signal Protocol device identity, prekeys, verification and push lifecycle.
-- Public key material is stored here. Private keys MUST NEVER be uploaded.

-- Device identity. device_id follows Signal's 1..127 address range.
create table if not exists public.signal_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id integer not null check (device_id between 1 and 127),
  identity_key bytea not null check (octet_length(identity_key) between 32 and 256),
  registration_id integer not null check (registration_id > 0),
  signed_prekey_id integer not null,
  signed_prekey bytea not null check (octet_length(signed_prekey) between 32 and 256),
  signed_prekey_signature bytea not null check (octet_length(signed_prekey_signature) > 0),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (user_id, device_id)
);
create index if not exists signal_devices_user_idx on public.signal_devices(user_id);

create table if not exists public.signal_one_time_prekeys (
  id bigint generated always as identity primary key,
  device_row_id uuid not null references public.signal_devices(id) on delete cascade,
  prekey_id integer not null check (prekey_id > 0),
  public_key bytea not null check (octet_length(public_key) between 32 and 256),
  used_at timestamptz,
  created_at timestamptz not null default now(),
  unique (device_row_id, prekey_id)
);
create index if not exists signal_prekeys_device_idx
  on public.signal_one_time_prekeys(device_row_id) where used_at is null;

-- Post-quantum Kyber prekeys are required by libsignal 0.106 bundles.
create table if not exists public.signal_kyber_prekeys (
  id bigint generated always as identity primary key,
  device_row_id uuid not null references public.signal_devices(id) on delete cascade,
  prekey_id integer not null check (prekey_id > 0),
  public_key bytea not null check (octet_length(public_key) > 0),
  signature bytea not null check (octet_length(signature) > 0),
  used_at timestamptz,
  created_at timestamptz not null default now(),
  unique (device_row_id, prekey_id)
);

create table if not exists public.signal_verified_identities (
  user_id uuid not null references auth.users(id) on delete cascade,
  peer_user_id uuid not null references auth.users(id) on delete cascade,
  fingerprint text not null check (length(fingerprint) between 8 and 256),
  verified_at timestamptz not null default now(),
  primary key (user_id, peer_user_id)
);

create table if not exists public.push_tokens (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null check (length(device_id) between 1 and 128),
  token text not null check (length(token) between 8 and 1024),
  platform text not null check (platform in ('android', 'iOS', 'web')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, device_id)
);

-- Existing installations stored a Firebase Installation ID in push_tokens.
-- FCM HTTP v1 delivery requires a real registration token, so add the new
-- columns without destroying the old rows. Legacy rows are ignored by the
-- sender until clients re-register.
alter table public.push_tokens add column if not exists device_id text;
alter table public.push_tokens add column if not exists token text;
create unique index if not exists push_tokens_user_device_idx
  on public.push_tokens(user_id, device_id) where device_id is not null;
create index if not exists push_tokens_token_idx
  on public.push_tokens(token) where token is not null;

create table if not exists public.web_push_subscriptions (
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null check (length(endpoint) between 8 and 2048),
  p256dh text not null check (length(p256dh) between 8 and 512),
  auth_token text not null check (length(auth_token) between 8 and 512),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, endpoint)
);

create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  show_previews boolean not null default false,
  show_sender boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.notification_deliveries (
  idempotency_key text primary key check (length(idempotency_key) between 8 and 256),
  user_id uuid not null references auth.users(id) on delete cascade,
  message_id uuid,
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed', 'invalid_token')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists notification_deliveries_user_idx
  on public.notification_deliveries(user_id);

alter table public.signal_devices enable row level security;
alter table public.signal_one_time_prekeys enable row level security;
alter table public.signal_kyber_prekeys enable row level security;
alter table public.signal_verified_identities enable row level security;
alter table public.push_tokens enable row level security;
alter table public.web_push_subscriptions enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.notification_deliveries enable row level security;

-- Public keys must be readable so sessions can be established. No private key
-- data exists in these tables.
drop policy if exists "Signal devices public read" on public.signal_devices;
create policy "Signal devices public read" on public.signal_devices
  for select to authenticated using (revoked_at is null);
drop policy if exists "Signal devices owner write" on public.signal_devices;
create policy "Signal devices owner write" on public.signal_devices
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Signal prekeys public read" on public.signal_one_time_prekeys;
create policy "Signal prekeys public read" on public.signal_one_time_prekeys
  for select to authenticated using (used_at is null);
drop policy if exists "Signal prekeys owner write" on public.signal_one_time_prekeys;
create policy "Signal prekeys owner write" on public.signal_one_time_prekeys
  for all to authenticated using (
    exists (select 1 from public.signal_devices d
            where d.id = device_row_id and d.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.signal_devices d
            where d.id = device_row_id and d.user_id = auth.uid())
  );

drop policy if exists "Signal kyber prekeys public read" on public.signal_kyber_prekeys;
create policy "Signal kyber prekeys public read" on public.signal_kyber_prekeys
  for select to authenticated using (used_at is null);
drop policy if exists "Signal kyber prekeys owner write" on public.signal_kyber_prekeys;
create policy "Signal kyber prekeys owner write" on public.signal_kyber_prekeys
  for all to authenticated using (
    exists (select 1 from public.signal_devices d
            where d.id = device_row_id and d.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.signal_devices d
            where d.id = device_row_id and d.user_id = auth.uid())
  );

drop policy if exists "Verified identities owner" on public.signal_verified_identities;
create policy "Verified identities owner" on public.signal_verified_identities
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Push tokens owner" on public.push_tokens;
create policy "Push tokens owner" on public.push_tokens
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Web push subscriptions owner" on public.web_push_subscriptions;
create policy "Web push subscriptions owner" on public.web_push_subscriptions
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Notification preferences owner" on public.notification_preferences;
create policy "Notification preferences owner" on public.notification_preferences
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Deliveries are service-role only. No RLS policy is granted to authenticated.

-- Atomically reserve an unused one-time prekey belonging to the caller.
create or replace function public.signal_claim_prekey(p_device_row_id uuid)
returns table(prekey_id integer, public_key bytea)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'unauthenticated call';
  end if;
  if not exists (
    select 1 from public.signal_devices d
    where d.id = p_device_row_id and d.user_id = auth.uid() and d.revoked_at is null
  ) then
    raise exception 'not your device';
  end if;
  return query
  with claimed as (
    select k.id
    from public.signal_one_time_prekeys k
    where k.device_row_id = p_device_row_id and k.used_at is null
    order by k.prekey_id
    limit 1
    for update skip locked
  )
  update public.signal_one_time_prekeys k
     set used_at = now()
    from claimed
   where k.id = claimed.id
  returning k.prekey_id, k.public_key;
end;
$$;
revoke all on function public.signal_claim_prekey(uuid) from public, anon;
grant execute on function public.signal_claim_prekey(uuid) to authenticated;

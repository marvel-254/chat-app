-- User-controlled push preferences. Notification content remains generic and
-- never includes message plaintext, ciphertext or caller identity.

create table if not exists public.notification_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  missed_call_push boolean not null default true,
  message_push boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.notification_settings enable row level security;

drop policy if exists "users manage own notification settings"
  on public.notification_settings;
create policy "users manage own notification settings"
  on public.notification_settings
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update, delete on public.notification_settings to authenticated;

-- Per-user chat canvas preference, shared across the user's signed-in devices.
alter table public.profiles
  add column if not exists chat_background text not null default 'default';

alter table public.profiles
  drop constraint if exists profiles_chat_background_check;
alter table public.profiles
  add constraint profiles_chat_background_check
  check (chat_background in ('default', 'ocean', 'forest', 'plum', 'ember'));

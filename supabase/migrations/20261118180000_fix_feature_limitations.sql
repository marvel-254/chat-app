-- ============================================================
-- Fix limitations from #66 / #72 / #74:
--  1. "Remind annually" on friendship dates now sends a push.
--  2. Game presence becomes realtime via the profiles table.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Annual friendship-date reminders
-- ------------------------------------------------------------
-- One row per (date, year) so a cron re-run on the same day cannot
-- send the same reminder twice.
create table if not exists public.friendship_reminder_log (
  date_id uuid not null references public.friendship_dates(id) on delete cascade,
  sent_for date not null,
  sent_at timestamptz not null default now(),
  primary key (date_id, sent_for)
);

alter table public.friendship_reminder_log enable row level security;
-- No client policies: this table is server-only (SECURITY DEFINER + cron).

-- Send due reminders through the existing push edge function, reusing the
-- vault-stored webhook URL/secret. A generic body keeps private date titles
-- off the lock screen.
create or replace function public.dispatch_friendship_reminders()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  endpoint text;
  webhook_secret text;
  due record;
begin
  select decrypted_secret into endpoint
    from vault.decrypted_secrets where name = 'push_webhook_url' limit 1;
  select decrypted_secret into webhook_secret
    from vault.decrypted_secrets where name = 'push_webhook_secret' limit 1;

  if endpoint is null or webhook_secret is null then
    return;
  end if;

  for due in
    select d.id, d.conversation_id, d.title, d.owner_id
      from public.friendship_dates d
     where d.remind_annually
       and date_part('month', d.occurs_on) = date_part('month', current_date)
       and date_part('day', d.occurs_on) = date_part('day', current_date)
       and not exists (
         select 1 from public.friendship_reminder_log l
          where l.date_id = d.id and l.sent_for = current_date
       )
  loop
    perform net.http_post(
      url := endpoint,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-bro-webhook-secret', webhook_secret
      ),
      body := jsonb_build_object(
        'type', 'INSERT',
        'schema', 'public',
        'table', 'messages',
        'record', jsonb_build_object(
          'id', due.id,
          'conversation_id', due.conversation_id,
          'sender_id', due.owner_id,
          'reminder_title', due.title
        )
      )
    );
    insert into public.friendship_reminder_log (date_id, sent_for)
      values (due.id, current_date)
      on conflict do nothing;
  end loop;
end;
$$;

revoke all on function public.dispatch_friendship_reminders() from public, anon, authenticated;

-- Daily at 08:00 UTC. Idempotent: re-runs are deduped by the log table.
do $cron$
begin
  if not exists (
    select 1 from pg_extension where extname = 'pg_cron'
  ) then
    return;
  end if;
  if not exists (
    select 1 from cron.job where jobname = 'friendship-annual-reminders'
  ) then
    perform cron.schedule(
      'friendship-annual-reminders',
      '0 8 * * *',
      $$select public.dispatch_friendship_reminders()$$
    );
  end if;
end;
$cron$;

-- ------------------------------------------------------------
-- 2. Realtime game presence
-- ------------------------------------------------------------
-- profiles is readable by all clients, so it can carry replica identity
-- for realtime UPDATE events. The poll in Presence remains as a fallback.
alter table public.profiles replica identity full;

do $pub$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and tablename = 'profiles'
  ) then
    alter publication supabase_realtime add table public.profiles;
  end if;
end;
$pub$;

-- ------------------------------------------------------------
-- 3. Digital avatar config in profile queries
-- ------------------------------------------------------------
-- Expose avatar_config through visible_profiles with the same
-- photo_visibility masking used for avatar_url, so chat lists and headers
-- get it with the profile row they already fetch (no per-surface RPC).
-- This is the last view definition; it must include every column from the
-- gaming-profiles migration plus avatar_config.
create or replace view public.visible_profiles
with (security_barrier = true, security_invoker = false) as
  select
    p.id,
    p.username,
    p.display_name,
    case
      when p.id = auth.uid() then p.about
      when p.about_visibility = 'everyone' then p.about
      when p.about_visibility = 'contacts'
        and public.shares_conversation(auth.uid(), p.id) then p.about
      else null
    end as about,
    case
      when p.id = auth.uid() then p.avatar_url
      when p.photo_visibility = 'everyone' then p.avatar_url
      when p.photo_visibility = 'contacts'
        and public.shares_conversation(auth.uid(), p.id) then p.avatar_url
      else null
    end as avatar_url,
    p.chat_background,
    p.chat_background_image_path,
    p.created_at,
    p.updated_at,
    p.photo_visibility,
    p.status_visibility,
    p.about_visibility,
    case
      when p.id = auth.uid() then p.last_seen_at
      when p.status_visibility = 'everyone' then p.last_seen_at
      when p.status_visibility = 'contacts'
        and public.shares_conversation(auth.uid(), p.id) then p.last_seen_at
      else null
    end as last_seen_at,
    p.read_receipts_enabled,
    p.default_message_expiry,
    case
      when p.id = auth.uid() then p.auto_lock_timer
      else null
    end as auto_lock_timer,
    p.profile_color,
    case
      when p.id = auth.uid() then p.cover_image_path
      when p.photo_visibility = 'everyone' then p.cover_image_path
      when p.photo_visibility = 'contacts'
        and public.shares_conversation(auth.uid(), p.id) then p.cover_image_path
      else null
    end as cover_image_path,
    case
      when p.id = auth.uid() then p.profile_music_path
      when p.status_visibility = 'everyone' then p.profile_music_path
      when p.status_visibility = 'contacts'
        and public.shares_conversation(auth.uid(), p.id) then p.profile_music_path
      else null
    end as profile_music_path,
    case
      when p.id = auth.uid() then p.profile_music_name
      when p.status_visibility = 'everyone' then p.profile_music_name
      when p.status_visibility = 'contacts'
        and public.shares_conversation(auth.uid(), p.id) then p.profile_music_name
      else null
    end as profile_music_name,
    case
      when p.id = auth.uid() then p.profile_status
      when p.status_visibility = 'everyone' then p.profile_status
      when p.status_visibility = 'contacts'
        and public.shares_conversation(auth.uid(), p.id) then p.profile_status
      else null
    end as profile_status,
    case
      when p.id = auth.uid() then p.animated_avatar_enabled
      when p.photo_visibility = 'everyone' then p.animated_avatar_enabled
      when p.photo_visibility = 'contacts'
        and public.shares_conversation(auth.uid(), p.id)
        then p.animated_avatar_enabled
      else false
    end as animated_avatar_enabled,
    case
      when p.id = auth.uid() then p.animated_avatar_path
      when p.photo_visibility = 'everyone' then p.animated_avatar_path
      when p.photo_visibility = 'contacts'
        and public.shares_conversation(auth.uid(), p.id) then p.animated_avatar_path
      else null
    end as animated_avatar_path,
    case
      when p.id = auth.uid() then p.game_platform
      when p.game_visibility = 'everyone' then p.game_platform
      when p.game_visibility = 'contacts'
        and public.shares_conversation(auth.uid(), p.id) then p.game_platform
      else null
    end as game_platform,
    case
      when p.id = auth.uid() then p.game_username
      when p.game_visibility = 'everyone' then p.game_username
      when p.game_visibility = 'contacts'
        and public.shares_conversation(auth.uid(), p.id) then p.game_username
      else null
    end as game_username,
    case
      when p.id = auth.uid() then p.game_status
      when p.game_visibility = 'everyone' then p.game_status
      when p.game_visibility = 'contacts'
        and public.shares_conversation(auth.uid(), p.id) then p.game_status
      else null
    end as game_status,
    p.game_visibility,
    case
      when p.id = auth.uid() then p.avatar_config
      when p.photo_visibility = 'everyone' then p.avatar_config
      when p.photo_visibility = 'contacts'
        and public.shares_conversation(auth.uid(), p.id) then p.avatar_config
      else null
    end as avatar_config
  from public.profiles p;

notify pgrst, 'reload schema';

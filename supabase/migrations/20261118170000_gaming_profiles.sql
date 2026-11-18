-- ============================================================
-- Gaming Profiles: Game presence for friends
-- Issue #72: Show game presence for friends - let users display
-- their usernames and what game they are currently playing.
-- ============================================================

-- Add gaming columns to profiles
alter table public.profiles
  add column if not exists game_platform text
    check (game_platform in ('steam', 'xbox', 'playstation', 'nintendo', 'battle_net', 'epic', 'riot', 'ubisoft', 'ea', 'gog', 'custom')),
  add column if not exists game_username text,
  add column if not exists game_status text,
  add column if not exists game_visibility text not null default 'everyone'
    check (game_visibility in ('everyone', 'contacts', 'nobody'));

-- Constraint: game_username required when game_platform is set
alter table public.profiles
  drop constraint if exists profiles_game_username_check;

alter table public.profiles
  add constraint profiles_game_username_check
    check (
      (game_platform is null and game_username is null)
      or (game_platform is not null and game_username is not null and char_length(game_username) <= 50)
    );

-- Constraint: game_status length
alter table public.profiles
  drop constraint if exists profiles_game_status_length_check;

alter table public.profiles
  add constraint profiles_game_status_length_check
    check (game_status is null or char_length(game_status) <= 100);

-- Update visible_profiles view to include gaming fields with privacy masking
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
        and public.shares_conversation(auth.uid(), p.id)
        then p.animated_avatar_path
      else null
    end as animated_avatar_path,
    -- Gaming fields
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
    p.game_visibility
  from public.profiles p;

grant select on public.visible_profiles to anon, authenticated;

notify pgrst, 'reload schema';
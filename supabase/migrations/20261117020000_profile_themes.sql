-- Profile themes: presentation fields, owned media paths, and a short status line.
alter table public.profiles
  add column if not exists profile_color text not null default '#D4FF00',
  add column if not exists cover_image_path text,
  add column if not exists profile_music_path text,
  add column if not exists profile_music_name text,
  add column if not exists animated_avatar_enabled boolean not null default false,
  add column if not exists animated_avatar_path text,
  add column if not exists profile_status text;

alter table public.profiles
  drop constraint if exists profiles_profile_color_check,
  drop constraint if exists profiles_profile_status_length_check,
  drop constraint if exists profiles_profile_media_paths_check;

alter table public.profiles
  add constraint profiles_profile_color_check
    check (profile_color ~ '^#[0-9A-Fa-f]{6}$'),
  add constraint profiles_profile_status_length_check
    check (profile_status is null or char_length(profile_status) <= 80),
  add constraint profiles_profile_media_paths_check
    check (
      (cover_image_path is null or
        cover_image_path ~ ('^' || id::text || '/cover\.(jpg|jpeg|png|webp)$'))
      and (profile_music_path is null or
        profile_music_path ~ ('^' || id::text || '/profile-music\.(mp3|m4a|aac|wav|ogg|webm)$'))
      and (animated_avatar_path is null or
        animated_avatar_path = id::text || '/animated-avatar.gif')
    );

alter table public.profiles
  alter column profile_color set default '#D4FF00';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-media',
  'profile-media',
  true,
  15728640,
  array[
    'image/jpeg', 'image/png', 'image/webp', 'image/gif',
    'audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/wav',
    'audio/ogg', 'audio/webm'
  ]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users read profile media" on storage.objects;
create policy "Users read profile media" on storage.objects
  for select to authenticated using (
    bucket_id = 'profile-media'
  );

drop policy if exists "Users upload own profile media" on storage.objects;
create policy "Users upload own profile media" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'profile-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users update own profile media" on storage.objects;
create policy "Users update own profile media" on storage.objects
  for update to authenticated using (
    bucket_id = 'profile-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  ) with check (
    bucket_id = 'profile-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users delete own profile media" on storage.objects;
create policy "Users delete own profile media" on storage.objects
  for delete to authenticated using (
    bucket_id = 'profile-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

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
    end as animated_avatar_path
  from public.profiles p;

grant select on public.visible_profiles to anon, authenticated;

notify pgrst, 'reload schema';

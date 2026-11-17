-- Add missing auto_lock_timer column and fix visible_profiles view
-- Also ensure proper grants for profile updates

-- 1. Add auto_lock_timer column to profiles
alter table public.profiles
  add column if not exists auto_lock_timer interval not null default interval '0';

-- 2. Update visible_profiles view to include auto_lock_timer
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
    p.auto_lock_timer
  from public.profiles p;
grant select on public.visible_profiles to anon, authenticated;

-- 3. Ensure UPDATE grants on all profile columns for authenticated users
-- (revoke select in previous migration may have affected column-level grants)
grant update (id, username, display_name, avatar_url, about, chat_background, 
  chat_background_image_path, photo_visibility, status_visibility, about_visibility,
  last_seen_at, read_receipts_enabled, default_message_expiry, auto_lock_timer, updated_at)
  on public.profiles to authenticated;

-- 4. Increase chat background signed URL expiry to 30 days (2592000 seconds)
-- This is handled in the client code via storage API. The fallback to 1-hour
-- signed URLs in the client still works, but 30-day URLs require the newer
-- storage API. Keeping the function commented out until the correct API is available.
-- create or replace function public.get_chat_background_signed_url(
--   p_user_id uuid,
--   p_path text
-- ) returns text
-- language sql
-- security definer
-- set search_path = public
-- as $$
--   select storage.create_signed_url('chat-backgrounds', p_path, 2592000) as signed_url;
-- $$;
-- grant execute on function public.get_chat_background_signed_url(uuid, text) to authenticated;

-- 5. Add comment for clarity
comment on column public.profiles.auto_lock_timer is 'Conversation auto-lock timeout for this user (0 = off)';
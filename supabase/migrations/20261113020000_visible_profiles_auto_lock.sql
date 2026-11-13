-- Expose auto_lock_timer on visible_profiles so Settings can read it back.
-- Only the owner sees the value; everyone else gets null.

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
    end as auto_lock_timer
  from public.profiles p;

grant select on public.visible_profiles to anon, authenticated;

notify pgrst, 'reload schema';

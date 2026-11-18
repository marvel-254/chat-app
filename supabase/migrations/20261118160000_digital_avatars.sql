-- ============================================================
-- Issue #74: 3D Digital Avatars
--
-- Stores the avatar customisation (preset, colours, expression,
-- accessory, reaction, animation flag) as jsonb on the profile row.
--
-- The config is deliberately NOT added to `visible_profiles`: that view is
-- recreated by several migrations that disagree about the gaming columns, so
-- appending to it here would make this migration order-dependent. Reads and
-- writes go through the two SECURITY DEFINER functions below instead, which
-- re-apply the same `photo_visibility` masking the view uses.
-- ============================================================

alter table public.profiles
  add column if not exists avatar_config jsonb;

alter table public.profiles
  drop constraint if exists profiles_avatar_config_check;

alter table public.profiles
  add constraint profiles_avatar_config_check
    check (
      avatar_config is null
      or (jsonb_typeof(avatar_config) = 'object'
          and octet_length(avatar_config::text) <= 8192)
    );

-- Read another user's avatar config, honouring photo_visibility.
create or replace function public.digital_avatar_config(uid uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p.id = auth.uid() then p.avatar_config
    when p.photo_visibility = 'everyone' then p.avatar_config
    when p.photo_visibility = 'contacts'
      and public.shares_conversation(auth.uid(), p.id) then p.avatar_config
    else null
  end
  from public.profiles p
  where p.id = uid;
$$;

revoke all on function public.digital_avatar_config(uuid) from public;
grant execute on function public.digital_avatar_config(uuid) to authenticated;

-- Persist the caller's own avatar config.
create or replace function public.set_digital_avatar_config(cfg jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if cfg is null
     or jsonb_typeof(cfg) <> 'object'
     or octet_length(cfg::text) > 8192 then
    raise exception 'avatar config must be a jsonb object under 8192 bytes';
  end if;

  update public.profiles
     set avatar_config = cfg,
         updated_at = now()
   where id = auth.uid();
end;
$$;

revoke all on function public.set_digital_avatar_config(jsonb) from public;
grant execute on function public.set_digital_avatar_config(jsonb) to authenticated;

notify pgrst, 'reload schema';

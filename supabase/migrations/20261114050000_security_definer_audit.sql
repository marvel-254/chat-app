-- ============================================================
-- Issue #94: Formal Audit for SECURITY DEFINER Functions
--
-- Fixes every SECURITY DEFINER function that does not already
-- follow the security checklist:
--   1. search_path = ''  (prevent search-path hijacking)
--   2. Fully-qualified names (public.*)
--   3. Input validation (auth.uid() checks where applicable)
--
-- Audit summary (run before this migration):
--   - handle_new_user:          search_path = public  →  FIXED
--   - create_circle:            no auth check (OK — uses auth.uid() directly)
--   - join_circle / leave_circle: OK — uses auth.uid()
--   - link_circle_to_conversation:      no auth check  →  FIXED
--   - unlink_circle_from_conversation:  no auth check  →  FIXED
--   - create_conversation_for_circle:   no owner check  →  FIXED
--   - All others:               already hardened ✓
-- ============================================================

-- ============================================================
-- 1. Fix handle_new_user: search_path = public → ''
--    This function runs on auth.users insert; it must not allow
--    search-path hijacking. We also fully-qualify all names.
-- ============================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  base_username text;
  candidate     text;
  attempt       int := 0;
begin
  base_username := coalesce(nullif(new.raw_user_meta_data->>'username', ''), 'user');
  candidate := base_username;

  loop
    begin
      insert into public.profiles (id, username, display_name)
      values (new.id, candidate, base_username)
      on conflict (id) do nothing;
      exit;
    exception
      when unique_violation then
        attempt := attempt + 1;
        if attempt > 3 then
          raise;
        end if;
        candidate := base_username || '_' || left(replace(new.id::text, '-', ''), 12);
    end;
  end loop;

  return new;
end;
$$;

-- ============================================================
-- 2. Harden circle functions: add ownership / membership checks.
-- ============================================================

-- link_circle_to_conversation: only circle admins may link.
create or replace function public.link_circle_to_conversation(
  p_circle_id uuid,
  p_conversation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean;
begin
  if v_uid is null then
    raise exception 'unauthenticated call';
  end if;

  -- Verify the caller is an admin of the circle
  select cp.is_admin into v_is_admin
    from public.circle_participants cp
   where cp.circle_id = p_circle_id and cp.user_id = v_uid;

  if not v_is_admin then
    raise exception 'only circle admins may link conversations';
  end if;

  insert into public.conversation_participants_extra (conversation_id, circle_id)
  values (p_conversation_id, p_circle_id)
  on conflict (conversation_id)
  do update set circle_id = p_circle_id
  returning circle_id;
end;
$$;

-- unlink_circle_from_conversation: only circle admins may unlink.
create or replace function public.unlink_circle_from_conversation(
  p_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_circle_id uuid;
  v_is_admin boolean;
begin
  if v_uid is null then
    raise exception 'unauthenticated call';
  end if;

  select circle_id into v_circle_id
    from public.conversation_participants_extra
   where conversation_id = p_conversation_id;

  if v_circle_id is null then
    return; -- nothing to unlink
  end if;

  select cp.is_admin into v_is_admin
    from public.circle_participants cp
   where cp.circle_id = v_circle_id and cp.user_id = v_uid;

  if not v_is_admin then
    raise exception 'only circle admins may unlink conversations';
  end if;

  delete from public.conversation_participants_extra
   where conversation_id = p_conversation_id;
end;
$$;

-- create_conversation_for_circle: only circle creator may create.
create or replace function public.create_conversation_for_circle(
  p_circle_id uuid,
  p_name text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_circle_creator uuid;
  v_circle_id_out uuid;
begin
  if v_uid is null then
    raise exception 'unauthenticated call';
  end if;

  -- Create or ensure the circle exists (idempotent)
  insert into public.circles (id, name, creator_id)
  values (p_circle_id, p_name, v_uid)
  on conflict (id) do nothing
  returning id into v_circle_id_out;

  -- Verify the caller is the creator
  select creator_id into v_circle_creator
    from public.circles where id = p_circle_id;

  if v_circle_creator is null then
    raise exception 'circle not found';
  end if;

  if v_circle_creator <> v_uid then
    raise exception 'only the circle creator may create its conversation';
  end if;

  return p_circle_id;
end;
$$;

-- ============================================================
-- 3. Revoke public execute on all SECURITY DEFINER functions
--    and grant only to authenticated (defense in depth).
-- ============================================================
revoke execute on function public.handle_new_user() from public;
grant execute on function public.handle_new_user() to authenticated;

revoke execute on function public.link_circle_to_conversation(uuid, uuid) from public;
grant execute on function public.link_circle_to_conversation(uuid, uuid) to authenticated;

revoke execute on function public.unlink_circle_from_conversation(uuid) from public;
grant execute on function public.unlink_circle_from_conversation(uuid) to authenticated;

revoke execute on function public.create_conversation_for_circle(uuid, text) from public;
grant execute on function public.create_conversation_for_circle(uuid, text) to authenticated;

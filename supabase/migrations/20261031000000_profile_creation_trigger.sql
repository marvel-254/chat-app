-- ============================================================
-- Create profiles reliably for confirmation-required sign-ups.
-- Fixes #43 (and the original #3).
--
-- Problem: the client inserted the profile right after auth.signUp().
-- When email confirmation is required, signUp() returns session == null,
-- so auth.uid() is NULL and the INSERT policy ("Users insert own profile",
-- with check auth.uid() = id) rejects the row with 42501. The auth user
-- is left stranded without a profile and the UI shows a raw PostgresException.
--
-- Fix: a SECURITY DEFINER trigger on auth.users creates the profile as
-- part of the same transaction that creates the user, so it works with
-- or without an immediate session. The client no longer inserts profiles.
-- ============================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
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
        -- username is taken: derive a unique one from the user's own uuid,
        -- which is guaranteed unique per user, so this terminates.
        attempt := attempt + 1;
        if attempt > 3 then
          raise; -- give up loudly rather than loop forever
        end if;
        candidate := base_username || '_' || left(replace(new.id::text, '-', ''), 12);
    end;
  end loop;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------
-- Backfill: create profiles for users who signed up before this
-- trigger existed (stranded by the RLS bug in #43/#3).
-- ------------------------------------------------------------
do $$
declare
  u         record;
  candidate text;
begin
  for u in
    select id, raw_user_meta_data from auth.users
  loop
    if exists (select 1 from public.profiles p where p.id = u.id) then
      continue;
    end if;

    candidate := coalesce(nullif(u.raw_user_meta_data->>'username', ''), 'user');
    begin
      insert into public.profiles (id, username, display_name)
      values (u.id, candidate, candidate);
    exception
      when unique_violation then
        candidate := 'user_' || left(replace(u.id::text, '-', ''), 12);
        insert into public.profiles (id, username, display_name)
        values (u.id, candidate, candidate)
        on conflict (id) do nothing;
    end;
  end loop;
end $$;

-- ============================================================
-- Security hardening migration
-- Replaces the unsafe self-join / sender-only RLS policies from
-- 20261022000000_initial_schema.sql with membership-authorised flows.
--
-- Fixes issues #26 (profiles INSERT), #27 (participant self-join),
-- #28 (get_or_create_dm under RLS), #29 (non-member message insert).
-- ============================================================

-- ----------------------------------------------------------------
-- 1. profiles: allow a user to create their own profile on sign-up.
--    Narrowly scoped to the caller's own auth uid; no one else can
--    create or overwrite another user's profile row.
-- ----------------------------------------------------------------
drop policy if exists "Users update own profile" on profiles;
drop policy if exists "Profiles readable by all" on profiles;

create policy "Profiles readable by all" on profiles
  for select using (true);

create policy "Users insert own profile" on profiles
  for insert with check (auth.uid() = id);

create policy "Users update own profile" on profiles
  for update using (auth.uid() = id);

-- ----------------------------------------------------------------
-- 2. conversation_participants: remove the unrestricted self-join.
--    Membership is now created only through the trusted
--    get_or_create_dm function (SECURITY DEFINER), which authorises
--    both participants of a 1:1 DM. Direct INSERT/UPDATE by users is
--    no longer permitted.
-- ----------------------------------------------------------------
drop policy if exists "Users can join conversations" on conversation_participants;
drop policy if exists "Users see own participations" on conversation_participants;

create policy "Users see own participations" on conversation_participants
  for select using (user_id = auth.uid());

-- (no user-facing insert/update policy on purpose)

-- ----------------------------------------------------------------
-- 3. conversations: no user-facing insert policy. Created only by
--    the trusted get_or_create_dm function. Participants can read.
-- ----------------------------------------------------------------
drop policy if exists "Participants read conversations" on conversations;

create policy "Participants read conversations" on conversations
  for select using (
    exists (
      select 1 from conversation_participants cp
      where cp.conversation_id = id and cp.user_id = auth.uid()
    )
  );

-- ----------------------------------------------------------------
-- 4. messages: insert AND update now require active membership in
--    the target conversation, closing the non-member spam hole.
-- ----------------------------------------------------------------
drop policy if exists "Participants read messages" on messages;
drop policy if exists "Sender inserts message" on messages;
drop policy if exists "Sender updates own message" on messages;

create policy "Participants read messages" on messages
  for select using (
    exists (
      select 1 from conversation_participants cp
      where cp.conversation_id = messages.conversation_id
        and cp.user_id = auth.uid()
    )
  );

create policy "Members insert message" on messages
  for insert with check (
    sender_id = auth.uid()
    and exists (
      select 1 from conversation_participants cp
      where cp.conversation_id = messages.conversation_id
        and cp.user_id = auth.uid()
    )
  );

create policy "Sender updates own message" on messages
  for update using (sender_id = auth.uid());

-- ----------------------------------------------------------------
-- 5. get_or_create_dm: run as a trusted, transactional operation.
--    SECURITY DEFINER + explicit search_path so the function can
--    create the conversation and both memberships regardless of the
--    caller's RLS privileges, while still validating the inputs.
-- ----------------------------------------------------------------
create or replace function get_or_create_dm(my_id uuid, other_id uuid)
returns uuid language plpgsql
security definer
set search_path = ''
as $$
declare
  conv_id uuid;
begin
  -- Reject self-DMs.
  if my_id = other_id then
    raise exception 'cannot start a conversation with yourself';
  end if;

  -- Both users must have profile rows (FK targets for participants).
  if not exists (select 1 from public.profiles where id = my_id) then
    raise exception 'unknown user';
  end if;
  if not exists (select 1 from public.profiles where id = other_id) then
    raise exception 'unknown user';
  end if;

  -- Find an existing 1:1 conversation between the two users.
  -- search_path is empty here (not the definer's), so we qualify names.
  select c.id into conv_id
  from public.conversations c
  join public.conversation_participants cp1 on cp1.conversation_id = c.id
  join public.conversation_participants cp2 on cp2.conversation_id = c.id
  where cp1.user_id = my_id
    and cp2.user_id = other_id
    and (select count(*) from public.conversation_participants where conversation_id = c.id) = 2
  limit 1;

  if conv_id is not null then
    return conv_id;
  end if;

  -- Create a new conversation and both memberships as the trusted owner.
  insert into public.conversations (id, created_at, updated_at)
  values (gen_random_uuid(), now(), now())
  returning id into conv_id;

  insert into public.conversation_participants (conversation_id, user_id, joined_at)
  values (conv_id, my_id, now()),
         (conv_id, other_id, now());

  return conv_id;
end;
$$;

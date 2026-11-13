-- Bug-bounty hardening: stop recipients rewriting messages, close IDOR
-- gaps, enforce blocks, rate-limit sends, and stop leaking internals.

-- ============================================================
-- 1. Recipients may only set read_at (not rewrite content)
-- ============================================================
create or replace function public.guard_message_update()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  my_uid uuid := auth.uid();
  is_participant boolean;
begin
  if my_uid is null then
    raise exception 'unauthenticated call';
  end if;

  is_participant := exists (
    select 1 from public.conversation_participants cp
    where cp.conversation_id = old.conversation_id
      and cp.user_id = my_uid
  );

  if not is_participant then
    raise exception 'only conversation participants may update this message';
  end if;

  if new.conversation_id is distinct from old.conversation_id
     or new.sender_id is distinct from old.sender_id
     or new.created_at is distinct from old.created_at then
    raise exception 'message identity fields cannot be changed';
  end if;

  if my_uid = old.sender_id then
    if new.content is distinct from old.content then
      if old.created_at < now() - interval '15 minutes' then
        raise exception 'message edit window has expired';
      end if;
      new.original_content := coalesce(old.original_content, old.content);
      new.edited_at := now();
    end if;
  else
    if new.read_at is not distinct from old.read_at or new.read_at is null then
      raise exception 'recipients may only set read_at';
    end if;
    if to_jsonb(new) - 'read_at' is distinct from to_jsonb(old) - 'read_at' then
      raise exception 'recipients may only set read_at';
    end if;
  end if;

  return new;
end;
$$;

-- ============================================================
-- 2. Reactions: only conversation members may insert
-- ============================================================
drop policy if exists "Users can add own reactions" on public.message_reactions;
create policy "Users can add own reactions"
  on public.message_reactions
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1
        from public.messages m
        join public.conversation_participants cp
          on cp.conversation_id = m.conversation_id
       where m.id = message_reactions.message_id
         and cp.user_id = auth.uid()
    )
  );

-- ============================================================
-- 3. Freeze identity columns on participants / conversations
-- ============================================================
create or replace function public.guard_participant_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.conversation_id is distinct from old.conversation_id
     or new.user_id is distinct from old.user_id then
    raise exception 'participant identity cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_participant_update on public.conversation_participants;
create trigger guard_participant_update
  before update on public.conversation_participants
  for each row execute function public.guard_participant_update();

create or replace function public.guard_conversation_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
     or new.created_at is distinct from old.created_at then
    raise exception 'conversation identity cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_conversation_update on public.conversations;
create trigger guard_conversation_update
  before update on public.conversations
  for each row execute function public.guard_conversation_update();

-- ============================================================
-- 4. Block / report tables (were referenced by the client, missing in DB)
-- ============================================================
create table if not exists public.blocked_users (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
alter table public.blocked_users enable row level security;

drop policy if exists "Users read own blocks" on public.blocked_users;
create policy "Users read own blocks" on public.blocked_users
  for select to authenticated
  using (blocker_id = auth.uid() or blocked_id = auth.uid());

drop policy if exists "Users insert own blocks" on public.blocked_users;
create policy "Users insert own blocks" on public.blocked_users
  for insert to authenticated
  with check (blocker_id = auth.uid());

drop policy if exists "Users delete own blocks" on public.blocked_users;
create policy "Users delete own blocks" on public.blocked_users
  for delete to authenticated
  using (blocker_id = auth.uid());

create table if not exists public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_id uuid not null references auth.users(id) on delete cascade,
  reason text not null,
  details text,
  created_at timestamptz not null default now(),
  check (reporter_id <> reported_id)
);
alter table public.user_reports enable row level security;

drop policy if exists "Users insert own reports" on public.user_reports;
create policy "Users insert own reports" on public.user_reports
  for insert to authenticated
  with check (reporter_id = auth.uid());

drop policy if exists "Users read own reports" on public.user_reports;
create policy "Users read own reports" on public.user_reports
  for select to authenticated
  using (reporter_id = auth.uid());

-- ============================================================
-- 5. Hide-for-me (so delete-for-me does not wipe the peer's copy)
-- ============================================================
create table if not exists public.message_hides (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
alter table public.message_hides enable row level security;

drop policy if exists "Users manage own hidden messages" on public.message_hides;
create policy "Users manage own hidden messages" on public.message_hides
  for all to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and exists (
      select 1
        from public.messages m
        join public.conversation_participants cp
          on cp.conversation_id = m.conversation_id
       where m.id = message_hides.message_id
         and cp.user_id = auth.uid()
    )
  );

drop policy if exists "Sender deletes own message" on public.messages;
create policy "Sender deletes own message" on public.messages
  for delete to authenticated
  using (sender_id = auth.uid());

-- ============================================================
-- 6. Insert guard: membership already in RLS; add blocks, length, rate limit,
--    and same-conversation replies.
-- ============================================================
create or replace function public.guard_message_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recent int;
begin
  if auth.uid() is null or new.sender_id is distinct from auth.uid() then
    raise exception 'sender must be the current user';
  end if;

  if btrim(new.content) = '' then
    raise exception 'message cannot be empty';
  end if;

  if char_length(new.content) > 4000 then
    raise exception 'message too long';
  end if;

  if exists (
    select 1
      from public.conversation_participants cp
      join public.blocked_users b
        on (b.blocker_id = new.sender_id and b.blocked_id = cp.user_id)
        or (b.blocked_id = new.sender_id and b.blocker_id = cp.user_id)
     where cp.conversation_id = new.conversation_id
       and cp.user_id <> new.sender_id
  ) then
    raise exception 'cannot message this user';
  end if;

  if new.reply_to_id is not null and not exists (
    select 1 from public.messages m
     where m.id = new.reply_to_id
       and m.conversation_id = new.conversation_id
  ) then
    raise exception 'reply must be in the same conversation';
  end if;

  select count(*) into recent
    from public.messages
   where sender_id = new.sender_id
     and created_at > now() - interval '1 minute';

  if recent >= 30 then
    raise exception 'rate limit exceeded';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_message_insert on public.messages;
create trigger guard_message_insert
  before insert on public.messages
  for each row execute function public.guard_message_insert();

-- ============================================================
-- 7. get_or_create_dm: refuse blocked pairs
-- ============================================================
create or replace function public.get_or_create_dm(my_id uuid, other_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  conv_id uuid;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated call';
  end if;

  if my_id <> auth.uid() then
    raise exception 'caller must be my_id';
  end if;

  if my_id = other_id then
    raise exception 'cannot start a conversation with yourself';
  end if;

  if exists (
    select 1 from public.blocked_users
     where (blocker_id = my_id and blocked_id = other_id)
        or (blocker_id = other_id and blocked_id = my_id)
  ) then
    raise exception 'cannot start a conversation with this user';
  end if;

  if not exists (select 1 from public.profiles where id = my_id) then
    raise exception 'unknown user';
  end if;
  if not exists (select 1 from public.profiles where id = other_id) then
    raise exception 'unknown user';
  end if;

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

  insert into public.conversations (id, created_at, updated_at)
  values (gen_random_uuid(), now(), now())
  returning id into conv_id;

  insert into public.conversation_participants (conversation_id, user_id, joined_at)
  values (conv_id, my_id, now()),
         (conv_id, other_id, now());

  return conv_id;
end;
$$;

revoke execute on function public.get_or_create_dm(uuid, uuid) from public;
grant execute on function public.get_or_create_dm(uuid, uuid) to authenticated;

-- ============================================================
-- 8. pin_message: require conversation membership
-- ============================================================
create or replace function public.pin_message(msg_id uuid, do_pin boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  msg_conversation uuid;
  msg_sender uuid;
  pin_count int;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated call';
  end if;

  select conversation_id, sender_id into msg_conversation, msg_sender
    from public.messages where id = msg_id;

  if not found then
    raise exception 'message not found';
  end if;

  if not exists (
    select 1 from public.conversation_participants
     where conversation_id = msg_conversation and user_id = auth.uid()
  ) then
    raise exception 'not a participant';
  end if;

  if msg_sender <> auth.uid() then
    raise exception 'only the message author may pin this message';
  end if;

  if do_pin then
    select count(*) into pin_count
      from public.messages
     where conversation_id = msg_conversation
       and pinned_at is not null
       and id <> msg_id;

    if pin_count >= 5 then
      raise exception 'a conversation can have at most 5 pinned messages';
    end if;

    update public.messages set pinned_at = now() where id = msg_id;
  else
    update public.messages set pinned_at = null where id = msg_id;
  end if;
end;
$$;

grant execute on function public.pin_message(uuid, boolean) to authenticated;

-- ============================================================
-- 9. Private typing broadcasts (same membership model as calls)
-- ============================================================
drop policy if exists "Conversation members receive typing signals" on realtime.messages;
create policy "Conversation members receive typing signals" on realtime.messages
  for select to authenticated using (
    realtime.topic() like 'typing:%'
    and exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id::text = split_part(realtime.topic(), ':', 2)
        and cp.user_id = auth.uid()
    )
  );

drop policy if exists "Conversation members send typing signals" on realtime.messages;
create policy "Conversation members send typing signals" on realtime.messages
  for insert to authenticated with check (
    realtime.topic() like 'typing:%'
    and exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id::text = split_part(realtime.topic(), ':', 2)
        and cp.user_id = auth.uid()
    )
  );

-- ============================================================
-- 10. Stop leaking database internals to anonymous clients
-- ============================================================
revoke execute on function public.shares_conversation(uuid, uuid) from public, anon, authenticated;

do $$
begin
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'validate_supabase_config'
  ) then
    execute 'revoke execute on function public.validate_supabase_config() from public, anon, authenticated';
  end if;
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'health_check'
  ) then
    execute 'revoke execute on function public.health_check() from public, anon, authenticated';
  end if;
  if exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'supabase_config_status'
  ) then
    execute 'revoke select on public.supabase_config_status from public, anon, authenticated';
  end if;
end
$$;

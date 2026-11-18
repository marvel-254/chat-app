-- ============================================================
-- Friendship Timeline (#66)
-- A private timeline between two friends that surfaces shared
-- photos, important dates, the first message, and memorable
-- (pinned) moments.
--
-- Storage: photos live in the private R2 bucket behind the
-- `bro-chat-storage` Worker, exactly like chat attachments, so
-- signed URLs keep working through Supa.attachmentUrl().
--
-- Access: every read goes through the SECURITY DEFINER function
-- friendship_timeline_for_peer(), which only returns rows for a
-- conversation the caller actually participates in. The tables
-- themselves stay locked down to the owner.
-- ============================================================

-- 1. Shared photos ------------------------------------------------------
create table if not exists public.friendship_photos (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  object_path text not null,
  caption text,
  taken_from_message_id uuid references public.messages(id) on delete set null,
  created_at timestamptz not null default now(),
  check (char_length(object_path) <= 512)
);

create index if not exists friendship_photos_owner_created_idx
  on public.friendship_photos (owner_id, created_at desc);
create index if not exists friendship_photos_conversation_idx
  on public.friendship_photos (conversation_id, created_at desc);

alter table public.friendship_photos enable row level security;

drop policy if exists "Users manage own friendship photos" on public.friendship_photos;
create policy "Users manage own friendship photos"
  on public.friendship_photos
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

comment on table public.friendship_photos is
  'Photos two friends pinned to their private timeline. Only the two participants of the conversation can read them (via friendship_timeline_for_peer).';

-- 2. Important dates ----------------------------------------------------
create table if not exists public.friendship_dates (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  title text not null,
  occurs_on date not null,
  remind_annually boolean not null default true,
  created_at timestamptz not null default now(),
  check (char_length(title) <= 120)
);

create index if not exists friendship_dates_owner_idx
  on public.friendship_dates (owner_id, occurs_on);

alter table public.friendship_dates enable row level security;

drop policy if exists "Users manage own friendship dates" on public.friendship_dates;
create policy "Users manage own friendship dates"
  on public.friendship_dates
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

comment on table public.friendship_dates is
  'Important dates two friends track on their private timeline. Only the two participants of the conversation can read them (via friendship_timeline_for_peer).';

-- 3. Timeline read model ------------------------------------------------
-- One row per timeline entry: an important date, a shared photo, or a
-- pinned moment. `kind` is the discriminator, so the whole timeline is a
-- single ordered query.
create or replace function public.friendship_timeline_for_peer(
  p_peer_id uuid,
  p_limit int default 100
)
returns table (
  id uuid,
  kind text,
  conversation_id uuid,
  created_at timestamptz,
  photo_path text,
  photo_caption text,
  photo_message_id uuid,
  date_title text,
  occurs_on date,
  remind_annually boolean,
  moment_message_id uuid,
  moment_preview text,
  moment_pinned_at timestamptz,
  moment_sender_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  with conv as (
    select c.id
      from public.conversations c
      join public.conversation_participants cp_me
        on cp_me.conversation_id = c.id and cp_me.user_id = auth.uid()
      join public.conversation_participants cp_peer
        on cp_peer.conversation_id = c.id and cp_peer.user_id = p_peer_id
     where (select count(*) from public.conversation_participants cp
             where cp.conversation_id = c.id) = 2
     limit 1
  ), mine as (
    select auth.uid() as viewer, p_peer_id as peer
  ), first_message as (
    select m.id, m.created_at, m.sender_id, m.content
      from public.messages m
     where m.conversation_id = (select id from conv)
     order by m.created_at asc, m.id asc
     limit 1
  )
  -- Important dates
  select
    d.id,
    'date'::text,
    d.conversation_id,
    d.created_at,
    null::text,
    null::text,
    null::uuid,
    d.title,
    d.occurs_on,
    d.remind_annually,
    null::uuid,
    null::text,
    null::timestamptz,
    null::uuid
    from public.friendship_dates d, conv
   where d.conversation_id = conv.id
     and d.owner_id = (select viewer from mine)
  union all
  -- Shared photos (owned by either friend)
  select
    p.id,
    'photo'::text,
    p.conversation_id,
    p.created_at,
    p.object_path,
    p.caption,
    p.taken_from_message_id,
    null::text,
    null::date,
    null::boolean,
    null::uuid,
    null::text,
    null::timestamptz,
    null::uuid
    from public.friendship_photos p, conv
   where p.conversation_id = conv.id
     and (p.owner_id = (select viewer from mine) or p.owner_id = (select peer from mine))
  union all
  -- Memorable moments: pinned messages from either friend
  select
    m.id,
    'moment'::text,
    m.conversation_id,
    m.created_at,
    null::text,
    null::text,
    null::uuid,
    null::text,
    null::date,
    null::boolean,
    m.id,
    left(m.content, 200),
    m.pinned_at,
    m.sender_id
    from public.messages m, conv
   where m.conversation_id = conv.id
     and m.pinned_at is not null
  union all
  -- First message, so a brand-new friendship already has a story
  select
    fm.id,
    'first_message'::text,
    (select id from conv),
    fm.created_at,
    null::text,
    null::text,
    null::uuid,
    null::text,
    null::date,
    null::boolean,
    fm.id,
    left(fm.content, 200),
    null::timestamptz,
    fm.sender_id
    from first_message fm
   where exists (select 1 from conv)
  order by created_at desc, id desc
  limit greatest(coalesce(p_limit, 100), 1);
$$;

revoke execute on function public.friendship_timeline_for_peer(uuid, int) from public, anon;
grant execute on function public.friendship_timeline_for_peer(uuid, int) to authenticated;

-- 4. Write helpers ------------------------------------------------------
-- The client stays on the plain tables for writes (RLS already limits them
-- to the owner); these exist so a client that prefers a single call can
-- create a photo without leaking the object path format.

create or replace function public.add_friendship_photo(
  p_conversation_id uuid,
  p_object_path text,
  p_caption text default null,
  p_taken_from_message_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  photo_id uuid;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated call';
  end if;

  if not exists (
    select 1 from public.conversation_participants
     where conversation_id = p_conversation_id and user_id = auth.uid()
  ) then
    raise exception 'not a participant';
  end if;

  if p_taken_from_message_id is not null and not exists (
    select 1 from public.messages
     where id = p_taken_from_message_id and conversation_id = p_conversation_id
  ) then
    raise exception 'message not in this conversation';
  end if;

  insert into public.friendship_photos
    (owner_id, conversation_id, object_path, caption, taken_from_message_id)
  values
    (auth.uid(), p_conversation_id, p_object_path, p_caption, p_taken_from_message_id)
  returning id into photo_id;

  return photo_id;
end;
$$;

revoke execute on function public.add_friendship_photo(uuid, text, text, uuid) from public, anon;
grant execute on function public.add_friendship_photo(uuid, text, text, uuid) to authenticated;

create or replace function public.add_friendship_date(
  p_conversation_id uuid,
  p_title text,
  p_occurs_on date,
  p_remind_annually boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  date_id uuid;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated call';
  end if;

  if btrim(p_title) = '' then
    raise exception 'title cannot be empty';
  end if;

  if char_length(p_title) > 120 then
    raise exception 'title too long';
  end if;

  if not exists (
    select 1 from public.conversation_participants
     where conversation_id = p_conversation_id and user_id = auth.uid()
  ) then
    raise exception 'not a participant';
  end if;

  insert into public.friendship_dates
    (owner_id, conversation_id, title, occurs_on, remind_annually)
  values
    (auth.uid(), p_conversation_id, btrim(p_title), p_occurs_on, coalesce(p_remind_annually, true))
  returning id into date_id;

  return date_id;
end;
$$;

revoke execute on function public.add_friendship_date(uuid, text, date, boolean) from public, anon;
grant execute on function public.add_friendship_date(uuid, text, date, boolean) to authenticated;

-- 5. Realtime: a friend adding a photo should refresh the open timeline.
do $$
begin
  alter publication supabase_realtime add table public.friendship_photos;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.friendship_dates;
exception
  when duplicate_object then null;
end $$;

notify pgrst, 'reload schema';

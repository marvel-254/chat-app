-- Privacy enforcement + safety hardening consolidating prior work.
-- 1. Masked profile access via a security_barrier view, so raw reads of
--    `profiles` from the client no longer bypass the privacy settings
--    (photo / about / last-seen visibility) added in shortcuts #40.
-- 2. Conversation listing now surfaces `peer_avatar_url` honouring the same
--    masking, so avatars stay gated by photo_visibility.
-- 3. DB-level cap on pinned messages (5 per conversation).
-- 4. Users may delete their own read receipts (message_reads delete policy).
-- 5. Scheduled cleanup of expired messages via pg_cron (1 minute cadence).
-- 6. New conversation participants inherit the creator's default
--    message-expiry timer (conversations.message_expiry = 0 means unset).

-- ============================================================
-- 1. Visible profiles (masked per privacy settings)
-- ============================================================
create or replace function public.shares_conversation(a uuid, b uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(a = b and a is not null, false)
      or exists (
        select 1
          from public.conversation_participants x
          join public.conversation_participants y
            on y.conversation_id = x.conversation_id
           and y.user_id = b
         where x.user_id = a
      );
$$;
grant execute on function public.shares_conversation(uuid, uuid)
  to anon, authenticated;

-- Non-sensitive columns stay visible to everyone; the privacy-gated ones
-- (about, avatar_url, last_seen_at) are masked to null when the viewer has
-- no permission for them. The view runs as its owner (postgres) so it can
-- bypass RLS while the case logic re-implements the privacy rules.
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
    p.default_message_expiry
  from public.profiles p;
grant select on public.visible_profiles to anon, authenticated;

-- `profiles` itself is no longer readable directly by clients.
-- Updates/inserts still need INSERT/UPDATE grants, which revoking select
-- leaves alone (Supabase's default uses separate per-column grants).
revoke select on public.profiles from anon, authenticated;

-- ============================================================
-- 2. Conversation listing with privacy-aware peer avatar
-- ============================================================
-- Recreated: the new `peer_avatar_url` output column changes the return
-- type, so the old function must be dropped before redefining it.
drop function if exists public.get_conversations_for_user();
create or replace function public.get_conversations_for_user()
returns table (
  conversation_id uuid,
  created_at timestamptz,
  updated_at timestamptz,
  peer_id uuid,
  peer_username text,
  peer_display_name text,
  peer_avatar_url text,
  last_message text,
  last_message_at timestamptz,
  unread_count bigint
) language sql
stable
security invoker
as $$
  select
    v.id,
    v.created_at,
    v.updated_at,
    v.peer_id,
    v.peer_username,
    v.peer_display_name,
    v.peer_avatar_url,
    v.last_message,
    v.last_message_at,
    v.unread_count
  from
    (select
      c.id,
      c.created_at,
      c.updated_at,
      -- the other participant (not the caller)
      (select p.id from visible_profiles p
         join conversation_participants cp on cp.user_id = p.id
        where cp.conversation_id = c.id and cp.user_id <> auth.uid()
        limit 1) as peer_id,
      (select p.username from visible_profiles p
         join conversation_participants cp on cp.user_id = p.id
        where cp.conversation_id = c.id and cp.user_id <> auth.uid()
        limit 1) as peer_username,
      (select p.display_name from visible_profiles p
         join conversation_participants cp on cp.user_id = p.id
        where cp.conversation_id = c.id and cp.user_id <> auth.uid()
        limit 1) as peer_display_name,
      (select p.avatar_url from visible_profiles p
         join conversation_participants cp on cp.user_id = p.id
        where cp.conversation_id = c.id and cp.user_id <> auth.uid()
        limit 1) as peer_avatar_url,
      (select m.content from messages m
        where m.conversation_id = c.id
        order by m.created_at desc limit 1) as last_message,
      (select m.created_at from messages m
        where m.conversation_id = c.id
        order by m.created_at desc limit 1) as last_message_at,
      -- unread = messages not yet read by the caller, newer than their last_read_at
      (select count(*) from messages m
        where m.conversation_id = c.id
          and m.sender_id <> auth.uid()
          and m.read_at is null
          and (
            not exists (
              select 1 from conversation_participants cp
              where cp.conversation_id = c.id and cp.user_id = auth.uid()
            )
            or m.created_at > (
              select cp.last_read_at from conversation_participants cp
              where cp.conversation_id = c.id and cp.user_id = auth.uid()
            )
          )
      ) as unread_count
    from conversations c
    where exists (
      select 1 from conversation_participants cp
      where cp.conversation_id = c.id and cp.user_id = auth.uid()
    )) as v
    order by v.last_message_at nulls first, v.updated_at desc;
$$;
grant execute on function public.get_conversations_for_user() to authenticated;

-- ============================================================
-- 3. Pin cap (5 per conversation) enforced in the database
-- ============================================================
create or replace function public.enforce_pin_cap()
returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.pinned_at is not null and (old.pinned_at is null) then
    if exists (
      select 1
        from public.messages
       where conversation_id = new.conversation_id
         and id <> new.id
         and pinned_at is not null
    ) and (
      select count(*)
        from public.messages
       where conversation_id = new.conversation_id
         and id <> new.id
         and pinned_at is not null
    ) >= 5 then
      raise exception 'a conversation can have at most 5 pinned messages';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists enforce_pin_cap on public.messages;
create trigger enforce_pin_cap before update of pinned_at on public.messages
  for each row execute function public.enforce_pin_cap();

-- ============================================================
-- 4. Delete own read receipts
-- ============================================================
drop policy if exists "Users delete own read receipts" on public.message_reads;
create policy "Users delete own read receipts" on public.message_reads
  for delete to authenticated using (user_id = auth.uid());

-- ============================================================
-- 5. Scheduled cleanup of expired messages
-- ============================================================
create extension if not exists pg_cron;
do $cron$
begin
  if not exists (
    select 1 from cron.job where jobname = 'cleanup-expired-messages'
  ) then
    perform cron.schedule(
      'cleanup-expired-messages',
      '* * * * *',
      $$select public.delete_expired_messages()$$
    );
  end if;
end;
$cron$;

-- ============================================================
-- 6. Profile defaults seeding conversation message-expiry
-- ============================================================
create or replace function public.apply_default_message_expiry()
returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.user_id = auth.uid() then
    update public.conversations c
       set message_expiry = p.default_message_expiry
      from public.profiles p
     where p.id = new.user_id
       and c.id = new.conversation_id
       and c.message_expiry = interval '0'
       and p.default_message_expiry > interval '0';
  end if;
  return new;
end;
$$;
drop trigger if exists apply_default_message_expiry on public.conversation_participants;
create trigger apply_default_message_expiry
  after insert on public.conversation_participants
  for each row execute function public.apply_default_message_expiry();

-- ============================================================
-- Respect the read-receipts privacy toggle
--
-- The app exposes a "Read receipts" switch, and the DB has
-- profiles.read_receipts_enabled, but mark_messages_read ignored it: every
-- open of a conversation stamped read_at and inserted receipts, telling the
-- peer that the message had been read.
--
-- New shape:
--   mark_messages_read(p_conversation_id, p_share_receipt)
--     * always advances the caller's own last_read_at so their unread badge
--       clears;
--     * only writes read_at / receipt rows when p_share_receipt is true.
--
-- The two-argument function replaces the one-argument version; PostgREST
-- resolves RPCs by argument names, so a stale client calling the old name
-- would fail, hence the compatibility overload at the bottom.
-- ============================================================

create or replace function public.mark_messages_read(
  p_conversation_id uuid,
  p_share_receipt boolean default true
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  my_uid uuid := auth.uid();
  latest_read timestamptz := now();
  receipt_enabled boolean;
begin
  if my_uid is null then
    raise exception 'unauthenticated call';
  end if;

  if not exists (
    select 1 from public.conversation_participants
    where conversation_id = p_conversation_id
      and user_id = my_uid
  ) then
    raise exception 'not a participant';
  end if;

  select coalesce(read_receipts_enabled, true) into receipt_enabled
  from public.profiles where id = my_uid;

  if (p_share_receipt and coalesce(receipt_enabled, true)) then
    update public.messages
       set read_at = latest_read
     where conversation_id = p_conversation_id
       and sender_id <> my_uid
       and read_at is null;

    insert into public.message_reads (message_id, user_id, read_at)
    select m.id, my_uid, latest_read
      from public.messages m
     where m.conversation_id = p_conversation_id
       and m.sender_id <> my_uid
    on conflict (message_id, user_id) do nothing;
  end if;

  -- Always advance the caller's own cursor so their unread count clears.
  update public.conversation_participants
     set last_read_at = latest_read
   where conversation_id = p_conversation_id
     and user_id = my_uid;
end;
$$;

grant execute on function public.mark_messages_read(uuid, boolean) to authenticated;

-- Older builds (and anything still calling the single-argument form) keep
-- working; they are treated as "share receipts", which matches the previous
-- behaviour for clients that predate the toggle.
create or replace function public.mark_messages_read(p_conversation_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  select public.mark_messages_read(p_conversation_id, true);
$$;

grant execute on function public.mark_messages_read(uuid) to authenticated;

-- Unread counts must not depend on read receipts: the conversation-list RPC
-- previously compared created_at with the caller's last_read_at, which the
-- version above now always advances. Re-assert that the "unread" definition
-- is about the caller only, and never about what the peer can see.
create or replace function public.unread_counts_for_user()
returns table (conversation_id uuid, unread_count bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select
    c.id,
    (
      select count(*)
        from public.messages m
       where m.conversation_id = c.id
         and m.sender_id <> auth.uid()
         and m.deleted_at is null
         and not (auth.uid() = any (coalesce(m.hidden_for, '{}'::uuid[])))
         and m.created_at > coalesce((
               select cp.last_read_at
                 from public.conversation_participants cp
                where cp.conversation_id = c.id
                  and cp.user_id = auth.uid()
             ), '-infinity'::timestamptz)
    )
  from public.conversations c
  where exists (
    select 1 from public.conversation_participants cp
     where cp.conversation_id = c.id and cp.user_id = auth.uid()
  );
$$;

grant execute on function public.unread_counts_for_user() to authenticated;

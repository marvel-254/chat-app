-- ============================================================
-- Fix guard_message_update trigger to allow recipients to set read_at
-- Fixes issue #47 (read-receipt RLS).
--
-- The original trigger only allowed the message author to update.
-- Recipients need to be able to set read_at on inbound messages.
-- ============================================================

create or replace function public.guard_message_update()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  my_uid uuid := auth.uid();
  is_recipient boolean;
begin
  if my_uid is null then
    raise exception 'unauthenticated call';
  end if;

  -- Check if the caller is the sender or a recipient in the conversation
  is_recipient := exists (
    select 1 from public.conversation_participants cp
    where cp.conversation_id = old.conversation_id
      and cp.user_id = my_uid
  );

  if not is_recipient then
    raise exception 'only conversation participants may update this message';
  end if;

  -- Sender can update content (within edit window)
  -- Recipient can only update read_at
  if my_uid = old.sender_id then
    -- Sender: allow content updates within 15 minutes
    if new.content is distinct from old.content then
      if old.created_at < now() - interval '15 minutes' then
        raise exception 'message edit window has expired';
      end if;
      new.original_content := coalesce(old.original_content, old.content);
      new.edited_at := now();
    end if;
  else
    -- Recipient: only allow setting read_at (not clearing it)
    if new.read_at is not distinct from old.read_at then
      raise exception 'recipients may only set read_at';
    end if;
    if new.read_at is null then
      raise exception 'recipients may only set read_at, not clear it';
    end if;
  end if;

  -- Identity fields are immutable for everyone
  if new.conversation_id <> old.conversation_id
     or new.sender_id <> old.sender_id
     or new.created_at <> old.created_at then
    raise exception 'message identity fields cannot be changed';
  end if;

  return new;
end;
$$;
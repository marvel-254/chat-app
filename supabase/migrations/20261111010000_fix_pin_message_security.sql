-- ============================================================
-- Fix pin message: add SECURITY DEFINER function with ownership
-- and 5-pin limit enforcement. Fixes issue where pin action was
-- offered on peer messages but DB trigger rejected non-author updates.
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
  -- Reject unauthenticated calls
  if auth.uid() is null then
    raise exception 'unauthenticated call';
  end if;

  select conversation_id, sender_id into msg_conversation, msg_sender
  from public.messages where id = msg_id;
  
  if not found then
    raise exception 'message not found';
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

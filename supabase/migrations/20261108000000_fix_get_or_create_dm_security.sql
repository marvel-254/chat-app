-- ============================================================
-- Fix get_or_create_dm security: bind to auth.uid() and restrict EXECUTE
-- Fixes issue #46 (and related #5).
--
-- The SECURITY DEFINER function must validate that the caller is
-- one of the participants (my_id = auth.uid()) and reject anonymous
-- or spoofed calls. EXECUTE is restricted to authenticated role.
-- ============================================================

-- Revoke default PUBLIC execute grant and grant only to authenticated
revoke execute on function public.get_or_create_dm(uuid, uuid) from public;
grant execute on function public.get_or_create_dm(uuid, uuid) to authenticated;

-- Replace the function with proper auth.uid() binding
create or replace function public.get_or_create_dm(my_id uuid, other_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  conv_id uuid;
begin
  -- Reject unauthenticated calls
  if auth.uid() is null then
    raise exception 'unauthenticated call';
  end if;

  -- Caller must be the 'my_id' participant (prevents spoofing)
  if my_id <> auth.uid() then
    raise exception 'caller must be my_id';
  end if;

  -- Reject self-DMs
  if my_id = other_id then
    raise exception 'cannot start a conversation with yourself';
  end if;

  -- Both users must have profile rows (FK targets for participants)
  if not exists (select 1 from public.profiles where id = my_id) then
    raise exception 'unknown user: my_id';
  end if;
  if not exists (select 1 from public.profiles where id = other_id) then
    raise exception 'unknown user: other_id';
  end if;

  -- Find an existing 1:1 conversation between the two users
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

  -- Create a new conversation and both memberships as the trusted owner
  insert into public.conversations (id, created_at, updated_at)
  values (gen_random_uuid(), now(), now())
  returning id into conv_id;

  insert into public.conversation_participants (conversation_id, user_id, joined_at)
  values (conv_id, my_id, now()),
         (conv_id, other_id, now());

  return conv_id;
end;
$$;
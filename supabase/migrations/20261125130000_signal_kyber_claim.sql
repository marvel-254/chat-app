-- Kyber prekeys are one-time material too; claim atomically so one key is
-- never handed to multiple senders.
create or replace function public.signal_claim_kyber_prekey(p_device_row_id uuid)
returns table(prekey_id integer, public_key bytea, signature bytea)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated call';
  end if;

  select d.user_id into v_owner
    from public.signal_devices d
   where d.id = p_device_row_id
     and d.revoked_at is null;

  if v_owner is null then
    raise exception 'device unavailable';
  end if;

  if v_owner <> auth.uid() and not exists (
    select 1
      from public.conversation_participants mine
      join public.conversation_participants theirs
        on theirs.conversation_id = mine.conversation_id
     where mine.user_id = auth.uid()
       and theirs.user_id = v_owner
  ) then
    raise exception 'not authorized';
  end if;

  return query
  with claimed as (
    select k.id
      from public.signal_kyber_prekeys k
     where k.device_row_id = p_device_row_id
       and k.used_at is null
     order by k.prekey_id
     limit 1
     for update skip locked
  )
  update public.signal_kyber_prekeys k
     set used_at = now()
    from claimed
   where k.id = claimed.id
  returning k.prekey_id, k.public_key, k.signature;
end;
$$;
revoke all on function public.signal_claim_kyber_prekey(uuid) from public, anon;
grant execute on function public.signal_claim_kyber_prekey(uuid) to authenticated;

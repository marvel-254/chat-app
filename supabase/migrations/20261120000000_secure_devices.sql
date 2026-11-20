-- Append-only public device identities. No private key or recoverable seed.
create table public.chat_device_keys (
 fingerprint text primary key check (fingerprint ~ '^[0-9a-f]{64}$'),
 user_id uuid not null references auth.users on delete cascade,
 public_key text not null check (length(public_key) between 80 and 8192 and public_key like '-----BEGIN PGP PUBLIC KEY BLOCK-----%' and public_key not like '%PRIVATE KEY%'),
 created_at timestamptz not null default now(), revoked_at timestamptz
);
create index chat_device_keys_owner on public.chat_device_keys(user_id);
alter table public.chat_device_keys enable row level security;
revoke all on public.chat_device_keys from public, anon, authenticated;
grant select, insert(user_id,fingerprint,public_key) on public.chat_device_keys to authenticated;
create policy device_read on public.chat_device_keys for select to authenticated using
 (user_id=auth.uid() or public.shares_conversation(auth.uid(),user_id));
create policy device_register on public.chat_device_keys for insert to authenticated with check (user_id=auth.uid());
create function public.revoke_chat_key(p_key text) returns void language sql security definer set search_path='' as $$
 update public.chat_device_keys set revoked_at=now() where user_id=auth.uid() and fingerprint=p_key and revoked_at is null;
$$;
revoke all on function public.revoke_chat_key(text) from public, anon;
grant execute on function public.revoke_chat_key(text) to authenticated;
create or replace function public.guard_message_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or new.sender_id is distinct from auth.uid() then
    raise exception 'sender must be the current user';
  end if;

  if btrim(new.content) = '' then
    raise exception 'message cannot be empty';
  end if;

  if new.content !~ '^bro2:[0-9a-f]{64}:-----BEGIN PGP MESSAGE-----' or octet_length(new.content) > 262144 then
    raise exception 'Expected a bounded secure message envelope';
  end if;

  -- Block check
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

  -- Reply target check
  if new.reply_to_id is not null and not exists (
    select 1 from public.messages m
     where m.id = new.reply_to_id
       and m.conversation_id = new.conversation_id
  ) then
    raise exception 'reply must be in the same conversation';
  end if;

  -- Rate limit (uses tracking table — O(1) lookup)
  perform public.check_message_rate(new.sender_id);

  return new;
end;
$$;


create function public.require_secure_content() returns trigger language plpgsql set search_path='' as $$
begin
 if new.content !~ '^bro2:[0-9a-f]{64}:-----BEGIN PGP MESSAGE-----' or octet_length(new.content)>262144 then raise exception 'Secure envelope required'; end if;
 return new;
end; $$;
create trigger secure_edits before update of content on public.messages for each row when (new.content is distinct from old.content) execute function public.require_secure_content();
create trigger secure_schedule before insert or update of content on public.scheduled_messages for each row execute function public.require_secure_content();
create policy schedule_membership on public.scheduled_messages as restrictive for insert to authenticated with check(public.is_conversation_member(conversation_id) and attachment_url is null and attachment_mime is null);
-- Keep the legacy emoji column out of the encrypted data path. Index only
-- the random event id, not the (potentially large) armored packet.
alter table public.message_reactions add column sealed_content text;
create policy secure_reaction_writes on public.message_reactions as restrictive for insert to authenticated with check
 (emoji=id::text and sealed_content is not null and octet_length(sealed_content)<=262144 and sealed_content ~ '^bro2:[0-9a-f]{64}:-----BEGIN PGP MESSAGE-----');

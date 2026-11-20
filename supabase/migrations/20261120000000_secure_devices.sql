-- Append-only public device identities. No private key or recoverable seed.
create table public.chat_device_keys (
 fingerprint text primary key check (fingerprint ~ '^[0-9a-f]{64}$'),
 device_id uuid not null, user_id uuid not null references auth.users on delete cascade,
 public_key text not null check (length(public_key) between 80 and 8192 and public_key like '-----BEGIN PGP PUBLIC KEY BLOCK-----%' and public_key not like '%PRIVATE KEY%'),
 created_at timestamptz not null default now(), revoked_at timestamptz
);
create index chat_device_keys_owner on public.chat_device_keys(user_id);
alter table public.chat_device_keys enable row level security;
revoke all on public.chat_device_keys from public, anon, authenticated;
grant select, insert(user_id,device_id,fingerprint,public_key) on public.chat_device_keys to authenticated;
create policy device_read on public.chat_device_keys for select to authenticated using
 (user_id=auth.uid() or public.shares_conversation(auth.uid(),user_id));
create policy device_register on public.chat_device_keys for insert to authenticated with check (user_id=auth.uid());
create function public.revoke_chat_key(p_key text) returns void language sql security definer set search_path='' as $$
 update public.chat_device_keys set revoked_at=now() where user_id=auth.uid() and fingerprint=p_key and revoked_at is null;
$$;
revoke all on function public.revoke_chat_key(text) from public, anon;
grant execute on function public.revoke_chat_key(text) to authenticated;
create function public.valid_device_roster(conv uuid,author uuid,envelope text) returns boolean language sql stable set search_path='' as $$
 select length(envelope)<=262144 and envelope ~ '^bro2:[0-9a-f]{64}:[0-9a-f,]+:-----BEGIN PGP MESSAGE-----' and
 exists(select from public.chat_device_keys where user_id=author and fingerprint=split_part(envelope,':',2) and revoked_at is null) and
 (select count(*)>=2 and count(*)=count(k.fingerprint) and string_agg(k.fingerprint,',' order by k.fingerprint collate "C")=split_part(envelope,':',3)
  from public.conversation_participants p left join public.chat_device_keys k on k.user_id=p.user_id and k.revoked_at is null where p.conversation_id=conv);
$$;
revoke all on function public.valid_device_roster(uuid,uuid,text) from public,anon;
grant execute on function public.valid_device_roster(uuid,uuid,text) to authenticated;
alter table public.messages add column secure_revision integer not null default 0 check(secure_revision>=0),add column signed_reply uuid;
alter table public.message_edit_history add column revision integer;
-- signed_reply survives ON DELETE SET NULL on the navigation FK.
create function public.bind_message_context() returns trigger language plpgsql set search_path='' as $$ begin
 if tg_op='INSERT' then new.secure_revision:=0; new.signed_reply:=new.reply_to_id;
 else new.secure_revision:=old.secure_revision + case when new.content is distinct from old.content then 1 else 0 end;
 new.signed_reply:=case when old.content not like 'bro2:%' and new.content is distinct from old.content then old.reply_to_id else old.signed_reply end;
 end if;return new;
end;$$;
create trigger bind_message_context before insert or update on public.messages for each row execute function public.bind_message_context();
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

  if not coalesce(public.valid_device_roster(new.conversation_id,new.sender_id,new.content),false) or octet_length(new.content) > 262144 then
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
 if not coalesce(public.valid_device_roster(new.conversation_id,new.sender_id,new.content),false) or octet_length(new.content)>262144 then raise exception 'Secure envelope required'; end if;
 return new;
end; $$;
create trigger secure_edits before update of content on public.messages for each row when (new.content is distinct from old.content) execute function public.require_secure_content();
create trigger secure_schedule before insert or update of content on public.scheduled_messages for each row execute function public.require_secure_content();
create policy schedule_membership on public.scheduled_messages as restrictive for insert to authenticated with check(public.is_conversation_member(conversation_id) and attachment_url is null and attachment_mime is null);
-- Keep the legacy emoji column out of the encrypted data path. Index only
-- the random event id, not the (potentially large) armored packet.
alter table public.message_reactions add column sealed_content text;
create policy secure_reaction_writes on public.message_reactions as restrictive for insert to authenticated with check
 (emoji=id::text and sealed_content is not null and octet_length(sealed_content)<=262144 and public.valid_device_roster((select m.conversation_id from public.messages m where m.id=message_id),user_id,sealed_content));

-- Preserve the signed event ID on dispatch. This invoker operation is also
-- subject to normal message insertion RLS, current blocks and send limits.
create function public.deliver_my_due_messages() returns integer language plpgsql security invoker set search_path='' as $$
declare item public.scheduled_messages; n integer:=0;
begin
 for item in delete from public.scheduled_messages where id in (select s.id from public.scheduled_messages s where s.sender_id=auth.uid() and s.scheduled_at<=now() and public.valid_device_roster(s.conversation_id,s.sender_id,s.content) order by s.scheduled_at limit 10) returning * loop
   insert into public.messages(id,sender_id,conversation_id,content,reply_to_id) values(item.id,item.sender_id,item.conversation_id,item.content,item.reply_to_id);
   n:=n+1;
 end loop;
 return n;
end; $$;
revoke all on function public.deliver_my_due_messages() from public,anon;
grant execute on function public.deliver_my_due_messages() to authenticated;
-- Write edit and history in one transaction. Old apps cannot copy cleartext
-- into the history table before an incompatible edit is rejected.
revoke insert,update on public.message_edit_history from authenticated,anon;
create function public.record_secure_edit() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.message_edit_history(message_id,revision,previous_content,new_content) values(new.id,new.secure_revision,case when old.content like 'bro2:%' then old.content else '[Legacy version]' end,new.content);
 return new;
end; $$;
create trigger record_secure_edit after update of content on public.messages for each row when(new.content is distinct from old.content) execute function public.record_secure_edit();
create function public.prevent_plaintext_draft() returns trigger language plpgsql set search_path='' as $$ begin
 if new.draft is not null and new.draft<>'' then raise exception 'Drafts are local to your device';end if;return new;
end; $$;
create trigger local_drafts before insert or update of draft on public.conversation_participants for each row execute function public.prevent_plaintext_draft();

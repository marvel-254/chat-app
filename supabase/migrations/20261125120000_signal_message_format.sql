-- Identify Signal envelopes explicitly. Historical plaintext stays readable
-- as legacy and is never relabelled as encrypted.
alter table public.messages
  drop constraint if exists messages_content_format_check;

alter table public.messages
  add constraint messages_content_format_check
  check (content_format in (
    'legacy_unversioned',
    'legacy_plaintext',
    'signal_v1'
  ));

-- New writes must be a versioned Signal envelope. Historical plaintext stays
-- readable, but old clients cannot silently downgrade new messages.
create or replace function public.bro_require_signal_message()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.content_format is distinct from 'signal_v1'
     or left(new.content, 5) is distinct from 'sig2:' then
    raise exception using errcode = '42501',
      message = 'end-to-end encrypted messages are required';
  end if;
  return new;
end;
$$;
revoke all on function public.bro_require_signal_message() from public, anon, authenticated;
drop trigger if exists bro_require_signal_message on public.messages;
create trigger bro_require_signal_message
  before insert on public.messages
  for each row execute function public.bro_require_signal_message();

create or replace function public.bro_require_signal_scheduled_message()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if left(new.content, 5) is distinct from 'sig2:' then
    raise exception using errcode = '42501',
      message = 'scheduled messages must be encrypted on the sender device';
  end if;
  return new;
end;
$$;
revoke all on function public.bro_require_signal_scheduled_message() from public, anon, authenticated;
drop trigger if exists bro_require_signal_scheduled_message on public.scheduled_messages;
create trigger bro_require_signal_scheduled_message
  before insert or update of content on public.scheduled_messages
  for each row execute function public.bro_require_signal_scheduled_message();

-- Signal envelopes expand the client-validated 4,000-character plaintext.
create or replace function public.guard_message_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  internal boolean := coalesce(current_setting('bro.scheduled_dispatch', true), '') = 'on';
begin
  if not internal and
     (auth.uid() is null or new.sender_id is distinct from auth.uid()) then
    raise exception 'sender must be the current user';
  end if;

  if btrim(new.content) = '' then
    raise exception 'message cannot be empty';
  end if;
  if char_length(new.content) > 1000000 then
    raise exception 'encrypted message envelope too large';
  end if;

  if exists (
    select 1 from public.conversation_participants cp
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

  if not internal then
    perform public.check_message_rate(new.sender_id);
  end if;
  return new;
end;
$$;

create or replace function public.bro_block_plaintext_message_edits()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.content is distinct from old.content then
    raise exception using errcode = '42501',
      message = 'message editing is unavailable for encrypted conversations';
  end if;
  return new;
end;
$$;
revoke all on function public.bro_block_plaintext_message_edits() from public, anon, authenticated;
drop trigger if exists bro_block_plaintext_message_edits on public.messages;
create trigger bro_block_plaintext_message_edits
  before update of content on public.messages
  for each row execute function public.bro_block_plaintext_message_edits();

-- The scheduled dispatcher can only deliver ciphertext already prepared by a
-- client. Legacy plaintext jobs fail closed and are eventually discarded by
-- the dispatcher's existing bounded retry policy.
create or replace function public.dispatch_scheduled_messages()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  job public.scheduled_messages;
  next_attempts integer;
  sent integer := 0;
begin
  for job in
    select * from public.scheduled_messages
     where next_attempt_at <= now()
     order by scheduled_at
     for update skip locked
  loop
    begin
      if left(job.content, 5) is distinct from 'sig2:'
         or char_length(job.content) > 100000 then
        raise exception 'scheduled message is not encrypted';
      end if;
      if not exists (
        select 1 from public.conversation_participants cp
         where cp.conversation_id = job.conversation_id
           and cp.user_id = job.sender_id
      ) then
        raise exception 'sender is no longer a participant';
      end if;
      if exists (
        select 1 from public.conversation_participants cp
        join public.blocked_users b
          on (b.blocker_id = job.sender_id and b.blocked_id = cp.user_id)
          or (b.blocked_id = job.sender_id and b.blocker_id = cp.user_id)
        where cp.conversation_id = job.conversation_id
          and cp.user_id <> job.sender_id
      ) then
        raise exception 'recipient blocked the sender';
      end if;
      if job.reply_to_id is not null and not exists (
        select 1 from public.messages m
         where m.id = job.reply_to_id
           and m.conversation_id = job.conversation_id
      ) then
        raise exception 'reply target is no longer valid';
      end if;

      perform set_config('bro.scheduled_dispatch', 'on', true);
      insert into public.messages
        (id, conversation_id, sender_id, content, content_format, created_at, reply_to_id)
      values
        (gen_random_uuid(), job.conversation_id, job.sender_id, job.content,
         'signal_v1', now(), job.reply_to_id);
      perform set_config('bro.scheduled_dispatch', '', true);

      delete from public.scheduled_messages where id = job.id;
      sent := sent + 1;
    exception when others then
      perform set_config('bro.scheduled_dispatch', '', true);
      next_attempts := coalesce(job.attempts, 0) + 1;
      update public.scheduled_messages
         set attempts = next_attempts,
             last_error = left(sqlerrm, 300),
             next_attempt_at = now() + (least(next_attempts, 5) * interval '5 minutes')
       where id = job.id;
      if next_attempts >= 5 then
        delete from public.scheduled_messages where id = job.id;
      end if;
    end;
  end loop;
  return sent;
end;
$$;
revoke all on function public.dispatch_scheduled_messages() from public, anon, authenticated;
grant execute on function public.dispatch_scheduled_messages() to service_role;

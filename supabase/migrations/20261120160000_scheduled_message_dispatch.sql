-- Scheduled messages were stored but never delivered. Dispatch due rows
-- server-side so delivery does not depend on the sender keeping the app open.

alter table public.scheduled_messages
  add column if not exists attempts integer not null default 0,
  add column if not exists last_error text,
  add column if not exists next_attempt_at timestamptz not null default now();

create index if not exists idx_scheduled_messages_due
  on public.scheduled_messages (next_attempt_at);

-- Let the trusted dispatcher insert without an HTTP user context. The flag is
-- transaction-local and only set inside the SECURITY DEFINER function below;
-- PostgREST cannot set arbitrary custom GUCs from client requests.
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
  if char_length(new.content) > 4000 then
    raise exception 'message too long';
  end if;

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

drop trigger if exists guard_message_insert on public.messages;
create trigger guard_message_insert
  before insert on public.messages
  for each row execute function public.guard_message_insert();

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
      if btrim(job.content) = '' or char_length(job.content) > 4000 then
        raise exception 'invalid scheduled content';
      end if;
      if not exists (
        select 1 from public.conversation_participants cp
         where cp.conversation_id = job.conversation_id
           and cp.user_id = job.sender_id
      ) then
        raise exception 'sender is no longer a participant';
      end if;
      if exists (
        select 1
          from public.conversation_participants cp
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
         'legacy_plaintext', now(), job.reply_to_id);
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

do $cron$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return;
  end if;
  if not exists (select 1 from cron.job where jobname = 'bro-scheduled-dispatch') then
    perform cron.schedule(
      'bro-scheduled-dispatch',
      '* * * * *',
      'select public.dispatch_scheduled_messages()'
    );
  end if;
end
$cron$;

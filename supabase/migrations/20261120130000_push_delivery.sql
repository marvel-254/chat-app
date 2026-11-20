-- Legacy Firebase Installation IDs are not copied into token registrations.
create table public.bro_push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  device_id uuid not null,
  token text not null unique check (length(token) between 20 and 4096),
  platform text not null check (platform in ('android','iOS','web')),
  refreshed_at timestamptz not null default now(),
  unique (user_id, device_id)
);
create index bro_push_devices_staleness on public.bro_push_devices (refreshed_at);
alter table public.bro_push_devices enable row level security;
revoke all on public.bro_push_devices from public, anon, authenticated;
grant select, delete on public.bro_push_devices to authenticated;
grant select, delete on public.bro_push_devices to service_role;
create policy bro_push_device_read on public.bro_push_devices for select to authenticated using (user_id = (select auth.uid()));
create policy bro_push_device_delete on public.bro_push_devices for delete to authenticated using (user_id = (select auth.uid()));

create function public.register_bro_push(p_owner uuid, p_device uuid, p_token text, p_platform text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or auth.uid() is distinct from p_owner then raise exception using errcode = '42501'; end if;
  -- Replace a rotated token by installation, but never take over another account's token.
  insert into public.bro_push_devices(user_id, device_id, token, platform)
    values(auth.uid(), p_device, p_token, p_platform)
    on conflict (user_id, device_id) do update set token = excluded.token,
      platform = excluded.platform, refreshed_at = now();
end $$;
revoke all on function public.register_bro_push(uuid,uuid,text,text) from public, anon;
grant execute on function public.register_bro_push(uuid,uuid,text,text) to authenticated;

create table public.bro_notification_preferences (
  user_id uuid primary key default auth.uid() references auth.users on delete cascade,
  messages boolean not null default true,
  calls boolean not null default true
);
alter table public.bro_notification_preferences enable row level security;
revoke all on public.bro_notification_preferences from public, anon, authenticated;
grant select, insert, update on public.bro_notification_preferences to authenticated;
create policy bro_notification_preferences_owner on public.bro_notification_preferences
  for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table public.bro_push_events (
  kind text not null check (kind in ('message','missed_call','incoming_call','friendship_reminder')),
  source_id uuid not null,
  event_day date not null default '1970-01-01',
  conversation_id uuid not null references public.conversations on delete cascade,
  sender_id uuid references auth.users on delete cascade,
  recipient_id uuid references auth.users on delete cascade,
  expires_at timestamptz not null,
  primary key(kind, source_id, event_day)
);
create table public.bro_push_deliveries (
  id bigint generated always as identity primary key,
  kind text not null,
  source_id uuid not null,
  event_day date not null,
  device_id uuid not null references public.bro_push_devices(id) on delete cascade,
  attempts int not null default 0,
  available_at timestamptz not null default now(),
  status text not null default 'pending' check (status in ('pending','sent','discarded')),
  unique(kind, source_id, event_day, device_id),
  foreign key(kind,source_id,event_day) references public.bro_push_events on delete cascade
);
create index bro_push_queue_ready on public.bro_push_deliveries(available_at, id) where status = 'pending';
create index bro_push_queue_expiry on public.bro_push_events(expires_at);
create index bro_push_queue_device on public.bro_push_deliveries(device_id);
alter table public.bro_push_events enable row level security;
alter table public.bro_push_deliveries enable row level security;
revoke all on public.bro_push_events, public.bro_push_deliveries from public, anon, authenticated;
grant select, update on public.bro_push_deliveries to service_role;

create function public.bro_queue_push() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_table_name = 'messages' then
    if new.sender_id is not null and new.conversation_id is not null then
      insert into public.bro_push_events(kind,source_id,conversation_id,sender_id,expires_at)
        values('message',new.id,new.conversation_id,new.sender_id,now() + interval '1 hour') on conflict do nothing;
    end if;
  elsif tg_table_name = 'call_sessions' then
    if tg_op = 'INSERT' and new.status = 'ringing' then
      insert into public.bro_push_events(kind,source_id,conversation_id,sender_id,recipient_id,expires_at)
        values('incoming_call',new.id,new.conversation_id,new.caller_id,new.callee_id,new.expires_at) on conflict do nothing;
    elsif tg_op = 'UPDATE' and old.status = 'ringing' and new.status = 'missed' then
      insert into public.bro_push_events(kind,source_id,conversation_id,sender_id,recipient_id,expires_at)
        values('missed_call',new.id,new.conversation_id,new.caller_id,new.callee_id,now() + interval '1 hour') on conflict do nothing;
    end if;
  end if;
  return new;
end $$;
revoke all on function public.bro_queue_push() from public, anon, authenticated;
drop trigger dispatch_message_push on public.messages;
create trigger bro_queue_message_push after insert on public.messages for each row execute function public.bro_queue_push();
create trigger bro_queue_call_push after insert or update of status on public.call_sessions
  for each row execute function public.bro_queue_push();

-- Preserve the existing annual reminder job without sending the private title out of Postgres.
create or replace function public.dispatch_friendship_reminders() returns void
language sql security definer set search_path = '' as $$
  with todo as (
    insert into public.friendship_reminder_log(date_id,sent_for)
      select id,current_date from public.friendship_dates
        where remind_annually and to_char(occurs_on,'MM-DD') = to_char(current_date,'MM-DD')
      on conflict do nothing returning date_id, sent_for
  )
  insert into public.bro_push_events(kind,source_id,event_day,conversation_id,expires_at)
    select 'friendship_reminder', d.id, todo.sent_for, d.conversation_id, now() + interval '1 hour'
    from todo join public.friendship_dates d on d.id = todo.date_id
    where d.conversation_id is not null on conflict do nothing;
$$;

create view public.bro_eligible_push as
select e.kind, e.source_id, e.event_day, e.conversation_id, e.expires_at,
      d.id device_id, d.user_id, d.token, d.platform
    from public.bro_push_events e
    join public.conversation_participants cp on cp.conversation_id = e.conversation_id
    join public.bro_push_devices d on d.user_id = cp.user_id
    left join public.bro_notification_preferences p on p.user_id = d.user_id
    where e.expires_at > now() and d.refreshed_at > now() - interval '45 days'
      and case when e.kind in ('incoming_call','missed_call') then coalesce(p.calls,true) else coalesce(p.messages,true) end
      and d.user_id is distinct from e.sender_id
      and (e.recipient_id is null or e.recipient_id = d.user_id)
      and not exists (select 1 from public.blocked_users b where (b.blocker_id,b.blocked_id)
        in ((e.sender_id,d.user_id),(d.user_id,e.sender_id)))
      and (e.kind <> 'message' or exists (select 1 from public.messages m where m.id = e.source_id
        and m.conversation_id = e.conversation_id))
      and (e.kind not in ('incoming_call','missed_call') or exists (
        select 1 from public.call_sessions c where c.id = e.source_id
          and ((e.kind = 'incoming_call' and c.status = 'ringing' and c.expires_at > now())
            or (e.kind = 'missed_call' and c.status = 'missed'))
          and not exists (select 1 from public.call_history_hidden h where h.call_id = c.id and h.user_id = d.user_id)));
revoke all on public.bro_eligible_push from public, anon, authenticated;

-- Enqueue each device once, and lease bounded batches. Delivery is at least once
-- because FCM acceptance and the database acknowledgement cannot be atomic.
create function public.claim_bro_push() returns table (
  id text, attempts int, token text, platform text, device_id uuid,
  recipient_id uuid, conversation_id uuid, source_id uuid, kind text, expires_at timestamptz
) language plpgsql security definer set search_path = '' as $$
begin
    insert into public.bro_push_deliveries(kind,source_id,event_day,device_id)
      select a.kind,a.source_id,a.event_day,a.device_id from public.bro_eligible_push a
      where not exists (select 1 from public.bro_push_deliveries existing
        where (existing.kind,existing.source_id,existing.event_day,existing.device_id)
            = (a.kind,a.source_id,a.event_day,a.device_id))
      order by (a.kind = 'incoming_call') desc, a.expires_at limit 500
      on conflict on constraint bro_push_deliveries_kind_source_id_event_day_device_id_key do nothing;
  return query
  with due as (
    select q.id, a.token, a.platform, a.user_id, a.conversation_id, a.expires_at
    from public.bro_push_deliveries q join public.bro_eligible_push a on (q.kind,q.source_id,q.event_day,q.device_id) = (a.kind,a.source_id,a.event_day,a.device_id)
    where q.status = 'pending' and q.attempts < 5 and q.available_at <= now()
    order by (q.kind = 'incoming_call') desc, q.available_at, q.id limit 32 for update of q skip locked
  )
  update public.bro_push_deliveries q set attempts = q.attempts + 1, available_at = now() + interval '2 minutes'
    from due where q.id = due.id returning q.id::text,q.attempts,due.token,due.platform,q.device_id,
    due.user_id,due.conversation_id,q.source_id,q.kind,due.expires_at;
end $$;
revoke all on function public.claim_bro_push() from public, anon, authenticated;
grant execute on function public.claim_bro_push() to service_role;

create function public.wake_bro_push() returns void language plpgsql security definer set search_path = '' as $$
declare
  endpoint text;
  secret text;
begin
  if not exists (
    select 1 from public.bro_eligible_push e left join public.bro_push_deliveries q
      on (q.kind,q.source_id,q.event_day,q.device_id) = (e.kind,e.source_id,e.event_day,e.device_id)
    where q.id is null or (q.status = 'pending' and q.attempts < 5 and q.available_at <= now())
  ) then return; end if;
  select decrypted_secret into endpoint from vault.decrypted_secrets where name = 'push_webhook_url';
  select decrypted_secret into secret from vault.decrypted_secrets where name = 'push_webhook_secret';
  if endpoint is not null and secret is not null then
    perform net.http_post(url := endpoint, body := '{}'::jsonb,
      headers := jsonb_build_object('Content-Type','application/json','x-bro-webhook-secret',secret), timeout_milliseconds := 30000);
  end if;
end $$;
revoke all on function public.wake_bro_push() from public, anon, authenticated;
select cron.schedule('bro-push-drain', '10 seconds', 'select public.wake_bro_push()');
select cron.schedule('bro-push-retention', '45 3 * * *', $job$
  delete from public.bro_push_events where expires_at < now() - interval '7 days';
  delete from public.bro_push_devices where refreshed_at < now() - interval '45 days';
$job$);

-- Separate registry: never migrate FIDs into the registration-token column.
create table public.fcm_devices (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users on delete cascade,
 device_id uuid not null, token text unique not null check(length(token) between 20 and 4096),
 platform text not null check(platform in ('android','iOS','web')), updated_at timestamptz not null default now(), unique(user_id,device_id)
);
alter table public.fcm_devices enable row level security;
revoke all on public.fcm_devices from public,anon,authenticated;
grant select,insert(user_id,device_id,platform,token),update(user_id,device_id,platform,token),delete on public.fcm_devices to authenticated;
grant all on public.fcm_devices to service_role;
create policy own_registration on public.fcm_devices for all to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
create function public.touch_registration() returns trigger language plpgsql set search_path='' as $$ begin new.updated_at=now(); return new; end; $$;
create trigger registration_touch before update on public.fcm_devices for each row execute function public.touch_registration();
create index fcm_stale on public.fcm_devices(updated_at);
create table public.push_deliveries (
 event_key text not null, device_id uuid references public.fcm_devices on delete cascade, claimed_at timestamptz not null default now(), done boolean not null default false, primary key(event_key,device_id)
);
alter table public.push_deliveries enable row level security;
revoke all on public.push_deliveries from public,anon,authenticated;
grant all on public.push_deliveries to service_role;
create function public.claim_push(p_event text,p_device uuid) returns boolean language sql set search_path='' as $$
 with claim as (insert into public.push_deliveries(event_key,device_id) values(p_event,p_device)
 on conflict(event_key,device_id) do update set claimed_at=now() where not push_deliveries.done and push_deliveries.claimed_at<now()-interval '5 minutes' returning 1) select exists(select from claim);
$$;
revoke all on function public.claim_push(text,uuid) from public,anon,authenticated;
grant execute on function public.claim_push(text,uuid) to service_role;
do $$ begin if exists(select from pg_extension where extname='pg_cron') then
 perform cron.schedule('bro-push-retention','27 3 * * *',$job$delete from public.fcm_devices where updated_at<now()-interval '60 days'; delete from public.push_deliveries where claimed_at<now()-interval '14 days'$job$);
end if; end; $$;
create or replace function public.dispatch_message_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  endpoint text;
  webhook_secret text;
begin
  select decrypted_secret into endpoint
  from vault.decrypted_secrets where name = 'push_webhook_url' limit 1;

  select decrypted_secret into webhook_secret
  from vault.decrypted_secrets where name = 'push_webhook_secret' limit 1;

  if endpoint is null or webhook_secret is null then
    return new;
  end if;

  perform net.http_post(
    url := endpoint,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-bro-webhook-secret', webhook_secret
    ),
    body := jsonb_build_object(
      'type', tg_op,
      'table', tg_table_name,
      'schema', tg_table_schema,
      'record', jsonb_build_object('id',new.id,'conversation_id',new.conversation_id,'sender_id',new.sender_id),
      'old_record', null
    ),
    timeout_milliseconds := 5000
  );

  return new;
end;
$$;

create or replace function public.dispatch_friendship_reminders()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  endpoint text;
  webhook_secret text;
  due record;
begin
  select decrypted_secret into endpoint
    from vault.decrypted_secrets where name = 'push_webhook_url' limit 1;
  select decrypted_secret into webhook_secret
    from vault.decrypted_secrets where name = 'push_webhook_secret' limit 1;

  if endpoint is null or webhook_secret is null then
    return;
  end if;

  for due in
    select d.id, d.conversation_id, d.title, d.owner_id
      from public.friendship_dates d
     where d.remind_annually
       and date_part('month', d.occurs_on) = date_part('month', current_date)
       and date_part('day', d.occurs_on) = date_part('day', current_date)
       and not exists (
         select 1 from public.friendship_reminder_log l
          where l.date_id = d.id and l.sent_for = current_date
       )
  loop
    perform net.http_post(
      url := endpoint,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-bro-webhook-secret', webhook_secret
      ),
      body := jsonb_build_object(
        'type', 'FRIENDSHIP_REMINDER',
        'schema', 'public',
        'table', 'messages',
        'record', jsonb_build_object(
          'id', due.id,
          'conversation_id', due.conversation_id,
          'sender_id', due.owner_id,
          'occurrence', current_date
        )
      )
    );
    insert into public.friendship_reminder_log (date_id, sent_for)
      values (due.id, current_date)
      on conflict do nothing;
  end loop;
end;
$$;


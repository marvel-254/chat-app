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
-- pg_net does not redeliver a failed webhook by itself. Persist only routing
-- fields; bodies, titles, FCM tokens and decrypted secrets do not belong here.
create table public.push_jobs (
 id uuid primary key default gen_random_uuid(), event jsonb not null,
 attempts integer not null default 0, next_at timestamptz not null default now(), request_id bigint,
 created_at timestamptz not null default now()
);
alter table public.push_jobs enable row level security;
revoke all on public.push_jobs from public,anon,authenticated;
create index due_push_jobs on public.push_jobs(next_at) where attempts<6;
create function public.send_push_job(job uuid) returns void language plpgsql security definer set search_path='' as $$
declare j public.push_jobs; endpoint text; secret text; req bigint;
begin
 select * into j from public.push_jobs where id=job for update;
 if not found then return;end if;
 if j.request_id is not null and exists(select from net._http_response where id=j.request_id and status_code between 200 and 299) then delete from public.push_jobs where id=job;return;end if;
 if j.attempts>=6 then return;end if;
 select decrypted_secret into endpoint from vault.decrypted_secrets where name='push_webhook_url' limit 1;
 select decrypted_secret into secret from vault.decrypted_secrets where name='push_webhook_secret' limit 1;
 if endpoint is not null and secret is not null then
   req:=net.http_post(url:=endpoint,headers:=jsonb_build_object('Content-Type','application/json','x-bro-webhook-secret',secret),body:=j.event,timeout_milliseconds:=55000);
 end if;
 update public.push_jobs set request_id=req,attempts=attempts+1,next_at=now()+make_interval(secs=>60*(1<<attempts)) where id=job;
end;$$;
create function public.enqueue_push(event jsonb) returns void language plpgsql security definer set search_path='' as $$
declare job uuid;
begin insert into public.push_jobs(event) values(event) returning id into job;perform public.send_push_job(job);end;$$;
create function public.drain_push_jobs() returns void language plpgsql security definer set search_path='' as $$
declare j uuid;
begin
 for j in select id from public.push_jobs where next_at<=now() and attempts<6 order by next_at limit 50 for update skip locked loop perform public.send_push_job(j);end loop;
 delete from public.push_jobs where created_at<now()-interval '7 days';
end;$$;
revoke all on function public.send_push_job(uuid),public.enqueue_push(jsonb),public.drain_push_jobs() from public,anon,authenticated;
do $$ begin if exists(select from pg_extension where extname='pg_cron') then perform cron.schedule('bro-push-retry','* * * * *',$job$select public.drain_push_jobs()$job$);end if;end;$$;
create or replace function public.dispatch_message_push() returns trigger language plpgsql security definer set search_path='' as $$
begin perform public.enqueue_push(jsonb_build_object('type',tg_op,'table',tg_table_name,'schema',tg_table_schema,'record',jsonb_build_object('id',new.id,'conversation_id',new.conversation_id,'sender_id',new.sender_id))); return new;end; $$;
create or replace function public.dispatch_friendship_reminders()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  due record;
begin
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
    perform public.enqueue_push(jsonb_build_object(
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


-- An installation ID is metadata, not proof of device possession. Removing
-- the installation invalidates its existing crypto/push entries; a genuinely
-- new installation still requires out-of-band fingerprint approval.
create function public.retire_installation() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update public.chat_device_keys set revoked_at=now() where user_id=new.user_id and device_id::text=new.device_id and revoked_at is null;
 delete from public.fcm_devices where user_id=new.user_id and device_id::text=new.device_id;
 return new;
end;$$;
create trigger retire_installation after update of revoked_at on public.linked_devices for each row when(old.revoked_at is null and new.revoked_at is not null) execute function public.retire_installation();
create policy not_retired_push on public.fcm_devices as restrictive for all to authenticated using(true) with check(not exists(select from public.linked_devices d where d.user_id=auth.uid() and d.device_id=fcm_devices.device_id::text and d.revoked_at is not null));

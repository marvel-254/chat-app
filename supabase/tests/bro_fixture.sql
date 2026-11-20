-- Minimal local harness: PostgreSQL executes actual migrations/functions/RLS.
-- Extension transports are stubbed; hosted Realtime, Vault, and cron need staging.
create role anon;
create role authenticated;
create role service_role bypassrls;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
grant usage on schema auth to anon,authenticated,service_role;
create publication supabase_realtime;
create table public.conversations(id uuid primary key);
create table public.conversation_participants(conversation_id uuid, user_id uuid);
create table public.conversation_participants_extra(conversation_id uuid, circle_id uuid);
create table public.blocked_users(blocker_id uuid, blocked_id uuid);
create table public.messages(id uuid primary key, conversation_id uuid, sender_id uuid, content text);
create table public.friendship_dates(id uuid primary key, conversation_id uuid, occurs_on date, remind_annually boolean);
create table public.friendship_reminder_log(date_id uuid, sent_for date, unique(date_id,sent_for));
create function public.fixture_message() returns trigger language plpgsql as $$begin return new; end$$;
create trigger dispatch_message_push after insert on public.messages for each row execute function public.fixture_message();
create schema realtime;
create table realtime.messages(payload jsonb);
alter table realtime.messages enable row level security;
create policy "Conversation members send call signals" on realtime.messages for insert with check (true);
create policy "Conversation members receive call signals" on realtime.messages for select using (true);
create function realtime.topic() returns text language sql stable as $$select current_setting('test.topic',true)$$;
create function realtime.send(payload jsonb,event text,topic text,private boolean) returns void language sql as $$
  insert into realtime.messages values(payload)
$$;
create schema net;
create function net.http_post(url text,body jsonb,headers jsonb,timeout_milliseconds int) returns bigint language sql as $$select 1::bigint$$;
create schema vault;
create table vault.decrypted_secrets(name text, decrypted_secret text);
create schema cron;
create function cron.schedule(job_name text, schedule text, command text) returns int language sql as $$select 1$$;

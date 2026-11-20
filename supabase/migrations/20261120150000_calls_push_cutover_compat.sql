-- Keep the pre-cutover clients working while the new call/push paths roll out.
-- Safe to apply both before and after 20261120120000 / 20261120130000.

-- Old clients signal on `call:<conversation>` topics; new clients use
-- `bro-call:<session>`. Both policies may coexist: each is scoped to the
-- signed-in conversation/session participant.
drop policy if exists "Conversation members send call signals" on realtime.messages;
create policy "Conversation members send call signals" on realtime.messages
  for insert to authenticated with check (
    realtime.topic() like 'call:%'
    and exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id::text = split_part(realtime.topic(), ':', 2)
        and cp.user_id = auth.uid()
    )
  );

drop policy if exists "Conversation members receive call signals" on realtime.messages;
create policy "Conversation members receive call signals" on realtime.messages
  for select to authenticated using (
    realtime.topic() like 'call:%'
    and exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id::text = split_part(realtime.topic(), ':', 2)
        and cp.user_id = auth.uid()
    )
  );

-- The legacy push webhook carried the message body; the new queue carries
-- only identifiers. Skip the legacy POST when the new queue already claimed
-- this message, so rollout cannot double-notify. Before the new migration is
-- applied bro_push_events does not exist and the legacy path is unchanged.
create or replace function public.dispatch_message_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  endpoint text;
  webhook_secret text;
  claimed boolean := false;
begin
  -- Dynamic SQL keeps this function loadable before bro_push_events exists.
  if to_regclass('public.bro_push_events') is not null then
    execute 'select exists (select 1 from public.bro_push_events e where e.kind = ''message'' and e.source_id = $1)'
      into claimed using new.id;
    if claimed then
      return new;
    end if;
  end if;

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
      'record', to_jsonb(new),
      'old_record', null
    ),
    timeout_milliseconds := 5000
  );
  return new;
end;
$$;

revoke all on function public.dispatch_message_push() from public, anon, authenticated;
drop trigger if exists dispatch_message_push on public.messages;
create trigger dispatch_message_push
  after insert on public.messages
  for each row execute function public.dispatch_message_push();

-- TURN credentials are issued by call-turn; make the quota RPC available
-- independently of the call_sessions cutover.
create table if not exists public.bro_turn_quota (
  user_id uuid primary key references auth.users on delete cascade,
  window_start timestamptz not null,
  requests integer not null
);
alter table public.bro_turn_quota enable row level security;
revoke all on public.bro_turn_quota from public, anon, authenticated;

create or replace function public.claim_bro_turn() returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  bucket timestamptz := date_trunc('minute', now());
  granted integer := 0;
begin
  if me is null then return false; end if;
  insert into public.bro_turn_quota as q values (me, bucket, 1)
    on conflict (user_id) do update set window_start = bucket,
      requests = case when q.window_start = bucket then q.requests + 1 else 1 end
    where q.window_start <> bucket or q.requests < 10 returning requests into granted;
  return granted is not null;
end $$;
revoke all on function public.claim_bro_turn() from public, anon;
grant execute on function public.claim_bro_turn() to authenticated;

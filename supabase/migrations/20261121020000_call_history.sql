-- Phase 11: per-user call history with idempotent writes and missed-call push.
-- Each participant gets their own row for the same call_id. Only public,
-- non-diagnostic metadata is stored. No recordings or media are stored here.
create table if not exists public.call_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  call_id uuid not null,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  peer_user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('voice', 'video')),
  direction text not null check (direction in ('incoming', 'outgoing')),
  status text not null check (
    status in ('completed', 'missed', 'rejected', 'cancelled', 'unanswered', 'failed')
  ),
  started_at timestamptz not null default now(),
  connected_at timestamptz,
  ended_at timestamptz,
  duration_seconds integer not null default 0 check (duration_seconds >= 0),
  failure_reason text check (length(failure_reason) <= 120),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, call_id)
);

create index if not exists call_history_user_started_idx
  on public.call_history (user_id, started_at desc);
create index if not exists call_history_conversation_idx
  on public.call_history (conversation_id);
create index if not exists call_history_status_idx
  on public.call_history (user_id, status) where status = 'missed';

alter table public.call_history enable row level security;

drop policy if exists "Call history owner read" on public.call_history;
create policy "Call history owner read" on public.call_history
  for select to authenticated using (auth.uid() = user_id);
drop policy if exists "Call history owner insert" on public.call_history;
create policy "Call history owner insert" on public.call_history
  for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Call history owner update" on public.call_history;
create policy "Call history owner update" on public.call_history
  for update to authenticated using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
drop policy if exists "Call history owner delete" on public.call_history;
create policy "Call history owner delete" on public.call_history
  for delete to authenticated using (auth.uid() = user_id);

-- Missed incoming calls go through the existing push Edge Function. The unique
-- (user_id, call_id) constraint already prevents duplicate notifications from
-- being created for the same call event.
create or replace function public.dispatch_missed_call_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  endpoint text;
  webhook_secret text;
begin
  if new.status <> 'missed' or new.direction <> 'incoming' then
    return new;
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
      'type', 'MISSED_CALL',
      'schema', 'public',
      'table', 'call_history',
      'record', jsonb_build_object(
        'id', new.id,
        'user_id', new.user_id,
        'peer_user_id', new.peer_user_id,
        'call_id', new.call_id,
        'conversation_id', new.conversation_id
      )
    ),
    timeout_milliseconds := 5000
  );

  return new;
end;
$$;

drop trigger if exists dispatch_missed_call_push on public.call_history;
create trigger dispatch_missed_call_push
  after insert on public.call_history
  for each row execute function public.dispatch_missed_call_push();

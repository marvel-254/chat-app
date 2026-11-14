-- ============================================================
-- Issue #93: Backend Rate Limiting — dedicated tracking table.
--
-- Replaces the O(N) COUNT query in guard_message_insert with a
-- constant-time lookup against a per-user tracking table.
-- Keeps the same threshold (30 messages per minute) but adds:
--   - A sliding-window tracking row updated on each insert.
--   - A cleanup cron job to vacuum stale rows.
--   - Configurable thresholds via a settings table.
-- ============================================================

-- 1. Rate-limit configuration (single row per limit type).
create table if not exists public.rate_limit_config (
  limit_type text primary key,                      -- e.g. 'message_per_minute'
  max_count  int   not null default 30,
  window_sec int   not null default 60
);

-- Seed the default: 30 messages per 60-second window.
insert into public.rate_limit_config (limit_type, max_count, window_sec)
values ('message_per_minute', 30, 60)
on conflict (limit_type) do nothing;

-- RLS: only service role (triggers) writes; authenticated users may read.
alter table public.rate_limit_config enable row level security;

create policy "RLC readable by authenticated"
  on public.rate_limit_config for select to authenticated using (true);

-- Inserts/updates are done only by SECURITY DEFINER triggers.
create policy "RLC writable by service role"
  on public.rate_limit_config for all to service_role using (true)
  with check (true);

-- 2. Per-user rate-limit tracking table.
create table if not exists public.message_rate_track (
  sender_id    uuid not null references public.profiles(id) on delete cascade,
  window_start timestamptz not null,
  msg_count    int not null default 0,
  primary key (sender_id, window_start)
);

create index on public.message_rate_track(sender_id, window_start desc);

alter table public.message_rate_track enable row level security;

-- Only the trigger (service role via SECURITY DEFINER) touches this table.
create policy "MRT writable by service role"
  on public.message_rate_track for all to service_role using (true)
  with check (true);

create policy "MRT readable by owners"
  on public.message_rate_track for select to authenticated
  using (sender_id = auth.uid());

-- 3. Helper: check and bump the rate counter for a sender.
--    Returns void when OK; raises exception when the limit is exceeded.
create or replace function public.check_message_rate(p_sender_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_max_count  int;
  v_window_sec int;
  v_window_start timestamptz;
  v_current    int;
begin
  -- Read configuration
  select max_count, window_sec into v_max_count, v_window_sec
    from public.rate_limit_config
   where limit_type = 'message_per_minute';

  if v_max_count is null then
    -- Fallback if config row is missing
    v_max_count := 30;
    v_window_sec := 60;
  end if;

  v_window_start := date_trunc('minute', now()) -
                     (extract(epoch from now())::int % v_window_sec) * interval '1 second';

  -- Upsert the tracking row
  insert into public.message_rate_track (sender_id, window_start, msg_count)
  values (p_sender_id, v_window_start, 1)
  on conflict (sender_id, window_start)
  do update set msg_count = public.message_rate_track.msg_count + 1
    returning msg_count into v_current;

  if v_current > v_max_count then
    raise exception 'rate limit exceeded (detail: % messages in the last %s)', v_current, v_window_sec
      using errcode = '23505';  -- SQLSTATE for integrity constraint
  end if;
end;
$$;

revoke execute on function public.check_message_rate(uuid) from public;
grant execute on function public.check_message_rate(uuid) to authenticated;

-- 4. Update guard_message_insert to use the tracking table.
--    We keep the existing checks (empty, length, blocks, reply) and
--    replace the COUNT-based rate limit with the new function.
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

  if char_length(new.content) > 4000 then
    raise exception 'message too long';
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

-- Ensure the trigger is attached (idempotent).
drop trigger if exists guard_message_insert on public.messages;
create trigger guard_message_insert
  before insert on public.messages
  for each row execute function public.guard_message_insert();

-- 5. Scheduled cleanup: remove tracking rows older than 5 minutes.
--    (pg_cron may not be available on all tiers; wrap in a do block.)
do $cron$
begin
  if not exists (
    select 1 from pg_extension where extname = 'pg_cron'
  ) then
    return;
  end if;

  if not exists (
    select 1 from cron.job where jobname = 'cleanup-rate-track'
  ) then
    perform cron.schedule(
      'cleanup-rate-track',
      '*/5 * * * *',
      $$delete from public.message_rate_track where window_start < now() - interval '5 minutes'$$
    );
  end if;
end;
$cron$;

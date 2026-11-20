-- One authoritative lifecycle per call. SDP/ICE is not stored in public tables.
create table public.call_sessions (
  id uuid primary key,
  conversation_id uuid not null references public.conversations on delete cascade,
  caller_id uuid not null references auth.users on delete cascade,
  callee_id uuid not null references auth.users on delete cascade,
  video boolean not null,
  status text not null default 'ringing' check (status in
    ('ringing','accepted','connected','completed','missed','rejected','cancelled','busy','failed')),
  started_at timestamptz not null default now(),
  connected_at timestamptz,
  ended_at timestamptz,
  expires_at timestamptz not null default (now() + interval '45 seconds'),
  check (caller_id <> callee_id),
  check ((status in ('ringing','accepted','connected')) = (ended_at is null)),
  check (status not in ('completed','connected') or connected_at is not null)
);
create index call_sessions_caller_recent on public.call_sessions (caller_id, started_at desc, id);
create index call_sessions_callee_recent on public.call_sessions (callee_id, started_at desc, id);
create index call_sessions_expiry on public.call_sessions (expires_at)
  where ended_at is null;

create table public.call_history_hidden (
  user_id uuid not null references auth.users on delete cascade,
  call_id uuid not null references public.call_sessions on delete cascade,
  primary key (user_id, call_id)
);
alter table public.call_sessions enable row level security;
alter table public.call_history_hidden enable row level security;
revoke all on public.call_sessions, public.call_history_hidden from public, anon, authenticated;
grant select on public.call_sessions, public.call_history_hidden to authenticated;
create policy call_participant_reads on public.call_sessions for select to authenticated
  using ((select auth.uid()) in (caller_id, callee_id) and not exists (
    select 1 from public.call_history_hidden h where h.call_id = id and h.user_id = (select auth.uid())
  ));
create policy call_owner_reads_hidden on public.call_history_hidden for select to authenticated
  using (user_id = (select auth.uid()));
alter publication supabase_realtime add table public.call_sessions;

create function public.start_bro_call(p_id uuid, p_conversation uuid, p_peer uuid, p_video boolean)
returns public.call_sessions language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  result public.call_sessions;
  initial_status text := 'ringing';
begin
  if me is null or p_peer is null or me = p_peer
    or exists (select 1 from public.conversation_participants_extra where conversation_id = p_conversation and circle_id is not null)
    or (select count(*) from public.conversation_participants where conversation_id = p_conversation) <> 2
    or (select count(*) from public.conversation_participants where conversation_id = p_conversation
          and user_id in (me, p_peer)) <> 2
    or exists (select 1 from public.blocked_users where (blocker_id, blocked_id) in ((me,p_peer),(p_peer,me))) then
    raise exception using errcode = '42501', message = 'Call unavailable';
  end if;
  -- Serialize call allocation for both participants, including calls from different devices.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(me,p_peer)::text, 1101));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(greatest(me,p_peer)::text, 1101));
  select * into result from public.call_sessions where id = p_id;
  if found then
    if (result.caller_id, result.callee_id, result.conversation_id, result.video)
        is distinct from (me, p_peer, p_conversation, p_video) then
      raise exception using errcode = '42501', message = 'Call unavailable';
    end if;
    return result;
  end if;
  if (select count(*) from public.call_sessions where caller_id = me
      and started_at > now() - interval '1 minute') >= 8 then
    raise exception 'Too many call attempts';
  end if;
  if exists (select 1 from public.call_sessions where me in (caller_id,callee_id)
      and ended_at is null and expires_at > now()) then
    raise exception 'Already in a call';
  end if;
  if exists (select 1 from public.call_sessions where p_peer in (caller_id,callee_id)
      and ended_at is null and expires_at > now()) then
    initial_status := 'busy';
  end if;
  insert into public.call_sessions(id, conversation_id, caller_id, callee_id, video, status, ended_at)
    values(p_id, p_conversation, me, p_peer, p_video, initial_status,
      case when initial_status = 'busy' then now() end) returning * into result;
  return result;
end $$;

create function public.advance_bro_call(p_id uuid, p_action text)
returns public.call_sessions language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  result public.call_sessions;
  next_status text;
  instant timestamptz;
begin
  select * into result from public.call_sessions where id = p_id for update;
  if not found or me is null or me not in (result.caller_id,result.callee_id) then
    raise exception using errcode = '42501', message = 'Call unavailable';
  end if;
  if result.ended_at is not null then return result; end if;
  instant := clock_timestamp();
  if result.expires_at <= instant then
    next_status := case when result.status = 'ringing' then 'missed' else 'failed' end;
    instant := result.expires_at;
  elsif p_action = 'accept' then
    if me <> result.callee_id or result.status <> 'ringing' then
      raise exception 'Call is no longer ringing';
    end if;
    if exists (select 1 from public.blocked_users b where (b.blocker_id,b.blocked_id)
        in ((result.caller_id,result.callee_id),(result.callee_id,result.caller_id))) then
      next_status := 'failed';
    else
      next_status := 'accepted';
    end if;
  elsif p_action = 'reject' and me = result.callee_id and result.status = 'ringing' then
    next_status := 'rejected';
  elsif p_action = 'connected' and result.status in ('accepted','connected') then
    next_status := 'connected';
  elsif p_action = 'heartbeat' and result.status = 'connected' then
    next_status := 'connected';
  elsif p_action = 'end' and result.status = 'ringing' and me = result.caller_id then
    next_status := 'cancelled';
  elsif p_action = 'end' and result.status in ('accepted','connected') then
    next_status := case when result.status = 'connected' then 'completed' else 'cancelled' end;
  elsif p_action = 'fail' and (result.status <> 'ringing' or me = result.caller_id) then
    next_status := 'failed';
  elsif p_action = 'refresh' then
    return result;
  else
    raise exception using errcode = '42501', message = 'Invalid call transition';
  end if;
  update public.call_sessions set status = next_status,
    connected_at = case when next_status = 'connected' then coalesce(connected_at, instant) else connected_at end,
    ended_at = case when next_status not in ('accepted','connected') then instant end,
    expires_at = case when next_status in ('accepted','connected') then instant + interval '60 seconds' else expires_at end
    where id = p_id returning * into result;
  return result;
end $$;

create function public.hide_bro_calls(p_id uuid default null)
returns void language sql security definer set search_path = '' as $$
  insert into public.call_history_hidden(user_id,call_id)
    select auth.uid(), s.id from public.call_sessions s
    where auth.uid() in (s.caller_id,s.callee_id) and s.ended_at is not null
      and (p_id is null or s.id = p_id)
    on conflict do nothing;
$$;

-- Keep media signaling private and stamp the actual sender/recipient in the DB.
drop policy "Conversation members send call signals" on realtime.messages;
drop policy "Conversation members receive call signals" on realtime.messages;
create policy call_session_receives_signal on realtime.messages for select to authenticated
  using (exists (select 1 from public.call_sessions c
    where realtime.topic() = 'bro-call:' || c.id::text and (select auth.uid()) in (c.caller_id,c.callee_id)));

create function public.signal_bro_call(p_id uuid, p_kind text, p_data jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  session public.call_sessions;
begin
  select * into session from public.call_sessions where id = p_id;
  if not found or me is null or me not in (session.caller_id,session.callee_id)
    or exists (select 1 from public.blocked_users b where (b.blocker_id,b.blocked_id)
        in ((session.caller_id,session.callee_id),(session.callee_id,session.caller_id)))
    or session.status not in ('accepted','connected') or session.expires_at <= now()
    or p_kind is null or p_kind not in ('offer','answer','ice','restart','ready')
    or (p_kind in ('offer','answer','restart','ready') and me <> (case when p_kind = 'offer' then session.caller_id else session.callee_id end))
    or jsonb_typeof(p_data) is distinct from 'object' or pg_column_size(p_data) > 65536 then
    raise exception using errcode = '42501', message = 'Signal unavailable';
  end if;
  perform realtime.send(jsonb_build_object('from',me,
    'to',case when me = session.caller_id then session.callee_id else session.caller_id end,
    'kind',p_kind,'data',p_data), 'signal', 'bro-call:' || p_id::text, true);
end $$;

revoke all on function public.start_bro_call(uuid,uuid,uuid,boolean), public.advance_bro_call(uuid,text),
  public.hide_bro_calls(uuid), public.signal_bro_call(uuid,text,jsonb) from public, anon;
grant execute on function public.start_bro_call(uuid,uuid,uuid,boolean), public.advance_bro_call(uuid,text),
  public.hide_bro_calls(uuid), public.signal_bro_call(uuid,text,jsonb) to authenticated;

-- Expire calls even when neither device is online, and retain only recent metadata.
select cron.schedule('bro-call-expiry', '* * * * *', $job$
  update public.call_sessions set status = case when status = 'ringing' then 'missed' else 'failed' end,
    ended_at = expires_at where ended_at is null and expires_at <= now();
  delete from public.call_sessions where started_at < now() - interval '90 days';
$job$);

create table public.bro_turn_quota (
  user_id uuid primary key references auth.users on delete cascade,
  window_start timestamptz not null,
  requests integer not null
);
alter table public.bro_turn_quota enable row level security;
revoke all on public.bro_turn_quota from public, anon, authenticated;
create function public.claim_bro_turn() returns boolean
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

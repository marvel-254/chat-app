-- check_message_rate() was callable directly by any authenticated user with
-- an arbitrary sender id, allowing one account to exhaust another's quota.
-- The sender is now always derived from the JWT. The message insert trigger
-- still passes the row sender, which must match auth.uid().

create or replace function public.check_message_rate(p_sender_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_max_count int;
  v_window_sec int;
  v_window_start timestamptz;
  v_current int;
begin
  if me is null or (p_sender_id is not null and p_sender_id <> me) then
    raise exception using errcode = '42501', message = 'Rate limit is server-controlled';
  end if;

  select max_count, window_sec into v_max_count, v_window_sec
    from public.rate_limit_config
   where limit_type = 'message_per_minute';

  if v_max_count is null then
    v_max_count := 30;
    v_window_sec := 60;
  end if;

  v_window_start := date_trunc('minute', now()) -
    (extract(epoch from now())::int % v_window_sec) * interval '1 second';

  insert into public.message_rate_track (sender_id, window_start, msg_count)
  values (me, v_window_start, 1)
  on conflict (sender_id, window_start)
  do update set msg_count = public.message_rate_track.msg_count + 1
    returning msg_count into v_current;

  if v_current > v_max_count then
    raise exception 'rate limit exceeded (detail: % messages in the last %s)',
      v_current, v_window_sec using errcode = '23505';
  end if;
end;
$$;

revoke all on function public.check_message_rate(uuid) from public, anon, authenticated;
grant execute on function public.check_message_rate(uuid) to service_role;

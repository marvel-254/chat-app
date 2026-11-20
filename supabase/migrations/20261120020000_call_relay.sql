create table public.turn_issuance (user_id uuid primary key references auth.users on delete cascade, window_start timestamptz not null, count integer not null);
alter table public.turn_issuance enable row level security;
revoke all on public.turn_issuance from public,anon,authenticated;
create function public.claim_call_relay(p_conversation uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 if auth.uid() is null or not public.is_conversation_member(p_conversation) or (select count(*) from public.conversation_participants where conversation_id=p_conversation)<>2 then return false; end if;
 insert into public.turn_issuance as t values(auth.uid(),date_trunc('hour',now()),1)
 on conflict(user_id) do update set count=case when t.window_start=excluded.window_start then t.count+1 else 1 end, window_start=excluded.window_start
 where t.count<30 or t.window_start<>excluded.window_start returning count into n;
 return n is not null;
end; $$;
revoke all on function public.claim_call_relay(uuid) from public,anon;
grant execute on function public.claim_call_relay(uuid) to authenticated;

-- Durable invitation/lease only. Do not store SDP, ICE addresses, or media here.
create table public.call_sessions (
 id uuid primary key, conversation_id uuid not null references public.conversations on delete cascade,
 sender_id uuid not null references auth.users on delete cascade, recipient_id uuid not null references auth.users on delete cascade,
 video boolean not null, state text not null check(state in ('ringing','accepted','rejected','ended')), expires_at timestamptz not null
);
create index call_recipient on public.call_sessions(recipient_id,expires_at);
create index call_sender on public.call_sessions(sender_id,expires_at);
alter table public.call_sessions enable row level security;
revoke all on public.call_sessions from public,anon,authenticated;
grant select on public.call_sessions to authenticated,service_role;
create policy call_members on public.call_sessions for select to authenticated using(auth.uid() in(sender_id,recipient_id) and public.is_conversation_member(conversation_id));
create trigger dispatch_call_push after insert on public.call_sessions for each row execute function public.dispatch_message_push();
drop policy "Conversation members send call signals" on realtime.messages;
create function public.signal_call(p_id uuid,p_conversation uuid,p_peer uuid,p_kind text,p_data jsonb) returns void language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); c public.call_sessions; payload jsonb; topic text:='call:'||p_conversation::text;
begin
 if me is null or me=p_peer or not public.is_conversation_member(p_conversation) or not exists(select from public.conversation_participants where user_id=p_peer and conversation_id=p_conversation) or (select count(*) from public.conversation_participants where conversation_id=p_conversation)<>2 then raise exception 'not a DM participant'; end if;
 if p_kind not in ('invite','accept','reject','hangup','offer','answer','ice','heartbeat') or octet_length(p_data::text)>65536 then raise exception 'invalid signal'; end if;
 if p_kind='invite' then
  perform pg_advisory_xact_lock(hashtextextended(least(me,p_peer)::text,0));
  perform pg_advisory_xact_lock(hashtextextended(greatest(me,p_peer)::text,0));
  if exists(select from public.call_sessions where (sender_id in(me,p_peer) or recipient_id in(me,p_peer)) and state in('ringing','accepted') and expires_at>now()) then raise exception 'busy'; end if;
  insert into public.call_sessions values(p_id,p_conversation,me,p_peer,coalesce((p_data->>'video')::boolean,false),'ringing',now()+interval '45 seconds');
 else
  select * into c from public.call_sessions where id=p_id and conversation_id=p_conversation and me in(sender_id,recipient_id) and p_peer in(sender_id,recipient_id) for update;
  if not found or c.expires_at<=now() or c.state not in('accepted','ringing') then raise exception 'call expired'; end if;
  if p_kind in ('accept','reject') then
   if c.state<>'ringing' or me<>c.recipient_id then raise exception 'call not ringing'; end if;
   update public.call_sessions set state=case when p_kind='accept' then 'accepted' else 'rejected' end,expires_at=now()+interval '90 seconds' where id=p_id;
  elsif p_kind='hangup' then update public.call_sessions set state='ended',expires_at=now() where id=p_id;
  elsif c.state<>'accepted' then raise exception 'call not accepted';
  elsif p_kind='heartbeat' then update public.call_sessions set expires_at=now()+interval '90 seconds' where id=p_id;return;
  end if;
 end if;
 payload=jsonb_build_object('kind',p_kind,'from',me,'to',p_peer,'call_id',p_id,'data',p_data);
 if p_kind in('invite','hangup','reject','accept') then perform realtime.send(payload,'signal',topic,true); end if;
 if p_kind<>'invite' then perform realtime.send(payload,'signal',topic||':'||p_id::text,true); end if;
end; $$;
revoke all on function public.signal_call(uuid,uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.signal_call(uuid,uuid,uuid,text,jsonb) to authenticated;
do $$ begin if exists(select from pg_extension where extname='pg_cron') then perform cron.schedule('bro-call-retention','21 * * * *',$job$delete from public.call_sessions where expires_at<now()-interval '1 day'$job$); end if;end;$$;

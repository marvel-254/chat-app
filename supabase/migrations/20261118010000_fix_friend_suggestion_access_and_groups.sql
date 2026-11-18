-- Keep relationship counts internal. Supabase may grant EXECUTE directly to
-- API roles as well as through PUBLIC, so revoke from all three explicitly.
revoke execute on function public.get_mutual_connections_count(uuid, uuid)
  from public, anon, authenticated;

-- One caller-scoped query powers both existing suggestion RPCs. Group chats
-- are marked by a circle link, even when they currently have only two members.
create function public.friend_suggestions_for_caller(
  p_category text, p_limit int, p_offset int, p_ranked boolean
)
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  last_seen_at timestamptz,
  is_online boolean,
  mutual_count int,
  suggestion_reason text,
  suggestion_type text,
  is_following boolean,
  is_close_friend boolean,
  profile_status text,
  profile_color text
)
language sql
stable
security invoker
set search_path = ''
as $$
  with my_conversations as (
    select cp.conversation_id, extra.circle_id is not null as is_group
    from public.conversation_participants cp
    left join public.conversation_participants_extra extra using (conversation_id)
    where cp.user_id = auth.uid()
  ),
  dm_peers as (
    select peer.user_id
    from my_conversations mine
    join public.conversation_participants peer using (conversation_id)
    where not mine.is_group
      and (select count(*) from public.conversation_participants cp
           where cp.conversation_id = mine.conversation_id) = 2
  ),
  shared_groups as (
    select peer.user_id, count(*)::int as total
    from my_conversations mine
    join public.conversation_participants peer using (conversation_id)
    where mine.is_group
    group by peer.user_id
  ),
  shared_circles as (
    select peer.user_id, count(*)::int as total
    from public.circle_participants mine
    join public.circle_participants peer using (circle_id)
    where mine.user_id = auth.uid()
    group by peer.user_id
  ),
  shared_follows as (
    select peer.follower_id as user_id, count(*)::int as total
    from public.user_follows mine
    join public.user_follows peer using (followed_id)
    where mine.follower_id = auth.uid()
    group by peer.follower_id
  ),
  candidates as (
    select vp.id, vp.username, vp.display_name, vp.avatar_url, vp.last_seen_at,
      vp.profile_status, vp.profile_color,
      coalesce(c.total, 0) as circles,
      coalesce(g.total, 0) as groups,
      coalesce(f.total, 0) as follows,
      outgoing.followed_id is not null as following,
      incoming.follower_id is not null as follower,
      cf.friend_id is not null as close_friend
    from public.visible_profiles vp
    left join shared_circles c on c.user_id = vp.id
    left join shared_groups g on g.user_id = vp.id
    left join shared_follows f on f.user_id = vp.id
    left join public.user_follows outgoing
      on outgoing.follower_id = auth.uid() and outgoing.followed_id = vp.id
    left join public.user_follows incoming
      on incoming.follower_id = vp.id and incoming.followed_id = auth.uid()
    left join public.close_friend_members cf
      on cf.owner_id = auth.uid() and cf.friend_id = vp.id
    where vp.id <> auth.uid() and vp.username <> ''
      and not exists (select 1 from dm_peers dm where dm.user_id = vp.id)
  ),
  scored as (
    select *, circles + groups + follows as connections,
      case
        when p_category = 'groups' and groups > 0 then 'groups'
        when circles > 0 then 'circles'
        when follows > 0 then 'mutual'
        when groups > 0 then 'groups'
        when follower then 'followers'
        else 'all'
      end as reason
    from candidates
  )
  select id, username, display_name, avatar_url, last_seen_at,
    coalesce(last_seen_at > now() - interval '60 seconds', false),
    connections,
    case reason
      when 'circles' then 'In ' || circles || case when circles = 1 then ' circle' else ' circles' end || ' with you'
      when 'mutual' then follows || case when follows = 1 then ' mutual connection' else ' mutual connections' end
      when 'groups' then groups || case when groups = 1 then ' shared group' else ' shared groups' end
      when 'followers' then 'Follows you'
      else 'Suggested for you'
    end,
    case reason
      when 'circles' then 'From your circles'
      when 'mutual' then 'Mutual connections'
      when 'groups' then 'Shared groups'
      when 'followers' then 'Follows you'
      else 'People you may know'
    end,
    following, close_friend, profile_status, profile_color
  from scored
  where case
    when p_ranked then connections > 0 or follower or close_friend
    when p_category = 'all' then true
    when p_category = 'circles' then circles > 0
    when p_category = 'mutual' then connections > 0
    when p_category = 'groups' then groups > 0
    when p_category = 'followers' then follower
    when p_category = 'close_friends' then close_friend
    else false
  end
  order by case
    when p_ranked then circles * 10 + follows * 5 + groups * 3
      + case when follower then 2 else 0 end
      + case when close_friend then 1 else 0 end
    when p_category = 'circles' then circles
    when p_category = 'groups' then groups
    else connections
  end desc, connections desc, username
  limit p_limit offset p_offset;
$$;

revoke execute on function public.friend_suggestions_for_caller(text, int, int, boolean)
  from public, anon, authenticated;

create or replace function public.get_friend_suggestions(p_limit int default 20, p_offset int default 0)
returns table (
  user_id uuid, username text, display_name text, avatar_url text,
  last_seen_at timestamptz, is_online boolean, mutual_count int,
  suggestion_reason text, suggestion_type text, is_following boolean,
  is_close_friend boolean, profile_status text, profile_color text
)
language sql stable security definer set search_path = ''
as $$
  select * from public.friend_suggestions_for_caller('all', p_limit, p_offset, true);
$$;

create or replace function public.get_friend_suggestions_by_category(p_category text, p_limit int default 10)
returns table (
  user_id uuid, username text, display_name text, avatar_url text,
  last_seen_at timestamptz, is_online boolean, mutual_count int,
  suggestion_reason text, suggestion_type text, is_following boolean,
  is_close_friend boolean, profile_status text, profile_color text
)
language sql stable security definer set search_path = ''
as $$
  select * from public.friend_suggestions_for_caller(p_category, p_limit, 0, false);
$$;

revoke execute on function public.get_friend_suggestions(int, int) from public, anon;
revoke execute on function public.get_friend_suggestions_by_category(text, int) from public, anon;
grant execute on function public.get_friend_suggestions(int, int) to authenticated;
grant execute on function public.get_friend_suggestions_by_category(text, int) to authenticated;

notify pgrst, 'reload schema';

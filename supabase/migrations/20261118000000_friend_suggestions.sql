-- ============================================================
-- Friend Suggestions: Smart recommendations with mutual connections
-- Supports "People You May Know" like Facebook Messenger
-- ============================================================

-- Function to get mutual connections count between two users
-- Checks: shared circles, mutual follows, shared conversations
create or replace function public.get_mutual_connections_count(
  a uuid,
  b uuid
)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select
    -- Mutual circles
    (
      select count(*)
      from public.circle_participants cp1
      join public.circle_participants cp2 on cp2.circle_id = cp1.circle_id
      where cp1.user_id = a
        and cp2.user_id = b
    )
    +
    -- Mutual follows (both follow same person, or follow each other)
    (
      select count(*)
      from public.user_follows f1
      join public.user_follows f2 on f2.followed_id = f1.followed_id
      where f1.follower_id = a
        and f2.follower_id = b
    )
    +
    -- Mutual conversations (participate in same circle conversations)
    (
      select count(*)
      from public.conversation_participants c1
      join public.conversation_participants c2 on c2.conversation_id = c1.conversation_id
      join public.conversation_participants_extra cpe on cpe.conversation_id = c1.conversation_id
      where c1.user_id = a
        and c2.user_id = b
    )
    as mutual_count;
$$;

grant execute on function public.get_mutual_connections_count(uuid, uuid) to authenticated;

-- Main function: Get smart friend suggestions for current user
-- Returns users with suggestion reasons and mutual connection counts
create or replace function public.get_friend_suggestions(
  p_limit int default 20,
  p_offset int default 0
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
security definer
set search_path = ''
as $$
  with current_user_id as (
    select auth.uid() as id
  ),
  -- Get users we already have conversations with (exclude from suggestions)
  existing_conversations as (
    select distinct cp.user_id as peer_id
    from public.conversation_participants cp
    join public.conversation_participants cp_me on cp_me.conversation_id = cp.conversation_id
    where cp_me.user_id = (select id from current_user_id)
      and cp.user_id <> (select id from current_user_id)
  ),
  -- Get users we already follow
  following as (
    select followed_id as user_id
    from public.user_follows
    where follower_id = (select id from current_user_id)
  ),
  -- Get close friends
  close_friends as (
    select friend_id as user_id
    from public.close_friend_members
    where owner_id = (select id from current_user_id)
  ),
  -- Get users who follow us
  followers as (
    select follower_id as user_id
    from public.user_follows
    where followed_id = (select id from current_user_id)
  ),
  -- Get shared circles
  shared_circles as (
    select
      cp2.user_id,
      count(distinct cp1.circle_id) as circle_count,
      array_agg(distinct c.name) filter (where c.name is not null) as circle_names
    from public.circle_participants cp1
    join public.circle_participants cp2 on cp2.circle_id = cp1.circle_id
    join public.circles c on c.id = cp1.circle_id
    where cp1.user_id = (select id from current_user_id)
      and cp2.user_id <> (select id from current_user_id)
    group by cp2.user_id
  ),
  -- Get mutual follows (people we both follow)
  mutual_follows as (
    select
      f2.followed_id as user_id,
      count(distinct f1.followed_id) as mutual_follow_count
    from public.user_follows f1
    join public.user_follows f2 on f2.followed_id = f1.followed_id
    where f1.follower_id = (select id from current_user_id)
      and f2.follower_id <> (select id from current_user_id)
    group by f2.followed_id
  ),
  -- Get shared group conversations (circles)
  shared_group_convs as (
    select
      cp2.user_id,
      count(distinct cp1.conversation_id) as group_count
    from public.conversation_participants cp1
    join public.conversation_participants cp2 on cp2.conversation_id = cp1.conversation_id
    join public.conversation_participants_extra cpe on cpe.conversation_id = cp1.conversation_id
    where cp1.user_id = (select id from current_user_id)
      and cp2.user_id <> (select id from current_user_id)
    group by cp2.user_id
  ),
  -- Combine all potential suggestions with scores
  scored_suggestions as (
    select
      vp.id as user_id,
      vp.username,
      vp.display_name,
      vp.avatar_url,
      vp.last_seen_at,
      vp.profile_status,
      vp.profile_color,
      coalesce(sc.circle_count, 0) as shared_circles_count,
      coalesce(sc.circle_names, '{}') as circle_names,
      coalesce(mf.mutual_follow_count, 0) as mutual_follows_count,
      coalesce(sgc.group_count, 0) as shared_groups_count,
      -- Calculate mutual connections
      public.get_mutual_connections_count((select id from current_user_id), vp.id) as mutual_count,
      case
        when f.user_id is not null then true else false end as is_following,
      case
        when cf.user_id is not null then true else false end as is_close_friend,
      case
        when fw.user_id is not null then true else false end as follows_you,
      -- Suggestion reason and type
      case
        when sc.circle_count is not null and sc.circle_count > 0 then 'From your circles'
        when mf.mutual_follow_count is not null and mf.mutual_follow_count > 0 then 'Mutual connections'
        when sgc.group_count is not null and sgc.group_count > 0 then 'Shared groups'
        when fw.user_id is not null then 'Follows you'
        else 'People you may know'
      end as suggestion_type,
      case
        when sc.circle_count is not null and sc.circle_count > 0
          then 'In ' || sc.circle_count || ' circle' || case when sc.circle_count > 1 then 's' else '' end || ' with you'
        when mf.mutual_follow_count is not null and mf.mutual_follow_count > 0
          then mf.mutual_follow_count || ' mutual connection' || case when mf.mutual_follow_count > 1 then 's' else '' end
        when sgc.group_count is not null and sgc.group_count > 0
          then sgc.group_count || ' shared group' || case when sgc.group_count > 1 then 's' else '' end
        when fw.user_id is not null
          then 'Follows you'
        else 'Suggested for you'
      end as suggestion_reason,
      -- Priority score for ordering
      (
        coalesce(sc.circle_count, 0) * 10 +
        coalesce(mf.mutual_follow_count, 0) * 5 +
        coalesce(sgc.group_count, 0) * 3 +
        case when fw.user_id is not null then 2 else 0 end +
        case when cf.user_id is not null then 1 else 0 end
      ) as priority_score
    from public.visible_profiles vp
    left join shared_circles sc on sc.user_id = vp.id
    left join mutual_follows mf on mf.user_id = vp.id
    left join shared_group_convs sgc on sgc.user_id = vp.id
    left join following f on f.user_id = vp.id
    left join close_friends cf on cf.user_id = vp.id
    left join followers fw on fw.user_id = vp.id
    where vp.id <> (select id from current_user_id)
      and vp.id not in (select peer_id from existing_conversations)
      and vp.username is not null
      and vp.username <> ''
  )
  select
    user_id,
    username,
    display_name,
    avatar_url,
    last_seen_at,
    (last_seen_at is not null and (extract(epoch from now()) - extract(epoch from last_seen_at)) < 60) as is_online,
    mutual_count,
    suggestion_reason,
    suggestion_type,
    is_following,
    is_close_friend,
    profile_status,
    profile_color
  from scored_suggestions
  where mutual_count > 0
     or shared_circles_count > 0
     or mutual_follows_count > 0
     or shared_groups_count > 0
     or follows_you
     or is_close_friend
  order by priority_score desc, mutual_count desc, username
  limit p_limit offset p_offset;
$$;

grant execute on function public.get_friend_suggestions(int, int) to authenticated;

-- Function to get suggestions by category
create or replace function public.get_friend_suggestions_by_category(
  p_category text,
  p_limit int default 10
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
security definer
set search_path = ''
as $$
  with current_user_id as (
    select auth.uid() as id
  ),
  existing_conversations as (
    select distinct cp.user_id as peer_id
    from public.conversation_participants cp
    join public.conversation_participants cp_me on cp_me.conversation_id = cp.conversation_id
    where cp_me.user_id = (select id from current_user_id)
      and cp.user_id <> (select id from current_user_id)
  ),
  following as (
    select followed_id as user_id from public.user_follows where follower_id = (select id from current_user_id)
  ),
  close_friends as (
    select friend_id as user_id from public.close_friend_members where owner_id = (select id from current_user_id)
  ),
  followers as (
    select follower_id as user_id from public.user_follows where followed_id = (select id from current_user_id)
  ),
  shared_circles as (
    select
      cp2.user_id,
      count(distinct cp1.circle_id) as circle_count,
      array_agg(distinct c.name) filter (where c.name is not null) as circle_names
    from public.circle_participants cp1
    join public.circle_participants cp2 on cp2.circle_id = cp1.circle_id
    join public.circles c on c.id = cp1.circle_id
    where cp1.user_id = (select id from current_user_id)
      and cp2.user_id <> (select id from current_user_id)
    group by cp2.user_id
  ),
  mutual_follows as (
    select
      f2.followed_id as user_id,
      count(distinct f1.followed_id) as mutual_follow_count
    from public.user_follows f1
    join public.user_follows f2 on f2.followed_id = f1.followed_id
    where f1.follower_id = (select id from current_user_id)
      and f2.follower_id <> (select id from current_user_id)
    group by f2.followed_id
  ),
  shared_group_convs as (
    select
      cp2.user_id,
      count(distinct cp1.conversation_id) as group_count
    from public.conversation_participants cp1
    join public.conversation_participants cp2 on cp2.conversation_id = cp1.conversation_id
    join public.conversation_participants_extra cpe on cpe.conversation_id = cp1.conversation_id
    where cp1.user_id = (select id from current_user_id)
      and cp2.user_id <> (select id from current_user_id)
    group by cp2.user_id
  ),
  all_suggestions as (
    select
      vp.id as user_id,
      vp.username,
      vp.display_name,
      vp.avatar_url,
      vp.last_seen_at,
      vp.profile_status,
      vp.profile_color,
      coalesce(sc.circle_count, 0) as shared_circles_count,
      coalesce(sc.circle_names, '{}') as circle_names,
      coalesce(mf.mutual_follow_count, 0) as mutual_follows_count,
      coalesce(sgc.group_count, 0) as shared_groups_count,
      public.get_mutual_connections_count((select id from current_user_id), vp.id) as mutual_count,
      case when f.user_id is not null then true else false end as is_following,
      case when cf.user_id is not null then true else false end as is_close_friend,
      case when fw.user_id is not null then true else false end as follows_you,
      case
        when sc.circle_count is not null and sc.circle_count > 0 then 'From your circles'
        when mf.mutual_follow_count is not null and mf.mutual_follow_count > 0 then 'Mutual connections'
        when sgc.group_count is not null and sgc.group_count > 0 then 'Shared groups'
        when fw.user_id is not null then 'Follows you'
        else 'People you may know'
      end as suggestion_type,
      case
        when sc.circle_count is not null and sc.circle_count > 0
          then 'In ' || sc.circle_count || ' circle' || case when sc.circle_count > 1 then 's' else '' end || ' with you'
        when mf.mutual_follow_count is not null and mf.mutual_follow_count > 0
          then mf.mutual_follow_count || ' mutual connection' || case when mf.mutual_follow_count > 1 then 's' else '' end
        when sgc.group_count is not null and sgc.group_count > 0
          then sgc.group_count || ' shared group' || case when sgc.group_count > 1 then 's' else '' end
        when fw.user_id is not null
          then 'Follows you'
        else 'Suggested for you'
      end as suggestion_reason
    from public.visible_profiles vp
    left join shared_circles sc on sc.user_id = vp.id
    left join mutual_follows mf on mf.user_id = vp.id
    left join shared_group_convs sgc on sgc.user_id = vp.id
    left join following f on f.user_id = vp.id
    left join close_friends cf on cf.user_id = vp.id
    left join followers fw on fw.user_id = vp.id
    where vp.id <> (select id from current_user_id)
      and vp.id not in (select peer_id from existing_conversations)
      and vp.username is not null
      and vp.username <> ''
  )
  select
    user_id,
    username,
    display_name,
    avatar_url,
    last_seen_at,
    (last_seen_at is not null and (extract(epoch from now()) - extract(epoch from last_seen_at)) < 60) as is_online,
    mutual_count,
    suggestion_reason,
    suggestion_type,
    is_following,
    is_close_friend,
    profile_status,
    profile_color
  from all_suggestions
  where (
    (p_category = 'circles' and shared_circles_count > 0)
    or (p_category = 'mutual' and (mutual_follows_count > 0 or mutual_count > 0))
    or (p_category = 'groups' and shared_groups_count > 0)
    or (p_category = 'followers' and follows_you)
    or (p_category = 'close_friends' and is_close_friend)
    or p_category = 'all'
  )
  order by
    case p_category
      when 'circles' then shared_circles_count
      when 'mutual' then mutual_count + mutual_follows_count
      when 'groups' then shared_groups_count
      when 'followers' then case when follows_you then 1 else 0 end
      when 'close_friends' then case when is_close_friend then 1 else 0 end
      else mutual_count
    end desc,
    mutual_count desc,
    username
  limit p_limit;
$$;

grant execute on function public.get_friend_suggestions_by_category(text, int) to authenticated;

notify pgrst, 'reload schema';
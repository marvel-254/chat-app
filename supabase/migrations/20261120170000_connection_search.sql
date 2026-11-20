-- Follower/following lists previously paginated the IDs before applying the
-- profile search, which produced incomplete results. Filter, order and
-- paginate in one query, and use a constant-time count.

create or replace function public.search_user_connections(
  p_user_id uuid,
  p_direction text,
  p_search text default '',
  p_limit integer default 30,
  p_offset integer default 0
)
returns setof public.visible_profiles
language sql
stable
set search_path = ''
as $$
  select vp.*
    from public.visible_profiles vp
   where vp.id in (
      select case when p_direction = 'followers' then uf.follower_id
                  else uf.followed_id end
        from public.user_follows uf
       where (p_direction = 'followers' and uf.followed_id = p_user_id)
          or (p_direction = 'following' and uf.follower_id = p_user_id)
   )
   and (
     coalesce(btrim(p_search), '') = ''
     or vp.username ilike '%' || p_search || '%'
     or vp.display_name ilike '%' || p_search || '%'
   )
   order by vp.username
   limit least(greatest(p_limit, 1), 100)
   offset greatest(p_offset, 0)
$$;

create or replace function public.count_user_connections(
  p_user_id uuid,
  p_direction text
)
returns integer
language sql
stable
set search_path = ''
as $$
  select count(*)::integer
    from public.user_follows uf
   where (p_direction = 'followers' and uf.followed_id = p_user_id)
      or (p_direction = 'following' and uf.follower_id = p_user_id)
$$;

revoke all on function public.search_user_connections(uuid, text, text, integer, integer),
  public.count_user_connections(uuid, text) from public, anon;
grant execute on function public.search_user_connections(uuid, text, text, integer, integer),
  public.count_user_connections(uuid, text) to authenticated;

-- Circle tables need to be in the Realtime publication for postgres_changes.
-- RLS already limits what a subscriber may see: circles are readable to signed
-- in users, participants to circle members, and invites to their participants.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'circles'
  ) then
    alter publication supabase_realtime add table public.circles;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'circle_participants'
  ) then
    alter publication supabase_realtime add table public.circle_participants;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'circle_invites'
  ) then
    alter publication supabase_realtime add table public.circle_invites;
  end if;
end $$;

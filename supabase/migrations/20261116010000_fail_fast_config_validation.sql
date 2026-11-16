-- ============================================================
-- Fail-fast configuration validation for hosted Supabase project
-- Fixes #25 (P0): App has no configured backend - placeholder SUPABASE_URL/ANON_KEY
--
-- This migration adds a validation function that can be called at
-- application startup to verify the database is properly configured
-- and not running against a placeholder/empty project.
--
-- The actual hosted project creation and credential injection is a
-- DevOps task (create project, apply migrations, set SUPABASE_URL
-- and SUPABASE_ANON_KEY via --dart-define in CI/build).
--
-- This migration provides the database-side validation layer.
-- ============================================================

-- Configuration validation function
create or replace function public.validate_supabase_config()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  result jsonb := '{}'::jsonb;
  policy_count int;
  function_count int;
  rls_enabled_count int;
  missing_tables text[];
  expected_tables text[] := array[
    'profiles',
    'conversations',
    'conversation_participants',
    'messages',
    'message_reads',
    'message_reactions',
    'push_tokens',
    'conversation_locks',
    'user_follows',
    'statuses'
  ];
  expected_functions text[] := array[
    'get_or_create_dm',
    'get_conversations_for_user',
    'mark_messages_read',
    'is_conversation_member',
    'handle_new_user',
    'guard_message_update',
    'dispatch_message_push',
    'delete_expired_messages',
    'enforce_pin_cap',
    'apply_default_message_expiry',
    'record_last_seen',
    'shares_conversation'
  ];
  expected_policies_per_table int := 2; -- minimum
begin
  -- Check all expected tables exist
  missing_tables := array(
    select t from unnest(expected_tables) t
    where not exists (
      select 1 from information_schema.tables
      where table_schema = 'public' and table_name = t
    )
  );

  if array_length(missing_tables, 1) > 0 then
    result := jsonb_build_object(
      'ok', false,
      'error', 'MISSING_TABLES',
      'missing_tables', missing_tables,
      'message', 'Required tables not found. Migrations may not have been applied.'
    );
    return result;
  end if;

  -- Check RLS is enabled on all expected tables
  select count(*) into rls_enabled_count
  from pg_tables t
  join pg_class c on c.relname = t.tablename
  where t.schemaname = 'public'
    and t.tablename = any(expected_tables)
    and c.relrowsecurity;

  if rls_enabled_count < array_length(expected_tables, 1) then
    result := jsonb_build_object(
      'ok', false,
      'error', 'RLS_NOT_ENABLED',
      'rls_enabled_count', rls_enabled_count,
      'expected_count', array_length(expected_tables, 1),
      'message', 'Row Level Security not enabled on all required tables.'
    );
    return result;
  end if;

  -- Check policies exist
  select count(*) into policy_count
  from pg_policy p
  join pg_class c on p.polrelid = c.oid
  join pg_namespace n on c.relnamespace = n.oid
  where n.nspname = 'public'
    and c.relname = any(expected_tables);

  if policy_count < array_length(expected_tables, 1) * expected_policies_per_table then
    result := jsonb_build_object(
      'ok', false,
      'error', 'INSUFFICIENT_POLICIES',
      'policy_count', policy_count,
      'expected_minimum', array_length(expected_tables, 1) * expected_policies_per_table,
      'message', 'Not enough RLS policies found. Security hardening may be incomplete.'
    );
    return result;
  end if;

  -- Check critical functions exist
  select count(*) into function_count
  from pg_proc p
  join pg_namespace n on p.pronamespace = n.oid
  where n.nspname = 'public'
    and p.proname = any(expected_functions);

  if function_count < array_length(expected_functions, 1) then
    result := jsonb_build_object(
      'ok', false,
      'error', 'MISSING_FUNCTIONS',
      'function_count', function_count,
      'expected_count', array_length(expected_functions, 1),
      'message', 'Required database functions not found.'
    );
    return result;
  end if;

  -- Verify profile creation trigger exists on auth.users
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'auth.users'::regclass
      and tgname = 'on_auth_user_created'
  ) then
    result := jsonb_build_object(
      'ok', false,
      'error', 'MISSING_PROFILE_TRIGGER',
      'message', 'Profile creation trigger on auth.users not found. New users will not get profiles automatically.'
    );
    return result;
  end if;

  -- All checks passed
  result := jsonb_build_object(
    'ok', true,
    'version', '1.0',
    'checks', jsonb_build_object(
      'tables', array_length(expected_tables, 1),
      'rls_enabled', rls_enabled_count,
      'policies', policy_count,
      'functions', function_count,
      'profile_trigger', true
    ),
    'message', 'Supabase configuration validated successfully.'
  );

  return result;
end;
$$;

grant execute on function public.validate_supabase_config() to authenticated, anon;

-- Helper: quick health check (lightweight, no auth required)
create or replace function public.health_check()
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'status', 'healthy',
    'timestamp', now(),
    'database', current_database(),
    'user', current_user
  );
$$;

grant execute on function public.health_check() to authenticated, anon;

-- Configuration metadata view (for debugging/monitoring)
create or replace view public.supabase_config_status as
select
  current_database() as database_name,
  current_user as connected_user,
  now() as checked_at,
  (select count(*) from information_schema.tables where table_schema = 'public') as table_count,
  (select count(*) from pg_policy p join pg_class c on p.polrelid = c.oid join pg_namespace n on c.relnamespace = n.oid where n.nspname = 'public') as policy_count,
  (select count(*) from pg_proc p join pg_namespace n on p.pronamespace = n.oid where n.nspname = 'public') as function_count,
  (select count(*) from pg_tables t join pg_class c on c.relname = t.tablename where t.schemaname = 'public' and c.relrowsecurity) as rls_enabled_tables,
  (select count(*) from pg_trigger where tgrelid = 'auth.users'::regclass and tgname = 'on_auth_user_created') as profile_trigger_exists;

grant select on public.supabase_config_status to authenticated, anon;
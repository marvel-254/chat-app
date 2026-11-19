-- Restore EXECUTE on shares_conversation for signed-in clients only.
--
-- 20261113000000_bug_bounty_hardening.sql revoked it from public, anon and
-- authenticated to stop anonymous clients probing conversation membership.
-- But public.visible_profiles calls it in every privacy-masked CASE branch
-- (avatar_url, game_*, profile_status, ...), so any authenticated client
-- selecting those columns got:
--   HTTP 401 / 42501 "permission denied for function shares_conversation"
-- That broke people search and friend suggestions, both of which read
-- visible_profiles through PostgREST as the authenticated role.
--
-- Grant only to authenticated: anon and public stay revoked, preserving the
-- hardening's actual goal. The function is SECURITY DEFINER (owner postgres),
-- so callers cannot read anything the view does not already expose to them.
grant execute on function public.shares_conversation(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';

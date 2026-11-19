-- Profile writes have been failing with 42501 since SELECT was revoked on
-- public.profiles by 20261106000000_privacy_and_fixes.sql. PostgreSQL requires
-- SELECT on columns read by an UPDATE/DELETE statement, including the `id`
-- column used in the WHERE clause and in the RLS policy expression. Granting
-- SELECT on `id` only keeps every privacy-masked column readable exclusively
-- through the visible_profiles view.
grant select (id) on public.profiles to authenticated;

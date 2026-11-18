-- Keep status lifetimes server-side so old and new Android/web clients agree.
alter table public.statuses
  alter column expires_at set default (now() + interval '48 hours');

-- Extend active statuses using the old default, without reviving expired
-- statuses or overriding rows that deliberately used a custom lifetime.
update public.statuses
set expires_at = created_at + interval '48 hours'
where expires_at > now()
  and expires_at = created_at + interval '24 hours';

# Linked devices

BRO registers one durable device row per installation in `public.linked_devices`.
The app stores a random installation ID locally, upserts the current device at
sign-in and when the linked-devices screen opens, and displays active rows with
last-seen timestamps.

## Controls

- **Remove device** marks one other registry row revoked. This removes it from
  the BRO device list, but does not invalidate that device's Supabase session.
- **Sign out all other sessions** uses Supabase Auth's `SignOutScope.others` and
  invalidates every other Auth session while keeping the current session active.
  The corresponding registry rows are then marked revoked.

Supabase's client Auth API does not expose a way to map a registry device ID to
one server session and revoke only that session. The UI therefore does not claim
that the per-device remove control signs a device out. Apply
`supabase/migrations/20261117120000_linked_devices.sql` before enabling the
screen in a deployed project.

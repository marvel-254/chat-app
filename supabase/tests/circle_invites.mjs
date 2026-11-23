import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

const db = new PGlite();
const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');
const run = (sql) => db.exec(sql);
const rows = async (sql) => (await db.query(sql)).rows;
const id = (n) => `20000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const a = id(1), b = id(2), c = id(3), circle = id(10);
const assume = async (role, uid = '') =>
  run(`reset role; set role ${role}; select set_config('request.jwt.claim.sub','${uid}',false);`);

try {
  await run(read('./bro_fixture.sql'));
  await run(`
    create table public.profiles(id uuid primary key, username text, display_name text, avatar_url text);
    create view public.visible_profiles as
      select id, username, display_name, avatar_url from public.profiles;
  `);
  await run(read('../migrations/20261114010000_circles_basic.sql'));
  await run(read('../migrations/20261123090000_circle_invites.sql'));
  await run(read('../migrations/20261123100000_circle_realtime.sql'));
  await run(`grant select on public.circles, public.circle_participants to authenticated;`);
  const published = (await rows(`
    select tablename from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public'
  `)).map((row) => row.tablename);
  for (const table of ['circles', 'circle_participants', 'circle_invites']) {
    assert.ok(published.includes(table), `${table} missing from realtime publication`);
  }
  await run(`
    insert into auth.users(id) values ('${a}'),('${b}'),('${c}');
    insert into public.profiles(id, username, display_name) values
      ('${a}','alice','Alice'),('${b}','bob','Bob'),('${c}','carol','Carol');
    insert into public.circles(id, name, is_private, creator_id)
      values ('${circle}','Studio Circle', true, '${a}');
    insert into public.circle_participants(circle_id, user_id, is_admin)
      values ('${circle}','${a}',true);
  `);

  await assume('authenticated', c);
  assert.equal((await rows(`select * from public.get_circle('${circle}')`)).length, 0);
  await assert.rejects(
    rows(`select public.invite_to_circle('${circle}','${b}')`),
    /Only circle admins/
  );
  assert.equal((await rows('select * from public.circle_pending_invites()')).length, 0);

  await assume('authenticated', a);
  assert.equal((await rows(`select * from public.get_circle('${circle}')`)).length, 1);
  const inviteId = (await rows(`select public.invite_to_circle('${circle}','${b}')`))[0]
    .invite_to_circle;
  assert.ok(inviteId);
  const adminView = await rows(`select * from public.circle_invites_for_circle('${circle}')`);
  assert.equal(adminView.length, 1);
  assert.equal(adminView[0].invitee_id, b);

  // Re-inviting refreshes the same pending invite instead of duplicating it.
  const again = (await rows(`select public.invite_to_circle('${circle}','${b}')`))[0]
    .invite_to_circle;
  assert.equal(again, inviteId);
  assert.equal((await rows(`select count(*)::int as n from public.circle_invites`))[0].n, 1);

  await assume('authenticated', b);
  const mine = await rows('select * from public.circle_pending_invites()');
  assert.equal(mine.length, 1);
  assert.equal(mine[0].circle_id, circle);
  assert.equal(mine[0].inviter_name, 'Alice');
  await run(`select public.accept_circle_invite('${inviteId}')`);
  assert.equal((await rows('select * from public.circle_pending_invites()')).length, 0);
  assert.equal(
    (await rows(`select count(*)::int as n from public.circle_participants
                 where circle_id='${circle}' and user_id='${b}'`))[0].n,
    1
  );
  await assert.rejects(
    run(`select public.decline_circle_invite('${inviteId}')`),
    /Invite unavailable/
  );

  await assume('authenticated', c);
  assert.equal((await rows('select * from public.circle_invites')).length, 0);
  await assert.rejects(
    run(`select public.accept_circle_invite('${inviteId}')`),
    /Invite unavailable/
  );

  await assume('authenticated', b);
  await assert.rejects(
    run(`select public.remove_circle_member('${circle}','${a}')`),
    /Only circle admins/
  );

  await assume('authenticated', a);
  await assert.rejects(
    run(`select public.remove_circle_member('${circle}','${a}')`),
    /creator cannot be removed/
  );
  await run(`select public.remove_circle_member('${circle}','${b}')`);
  assert.equal(
    (await rows(`select count(*)::int as n from public.circle_participants
                 where circle_id='${circle}' and user_id='${b}'`))[0].n,
    0
  );

  await run(`reset role; insert into public.blocked_users(blocker_id, blocked_id) values ('${a}','${c}')`);
  await assume('authenticated', a);
  await assert.rejects(
    rows(`select public.invite_to_circle('${circle}','${c}')`),
    /Invite unavailable/
  );

  console.log('Circle invites, accept/decline, admin removal and RLS passed.');
} finally {
  await db.close();
}

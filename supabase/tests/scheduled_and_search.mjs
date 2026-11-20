import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

const db = new PGlite();
const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');
const run = (sql) => db.exec(sql);
const rows = async (sql) => (await db.query(sql)).rows;
const id = (n) => `20000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const a = id(1), b = id(2), c = id(3), dm = id(4);
const assume = (role, uid = '') => run(
  `reset role; set role ${role}; select set_config('request.jwt.claim.sub','${uid}',false);`
);

try {
  await run(read('./bro_fixture.sql'));
  await run(`
    alter table public.messages add column created_at timestamptz not null default now();
    alter table public.messages add column reply_to_id uuid;
    create table public.profiles (id uuid primary key);
    create table public.user_follows (follower_id uuid, followed_id uuid);
    create view public.visible_profiles as
      select p.id, p.id::text as username, p.id::text as display_name
        from public.profiles p;
    create table public.scheduled_messages (
      id uuid primary key default gen_random_uuid(),
      sender_id uuid not null,
      conversation_id uuid not null,
      content text not null,
      reply_to_id uuid,
      scheduled_at timestamptz not null,
      created_at timestamptz not null default now()
    );
    create table public.rate_limit_config (limit_type text primary key, max_count int, window_sec int);
    create table public.message_rate_track (
      sender_id uuid, window_start timestamptz, msg_count int,
      primary key (sender_id, window_start)
    );
    create function public.check_message_rate(p_sender_id uuid) returns void
      language sql as $$ select $$;
    insert into public.rate_limit_config values ('message_per_minute', 30, 60);
    insert into auth.users values ('${a}'),('${b}'),('${c}');
    insert into public.profiles values ('${a}'),('${b}'),('${c}');
    insert into conversations values ('${dm}');
    insert into conversation_participants values ('${dm}','${a}'),('${dm}','${b}');
    insert into user_follows values ('${b}','${a}'),('${c}','${a}');
    grant all on public.user_follows, public.visible_profiles, public.profiles to authenticated;
    grant all on public.scheduled_messages, public.messages to service_role;
  `);

  await run(read('../migrations/20261120120000_call_sessions.sql'));
  await run(read('../migrations/20261120130000_push_delivery.sql'));
  await run(read('../migrations/20261120140000_legacy_message_format.sql'));
  await run(read('../migrations/20261120150000_calls_push_cutover_compat.sql'));
  await run(read('../migrations/20261120160000_scheduled_message_dispatch.sql'));
  await run(read('../migrations/20261120170000_connection_search.sql'));
  await run(read('../migrations/20261120180000_harden_message_rate_rpc.sql'));

  // Legacy and new call policies coexist, and the legacy push trigger is back.
  const policies = (await rows(
    `select policyname from pg_policies where schemaname='realtime' and tablename='messages'`
  )).map((row) => row.policyname);
  assert.ok(policies.includes('Conversation members send call signals'));
  assert.ok(policies.includes('call_session_receives_signal'));
  assert.equal((await rows(
    `select tgname from pg_trigger where tgname in ('dispatch_message_push','bro_queue_message_push')`
  )).length, 2);

  // Connection search filters before paginating and counts without loading rows.
  await assume('authenticated', a);
  assert.equal((await rows(
    `select count_user_connections('${a}','followers') value`
  ))[0].value, 2);
  assert.deepEqual((await rows(
    `select id from search_user_connections('${a}','followers','','10','0') order by id`
  )).map((row) => row.id), [b, c].sort());
  assert.deepEqual((await rows(
    `select id from search_user_connections('${a}','followers','${b}','10','0')`
  )).map((row) => row.id), [b]);

  // A due message is delivered exactly once and removed from the queue.
  await assume('postgres');
  await run(`insert into scheduled_messages(id,sender_id,conversation_id,content,scheduled_at)
    values ('${id(10)}','${a}','${dm}','scheduled hello',now() - interval '1 minute')`);
  await assume('service_role');
  await assume('service_role');
  assert.equal((await rows('select dispatch_scheduled_messages() value'))[0].value, 1);
  assert.equal((await rows(
    `select content_format from messages where content='scheduled hello'`
  ))[0].content_format, 'legacy_plaintext');
  assert.equal((await rows('select * from scheduled_messages')).length, 0);

  // Blocked recipients retry instead of silently dropping or bypassing the block.
  await assume('postgres');
  await run(`insert into blocked_users values ('${b}','${a}');
    insert into scheduled_messages(id,sender_id,conversation_id,content,scheduled_at)
    values ('${id(11)}','${a}','${dm}','blocked hello',now() - interval '1 minute')`);
  await assume('service_role');
  assert.equal((await rows('select dispatch_scheduled_messages() value'))[0].value, 0);
  assert.equal((await rows(`select attempts from scheduled_messages where id='${id(11)}'`))[0].attempts, 1);
  await assume('postgres');
  await run(`delete from blocked_users;
    update scheduled_messages set next_attempt_at=now() where id='${id(11)}'`);
  await assume('service_role');
  assert.equal((await rows('select dispatch_scheduled_messages() value'))[0].value, 1);

  // The rate-limit RPC can no longer be aimed at another account.
  await assume('authenticated', c);
  await assert.rejects(
    rows(`select check_message_rate('${a}')`),
    /server-controlled|42501|permission denied/i
  );

  console.log('Cutover compatibility, scheduled dispatch, connection search and rate-limit ownership passed.');
} catch (error) {
  console.error(error.stack ?? error, error.code ?? '', error.detail ?? '');
  process.exitCode = 1;
} finally {
  await db.close();
}

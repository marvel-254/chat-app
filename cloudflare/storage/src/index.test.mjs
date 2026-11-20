import assert from 'node:assert/strict';
import test from 'node:test';
import {
  authorizedKey,
  constantTimeEqual,
  isSafeKey,
  safeContentType,
  sign,
} from './index.js';

const user = { id: '11111111-1111-4111-8111-111111111111' };
const conversation = '22222222-2222-4222-8222-222222222222';
const env = {
  SUPABASE_URL: 'https://example.supabase.co',
  SUPABASE_ANON_KEY: 'public-anon-key',
};

test('storage keys reject traversal and require a scoped prefix', () => {
  assert.equal(isSafeKey(''), false);
  assert.equal(isSafeKey('../secret'), false);
  assert.equal(isSafeKey('a\\b/file'), false);
  assert.equal(isSafeKey(`${user.id}/background.png`), true);
  assert.equal(isSafeKey(`${conversation}/user/file.png`), true);
});

test('dangerous content types are forced to octet-stream', () => {
  assert.equal(safeContentType('text/html'), 'application/octet-stream');
  assert.equal(safeContentType('image/svg+xml'), 'application/octet-stream');
  assert.equal(safeContentType('image/png; charset=binary'), 'image/png');
});

test('background keys are owner-only; chat keys require membership', async () => {
  const originalFetch = globalThis.fetch;
  let membership = [];
  globalThis.fetch = async (url) => ({
    ok: true,
    json: async () => String(url).includes('/auth/v1/user') ? user : membership,
  });
  try {
    assert.equal(await authorizedKey(user, `${user.id}/background.jpg`, env, 'Bearer token'), true);
    assert.equal(await authorizedKey(user, `${user.id.replace('1', '2')}/background.jpg`, env, 'Bearer token'), false);
    assert.equal(await authorizedKey(user, `${conversation}/user/file.png`, env, 'Bearer token'), false);
    membership = [{ conversation_id: conversation }];
    assert.equal(await authorizedKey(user, `${conversation}/user/file.png`, env, 'Bearer token'), true);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('signed links are deterministic and compared safely', async () => {
  const a = await sign(`${conversation}/user/file.png`, 4102444800, 'secret');
  const b = await sign(`${conversation}/user/file.png`, 4102444800, 'secret');
  assert.equal(a, b);
  assert.notEqual(a, await sign('conversation/user/other.png', 4102444800, 'secret'));
  assert.equal(await constantTimeEqual(a, b), true);
  assert.equal(await constantTimeEqual(a, `${b}0`), false);
});

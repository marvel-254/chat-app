import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const script = readFileSync(new URL('../../web/service-worker.js', import.meta.url), 'utf8');
const id = '5bb13d21-611a-4693-8618-a308434174a3';
const scope = 'https://bro.example/chat-app/app/';

function worker(existing) {
  const listeners = {}, shown = [], navigation = [];
  let handler;
  const self = {
    addEventListener(event, fn) { listeners[event] = fn; },
    registration: { scope, showNotification: async (...args) => { shown.push(args); } },
    clients: {
      matchAll: async () => existing ? [
        { url: 'https://unrelated.example', navigate: () => assert.fail('cross-origin navigation') },
        { url: `${scope}#/conversations`, navigate: async (url) => {
          navigation.push(url);
          return { focus: async () => 'focused' };
        } },
      ] : [],
      openWindow: async url => navigation.push(url),
    },
  };
  vm.runInNewContext(script, { self, URL, URLSearchParams, importScripts: () => {
    self.BRO_FIREBASE_CONFIG = {};
  }, firebase: { initializeApp() {}, messaging: () => ({ onBackgroundMessage(fn) { handler = fn; } }) } });
  const data = { kind: 'missed_call', call_id: id, recipient_user_id: id, conversation_id: id,
    expires_at: new Date(Date.now() + 3600 * 1000).toISOString(), body: 'not used', url: 'https://evil.example' };
  return { listeners, shown, navigation, handler, data };
}

for (const existing of [false, true]) test(`worker reuses only an in-scope tab (existing=${existing})`, async () => {
  const { listeners, shown, navigation, handler, data } = worker(existing);
  await handler({ data });
  assert.equal(shown.length, 1);
  assert.equal(shown[0][1].body, 'You missed a call.');
  assert.equal(shown[0][1].tag, `missed_call-${id}`);
  let closed = false;
  let task;
  listeners.notificationclick({ notification: { data: shown[0][1].data, close() { closed = true; } },
    stopImmediatePropagation() {}, waitUntil(promise) { task = promise; } });
  await task;
  assert.equal(closed, true);
  assert.equal(navigation.length, 1);
  const url = new URL(navigation[0]);
  assert.equal(url.origin + url.pathname, scope);
  assert.equal(url.searchParams.get('call_id'), id);
  assert.equal(url.searchParams.has('url'), false);
});

test('bad, unknown and expired push payloads do not display', async () => {
  const { data, shown, handler } = worker(false);
  await handler({ data: { ...data, call_id: 'bad' } });
  await handler({ data: { ...data, kind: 'invitation' } });
  await handler({ data: { ...data, expires_at: '2020-01-01' } });
  assert.equal(shown.length, 0);
});

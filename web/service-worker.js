'use strict';

/* BRO PWA service worker
 * Provides offline caching for the Flutter web app at /app/.
 * Cache strategy:
 *  - App shell (index.html, main.dart.js, flutter.js, bootstrap, canvaskit,
 *    fonts, CSS, icons) → cache-first, precached at install.
 *  - Navigation requests → network-first with cache fallback (offline shell).
 *  - Supabase/API calls → never cached (network-only, pass-through).
 */

const VERSION = 'bro-pwa-v4';
const APP_SHELL = [
  'index.html',
  'main.dart.js',
  'flutter.js',
  'flutter_bootstrap.js',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'icons/Icon-maskable-192.png',
  'icons/Icon-maskable-512.png',
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(VERSION).then((cache) => cache.addAll(APP_SHELL))
      .catch(() => {})
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      // Clean up old caches
      const keys = await caches.keys();
      await Promise.all(
        keys.filter((key) => key.startsWith('bro-pwa-') && key !== VERSION).map((key) => caches.delete(key))
      );
      // Take control of open clients
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Network-only for API / auth traffic (Supabase, R2, GitHub releases)
  if (event.request.method !== 'GET' || url.origin !== self.location.origin || url.pathname.endsWith('/push-config.js')) return;

  if (event.request.mode === 'navigate') {
    const shell = new URL('index.html', self.registration.scope).href;
    event.respondWith(fetch(event.request).catch(() => caches.match(shell).then(cached => cached || Response.error())));
    return;
  }

  // App shell and assets: cache-first, except the Dart bundle and bootstrap.
  // Those use stale-while-revalidate: a returning user gets the cached copy
  // immediately instead of blocking on a multi-megabyte re-download, while the
  // fresh bundle is fetched in the background and used on the next launch.
  if (
    url.pathname.endsWith('main.dart.js') ||
    url.pathname.endsWith('flutter_bootstrap.js') ||
    url.pathname.endsWith('flutter.js')
  ) {
    event.respondWith((async () => {
      const cache = await caches.open(VERSION);
      const cached = await cache.match(event.request);
      const network = fetch(event.request)
        .then((response) => {
          if (response && response.status === 200) {
            cache.put(event.request, response.clone()).catch(() => {});
          }
          return response;
        })
        .catch(() => null);
      if (cached) {
        event.waitUntil(network);
        return cached;
      }
      return (await network) || Response.error();
    })());
    return;
  }

  if (
    url.pathname.endsWith('.js') ||
    url.pathname.endsWith('.wasm') ||
    url.pathname.endsWith('.css') ||
    url.pathname.endsWith('.json') ||
    url.pathname.endsWith('.png') ||
    url.pathname.endsWith('.svg') ||
    url.pathname.endsWith('.ttf') ||
    url.pathname.endsWith('.otf') ||
    url.pathname.endsWith('.html') ||
    url.pathname.startsWith('/app/') ||
    url.pathname.includes('/app/')
  ) {
    event.respondWith(
      caches.match(event.request).then((cached) => {
        if (cached) return cached;
        return fetch(event.request)
          .then((response) => {
            // Only cache successful same-origin responses
            if (response && response.status === 200) {
              const copy = response.clone();
              caches.open(VERSION).then((cache) => {
                cache.put(event.request, copy).catch(() => {});
              });
            }
            return response;
          })
          .catch(() => Response.error());
      })
    );
    return;
  }


});

// Register this before Firebase's click handler. A push can only open BRO's
// own scope, and Flutter revalidates account, membership and call status.
const BRO_PUSH_BODY = {
  message: 'You have a new message.',
  incoming_call: 'You have an incoming call.',
  missed_call: 'You missed a call.',
  friendship_reminder: 'A friendship anniversary is today.',
};
const BRO_ID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
function broPushData(value) {
  if (!value || !Object.hasOwn(BRO_PUSH_BODY, value.kind) ||
      !BRO_ID.test(value.recipient_user_id ?? '') || !BRO_ID.test(value.conversation_id ?? '') ||
      !Number.isFinite(Date.parse(value.expires_at)) || Date.parse(value.expires_at) <= Date.now()) return null;
  const call = value.kind === 'incoming_call' || value.kind === 'missed_call';
  const id = call ? value.call_id : value.message_id;
  if (!BRO_ID.test(id ?? '')) return null;
  return {
    kind: value.kind,
    recipient_user_id: value.recipient_user_id,
    conversation_id: value.conversation_id,
    [call ? 'call_id' : 'message_id']: id,
    expires_at: value.expires_at,
    event_id: `${value.kind}-${id}`,
  };
}

self.addEventListener('notificationclick', (event) => {
  if (!event.notification.data?.bro) return;
  event.stopImmediatePropagation();
  event.notification.close();
  const data = broPushData(event.notification.data.bro);
  if (!data) return;
  event.waitUntil((async () => {
    const url = new URL(self.registration.scope);
    url.search = new URLSearchParams({ bro_push: '1', ...data }).toString();
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const existing = windows.find(client => client.url.startsWith(self.registration.scope));
    if (existing) {
      const navigated = await existing.navigate(url.href).catch(() => null);
      if (navigated) return navigated.focus();
    }
    return self.clients.openWindow(url.href);
  })());
});

try {
  importScripts('push-config.js');
  if (self.BRO_FIREBASE_CONFIG) {
    importScripts('https://www.gstatic.com/firebasejs/12.10.0/firebase-app-compat.js',
      'https://www.gstatic.com/firebasejs/12.10.0/firebase-messaging-compat.js');
    firebase.initializeApp(self.BRO_FIREBASE_CONFIG);
    firebase.messaging().onBackgroundMessage(({ data }) => {
      const bro = broPushData(data);
      if (!bro) return;
      return self.registration.showNotification('BRO', {
        body: BRO_PUSH_BODY[bro.kind],
        icon: new URL('icons/Icon-192.png', self.registration.scope).href,
        tag: bro.event_id, renotify: false, data: { bro },
      });
    });
  }
} catch (_) {
  // Offline caching remains available on deployments without Firebase web configuration.
}

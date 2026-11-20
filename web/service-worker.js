'use strict';

/* BRO PWA service worker
 * Provides offline caching for the Flutter web app at /app/.
 * Cache strategy:
 *  - App shell (index.html, main.dart.js, flutter.js, bootstrap, canvaskit,
 *    fonts, CSS, icons) → cache-first, precached at install.
 *  - Navigation requests → network-first with cache fallback (offline shell).
 *  - Supabase/API calls → never cached (network-only, pass-through).
 */

const VERSION = 'bro-pwa-v3';
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
        keys.filter((key) => key.startsWith("bro-pwa-") && key !== VERSION).map((key) => caches.delete(key))
      );
      // Take control of open clients
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Network-only for API / auth traffic (Supabase, R2, GitHub releases)
  if (url.origin !== self.location.origin) return;

  // App shell and assets: cache-first, except the Dart bundle and bootstrap,
  // which go network-first so new releases reach users without a version bump.
  if (
    url.pathname.endsWith('main.dart.js') ||
    url.pathname.endsWith('flutter_bootstrap.js') ||
    url.pathname.endsWith('flutter.js')
  ) {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          if (response && response.status === 200) {
            const copy = response.clone();
            caches.open(VERSION).then((cache) => {
              cache.put(event.request, copy).catch(() => {});
            });
          }
          return response;
        })
        .catch(() =>
          caches.match(event.request).then((cached) => cached || Response.error())
        )
    );
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
          .catch(() => caches.match('index.html'));
      })
    );
    return;
  }

  // Navigations (SPA routes like /app/chat/<id>): network-first, fallback to shell
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          const copy = response.clone();
          caches.open(VERSION).then((cache) => {
            cache.put(event.request, copy).catch(() => {});
          });
          return response;
        })
        .catch(() => caches.match('index.html'))
    );
  }
});

// FCM data-only Web Push. Never render payload-supplied text or follow a URL.
const uuid = /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
self.addEventListener('push', event => {
  let data;
  try { data = event.data.json().data; } catch (_) { return; }
  if (!data || ![data.conversation_id,data.recipient_user_id,data.message_id].every(id=>typeof id==='string' && uuid.test(id))) return;
  event.waitUntil(self.registration.showNotification('BRO', {body:'You have a new notification.',tag:`bro:${data.message_id}`,data:{conversation_id:data.conversation_id,recipient_user_id:data.recipient_user_id}}));
});
self.addEventListener('notificationclick', event => {
  const data = event.notification.data;
  event.notification.close();
  if (!data || !uuid.test(data.conversation_id) || !uuid.test(data.recipient_user_id)) return;
  const target=new URL(self.registration.scope);
  target.search=new URLSearchParams({conversation_id:data.conversation_id,recipient_user_id:data.recipient_user_id});
  event.waitUntil((async()=>{
    const tabs=await self.clients.matchAll({type:'window'});
    const existing=tabs.find(tab=>tab.url.startsWith(self.registration.scope));
    if(existing){const tab=await existing.navigate(target.href); if(tab) return tab.focus();}
    return self.clients.openWindow(target.href);
  })());
});

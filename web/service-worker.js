'use strict';

/* BRO PWA service worker
 * Provides offline caching for the Flutter web app at /app/.
 * Cache strategy:
 *  - App shell (index.html, main.dart.js, flutter.js, bootstrap, canvaskit,
 *    fonts, CSS, icons) → cache-first, precached at install.
 *  - Navigation requests → network-first with cache fallback (offline shell).
 *  - Supabase/API calls → never cached (network-only, pass-through).
 */

const VERSION = 'bro-pwa-v1';
const APP_SHELL = [
  'index.html',
  'app.html',
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
        keys.filter((key) => key !== VERSION).map((key) => caches.delete(key))
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

  // App shell and assets: cache-first
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

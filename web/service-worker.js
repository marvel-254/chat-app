"use strict";

/* BRO PWA service worker
 * Provides offline caching for the Flutter web app at /app/.
 * Cache strategy:
 *  - App shell (index.html, main.dart.js, flutter.js, bootstrap, canvaskit,
 *    fonts, CSS, icons) → cache-first, precached at install.
 *  - Navigation requests → network-first with cache fallback (offline shell).
 *  - Supabase/API calls → never cached (network-only, pass-through).
 */

const VERSION = "bro-pwa-v3";
const APP_SHELL = [
  "index.html",
  "main.dart.js",
  "flutter.js",
  "flutter_bootstrap.js",
  "manifest.json",
  "favicon.png",
  "icons/Icon-192.png",
  "icons/Icon-512.png",
  "icons/Icon-maskable-192.png",
  "icons/Icon-maskable-512.png",
];

self.addEventListener("install", (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(VERSION).then((cache) => cache.addAll(APP_SHELL))
      .catch(() => {}),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      // Clean up old caches
      const keys = await caches.keys();
      await Promise.all(
        keys.filter((key) => key.startsWith("bro-pwa-") && key !== VERSION).map(
          (key) => caches.delete(key),
        ),
      );
      // Take control of open clients
      await self.clients.claim();
    })(),
  );
});

// Only public build artifacts belong in the offline cache. In particular,
// never key a cached navigation on a push/auth query string.
self.addEventListener("fetch", (event) => {
  const req = event.request,
    url = new URL(req.url),
    scope = new URL(self.registration.scope);
  if (
    req.method !== "GET" || url.origin !== scope.origin ||
    !url.pathname.startsWith(scope.pathname)
  ) return;
  const path = url.pathname.slice(scope.pathname.length);
  if (req.mode === "navigate") {
    event.respondWith(
      fetch(req).catch(async () =>
        await caches.match(new URL("index.html", scope).href) ||
        Response.error()
      ),
    );
    return;
  }
  if (
    url.search ||
    !(APP_SHELL.includes(path) || path === "notice-client.js" ||
      path.startsWith("assets/") || path.startsWith("canvaskit/"))
  ) return;
  event.respondWith((async () => {
    const cache = await caches.open(VERSION);
    try {
      const r = await fetch(req);
      if (r.ok) await cache.put(req, r.clone());
      return r;
    } catch {
      return await cache.match(req) || Response.error();
    }
  })());
});

// FCM data-only Web Push. Never render payload-supplied text or follow a URL.
const uuid = /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
self.addEventListener("push", (event) => {
  let data;
  try {
    data = event.data.json().data;
  } catch (_) {
    return;
  }
  if (
    !data ||
    ![data.conversation_id, data.recipient_user_id, data.message_id].every(
      (id) => typeof id === "string" && uuid.test(id),
    )
  ) return;
  event.waitUntil((async () => {
    const tab = (await self.clients.matchAll({ type: "window" })).find((w) =>
      w.visibilityState === "visible" &&
      w.url.startsWith(self.registration.scope)
    );
    const route = {
      conversation_id: data.conversation_id,
      recipient_user_id: data.recipient_user_id,
      message_id: data.message_id,
    };
    if (tab) {
      tab.postMessage({ broNotice: { route, opened: false } });
      return;
    }
    await self.registration.showNotification("BRO", {
      body: "You have a new notification.",
      tag: `bro:${data.message_id}`,
      data: route,
    });
  })());
});
self.addEventListener("notificationclick", (event) => {
  const data = event.notification.data;
  event.notification.close();
  if (
    !data || !uuid.test(data.conversation_id) ||
    !uuid.test(data.recipient_user_id)
  ) return;
  const target = new URL(self.registration.scope);
  target.search = new URLSearchParams({
    conversation_id: data.conversation_id,
    recipient_user_id: data.recipient_user_id,
  });
  event.waitUntil((async () => {
    const tabs = await self.clients.matchAll({ type: "window" });
    const existing = tabs.find((tab) =>
      tab.url.startsWith(self.registration.scope)
    );
    if (existing) {
      await existing.focus();
      existing.postMessage({
        broNotice: {
          route: {
            conversation_id: data.conversation_id,
            recipient_user_id: data.recipient_user_id,
          },
          opened: true,
        },
      });
      return;
    }
    return self.clients.openWindow(target.href);
  })());
});

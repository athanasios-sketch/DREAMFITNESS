// Bump CACHE when the shell changes; old caches are dropped on activate.
const CACHE = 'dreamfitness-v1';
const SHELL = ['/', '/icon.svg', '/manifest.webmanifest'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const { request } = e;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  // never touch auth or data: stale credentials and stale logs are both bad
  if (url.pathname.startsWith('/api/') || url.origin.includes('supabase.co')) return;

  // hashed assets are immutable - serve from cache and skip the network
  if (url.pathname.startsWith('/_astro/')) {
    e.respondWith(caches.match(request).then((hit) => hit || fetch(request).then((res) => {
      const copy = res.clone();
      caches.open(CACHE).then((c) => c.put(request, copy));
      return res;
    })));
    return;
  }

  // navigations: network first, fall back to the cached shell when offline
  if (request.mode === 'navigate') {
    e.respondWith(fetch(request).catch(() => caches.match('/').then((r) => r || Response.error())));
  }
});

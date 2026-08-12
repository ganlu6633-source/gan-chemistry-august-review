// One-time retirement worker: removes only this review site's obsolete caches.
self.addEventListener('install', () => self.skipWaiting())

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys()
    await Promise.all(keys.filter((key) => key.startsWith('gan-chemistry-shell')).map((key) => caches.delete(key)))
    await self.registration.unregister()
  })())
})

self.addEventListener('fetch', (event) => {
  if (event.request.method === 'GET') event.respondWith(fetch(event.request, { cache: 'no-store' }))
})

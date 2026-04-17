// YX Klar for Kunde — Service Worker
const CACHE='yx-kfk-v1';
const ASSETS=['/','/index.html'];

self.addEventListener('install',e=>{
  e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate',e=>{
  e.waitUntil(
    caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k))))
  );
  self.clients.claim();
});

self.addEventListener('fetch',e=>{
  const url=new URL(e.request.url);
  // Network-first for Supabase API (don't cache data requests)
  if(url.hostname.includes('supabase.co')){
    e.respondWith(fetch(e.request).catch(()=>new Response(JSON.stringify({error:'offline'}),{status:503,headers:{'Content-Type':'application/json'}})));
    return;
  }
  // Cache-first for app shell and CDN assets
  if(e.request.method==='GET'){
    e.respondWith(
      caches.match(e.request).then(cached=>{
        if(cached)return cached;
        return fetch(e.request).then(resp=>{
          if(resp.ok&&(url.hostname==='bettum1.github.io'||url.hostname==='app.yxbutikk.no'||url.hostname.includes('unpkg')||url.hostname.includes('jsdelivr')||url.hostname.includes('cloudflare'))){
            const clone=resp.clone();
            caches.open(CACHE).then(c=>c.put(e.request,clone));
          }
          return resp;
        }).catch(()=>caches.match('/index.html'));
      })
    );
  }
});

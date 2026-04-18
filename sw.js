// YX Klar for Kunde — Service Worker
const VERSION='v31';
const CACHE='yx-kfk-'+VERSION;
const ASSETS=['/','/index.html'];

self.addEventListener('install',e=>{
  e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate',e=>{
  e.waitUntil(
    caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE&&k.startsWith('yx-kfk-')).map(k=>caches.delete(k))))
  );
  self.clients.claim();
});

self.addEventListener('fetch',e=>{
  const url=new URL(e.request.url);
  // Network-first for Supabase API and index.html (always fresh app)
  if(url.hostname.includes('supabase.co')){
    e.respondWith(fetch(e.request).catch(()=>new Response(JSON.stringify({error:'offline'}),{status:503,headers:{'Content-Type':'application/json'}})));
    return;
  }
  // Network-first for the app shell — gets updates immediately when online
  if(url.pathname==='/'||url.pathname.endsWith('/index.html')){
    e.respondWith(
      fetch(e.request).then(resp=>{
        if(resp.ok){const clone=resp.clone();caches.open(CACHE).then(c=>c.put(e.request,clone));}
        return resp;
      }).catch(()=>caches.match(e.request).then(c=>c||caches.match('/index.html')))
    );
    return;
  }
  // Cache-first for CDN assets (React, fonts etc)
  if(e.request.method==='GET'){
    e.respondWith(
      caches.match(e.request).then(cached=>{
        if(cached)return cached;
        return fetch(e.request).then(resp=>{
          if(resp.ok&&(url.hostname.includes('unpkg')||url.hostname.includes('jsdelivr')||url.hostname.includes('cloudflare')||url.hostname.includes('fonts.g'))){
            const clone=resp.clone();
            caches.open(CACHE).then(c=>c.put(e.request,clone));
          }
          return resp;
        }).catch(()=>caches.match('/index.html'));
      })
    );
  }
});

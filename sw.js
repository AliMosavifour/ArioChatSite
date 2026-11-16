/* Ario service worker: lets the site install as an app (desktop / phone) and open fast.
   Same-origin GET only; Supabase / other servers are never cached. Pages and code: network first, cache when offline.
   Pictures, fonts: cache first. Audio is not cached (large). */
var V='ario-pwa-1',SHELL=['./','index.html','css/app.css?v=425','js/app.js?v=425','fonts/Vazirmatn.woff2','manifest.webmanifest','icons/icon-192.png','icons/icon-512.png'];
self.addEventListener('install',function(e){
  e.waitUntil(caches.open(V).then(function(c){return Promise.all(SHELL.map(function(u){return c.add(u).catch(function(){})}))}).then(function(){return self.skipWaiting()}));
});
self.addEventListener('activate',function(e){
  e.waitUntil(caches.keys().then(function(k){return Promise.all(k.filter(function(x){return x!==V}).map(function(x){return caches.delete(x)}))}).then(function(){return self.clients.claim()}));
});
self.addEventListener('fetch',function(e){
  var r=e.request,u=new URL(r.url);
  if(r.method!=='GET'||u.origin!==location.origin||r.headers.has('range')||/^\/?(.*\/)?audio\//.test(u.pathname))return;
  var asset=/\.(webp|png|jpg|jpeg|svg|woff2?|ico)$/i.test(u.pathname);
  if(asset){
    e.respondWith(caches.match(r).then(function(h){return h||fetch(r).then(function(n){if(n.ok){var c=n.clone();caches.open(V).then(function(x){x.put(r,c)})}return n})}));
    return;
  }
  e.respondWith(fetch(r).then(function(n){if(n.ok){var c=n.clone();caches.open(V).then(function(x){x.put(r,c)})}return n}).catch(function(){return caches.match(r).then(function(h){return h||(r.mode==='navigate'?caches.match('index.html'):Response.error())})}));
});

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve('site');
http.createServer((req,res)=>{
 try{const url=new URL(req.url,'http://localhost'),rel=decodeURIComponent(url.pathname),p=path.resolve(root,'.'+(rel.endsWith('/')?rel+'index.html':rel));
 if(!p.startsWith(root+path.sep)){res.writeHead(403).end();return;}
 const ext=path.extname(p),mime={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.svg':'image/svg+xml','.png':'image/png'};
 res.writeHead(200,{'Content-Type':mime[ext]||'application/octet-stream','Cache-Control':'no-store'});fs.createReadStream(p).on('error',()=>res.end()).pipe(res);
 }catch{res.writeHead(404).end('Not found')}
}).listen(5180,'127.0.0.1',()=>console.log('Snapcircle preview: http://127.0.0.1:5180'));

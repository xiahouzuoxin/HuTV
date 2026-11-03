import { build } from 'esbuild';
import { readdir, readFile, mkdir, writeFile, copyFile } from 'node:fs/promises';
import path from 'node:path';
// Portable Sites artifact embeds built assets; direct Cloudflare deployment uses Static Assets instead.
const assets = {};
async function walk(dir) {
  for (const e of await readdir(dir, { withFileTypes: true })) {
    const f = path.join(dir, e.name);
    if (e.isDirectory()) await walk(f);
    else {
      const ext = path.extname(f);
      const types = {
        '.html': 'text/html; charset=utf-8',
        '.js': 'text/javascript; charset=utf-8',
        '.css': 'text/css; charset=utf-8',
        '.svg': 'image/svg+xml',
        '.png': 'image/png',
      };
      assets['/' + path.relative('client-dist', f).split(path.sep).join('/')] = [
        types[ext] || 'application/octet-stream',
        (await readFile(f)).toString('base64'),
      ];
    }
  }
}
await walk('client-dist');
const code = `import {handleAPI} from './worker/index.ts';const assets=${JSON.stringify(assets)};export default {async fetch(request,env){const api=await handleAPI(request,env);if(api)return api;const url=new URL(request.url);const file=assets[url.pathname]||(!url.pathname.split('/').pop().includes('.')?assets['/index.html']:null);if(!file)return new Response('Not found',{status:404});const bytes=Uint8Array.from(atob(file[1]),c=>c.charCodeAt(0));return new Response(request.method==='HEAD'?null:bytes,{headers:{'Content-Type':file[0],'Cache-Control':url.pathname.startsWith('/assets/')?'public, max-age=31536000, immutable':'no-cache','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','X-Frame-Options':'SAMEORIGIN'}})}};`;
await mkdir('dist/server', { recursive: true });
await mkdir('dist/.openai', { recursive: true });
await build({
  stdin: { contents: code, resolveDir: process.cwd(), sourcefile: 'site-entry.ts' },
  bundle: true,
  format: 'esm',
  platform: 'browser',
  target: 'es2022',
  outfile: 'dist/server/index.js',
  minify: true,
});
await copyFile('.openai/hosting.json', 'dist/.openai/hosting.json');
console.log('Built standalone Worker artifact.');

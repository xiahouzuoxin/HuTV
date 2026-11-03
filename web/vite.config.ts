import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import worker from './worker/index.ts';
export default defineConfig({
  plugins: [
    react(),
    {
      name: 'hutv-local-api',
      configureServer(server) {
        server.middlewares.use('/api', async (req, res) => {
          try {
            let body = '';
            for await (const chunk of req) {
              body += chunk;
              if (body.length > 8192) throw Error('请求过大');
            }
            const result = await worker.fetch(
              new Request('http://localhost/api' + req.url, {
                method: req.method,
                headers: { 'Content-Type': 'application/json' },
                ...(req.method !== 'GET' ? { body } : {}),
              }),
              {},
            );
            res.statusCode = result.status;
            result.headers.forEach((v, k) => res.setHeader(k, v));
            res.end(Buffer.from(await result.arrayBuffer()));
          } catch {
            res.statusCode = 400;
            res.end(JSON.stringify({ error: '请求失败' }));
          }
        });
      },
    },
  ],
  build: { outDir: 'client-dist', chunkSizeWarningLimit: 700 },
});

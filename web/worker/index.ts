import { handleDiscovery } from './discovery.ts';
import { defaults } from '../shared/defaults.ts';
export interface Env {
  ALLOWED_ORIGINS?: string;
  ASSETS?: { fetch(request: Request): Promise<Response> };
}
import { readBoundedText } from '../shared/bounded.ts';
const json = (error: string, status: number) =>
  Response.json(
    { error },
    { status, headers: { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' } },
  );
export function allowedURL(input: string, env: Env): URL {
  const url = new URL(input);
  if (
    !['http:', 'https:'].includes(url.protocol) ||
    url.username ||
    url.password ||
    url.href.length > 4096
  )
    throw Error('不支持此地址');
  const allowed = new Set([
    ...defaults.filter((s) => s.url).map((s) => new URL(s.url).origin),
    'https://raw.githubusercontent.com',
    ...(env.ALLOWED_ORIGINS ?? '')
      .split(',')
      .map((x) => x.trim())
      .filter(Boolean),
  ]);
  if (!allowed.has(url.origin)) throw Error('此域名尚未加入代理白名单');
  const host = url.hostname.toLowerCase();
  if (
    host === 'localhost' ||
    host.endsWith('.localhost') ||
    host.endsWith('.local') ||
    host.endsWith('.internal') ||
    host.includes(':') ||
    /^[\d.]+$/.test(host)
  )
    throw Error('不允许访问本地或 IP 地址');
  return url;
}
export const boundedText = readBoundedText;
export async function handleAPI(request: Request, env: Env): Promise<Response | null> {
  const path = new URL(request.url).pathname;
  if (path === '/api/health') return Response.json({ ok: true, app: 'HuTV Web', version: '0.1.0' });
  if (!path.startsWith('/api/')) return null;
  const discovery = await handleDiscovery(request);
  if (discovery) return discovery;
  if (path !== '/api/fetch') return json('接口不存在', 404);
  if (request.method !== 'POST') return json('需要 POST 请求', 405);
  const origin = request.headers.get('origin');
  if (origin && origin !== new URL(request.url).origin) return json('仅接受同站请求', 403);
  const site = request.headers.get('sec-fetch-site');
  if (site === 'cross-site') return json('仅接受同站请求', 403);
  try {
    if (!request.headers.get('content-type')?.startsWith('application/json'))
      return json('需要 JSON 请求', 415);
    if (Number(request.headers.get('content-length') || 0) > 8192) return json('请求过大', 413);
    // Read with a hard byte limit, including when Content-Length is missing.
    const reader = request.body?.getReader();
    let text = '';
    let bytes = 0;
    const decoder = new TextDecoder();
    if (reader) {
      try {
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          bytes += value.length;
          if (bytes > 8192) {
            await reader.cancel();
            return json('请求过大', 413);
          }
          text += decoder.decode(value, { stream: true });
        }
        text += decoder.decode();
      } finally {
        reader.releaseLock();
      }
    }
    const body = JSON.parse(text);
    if (typeof body.url !== 'string') return json('缺少源地址', 400);
    let target: URL;
    try {
      target = allowedURL(body.url, env);
    } catch {
      return json('此地址不在代理白名单中', 403);
    }
    let upstream: Response | undefined;
    const signal = AbortSignal.timeout(15000);
    for (let i = 0; i < 4; i++) {
      upstream = await fetch(target, {
        headers: {
          Accept: 'application/json, text/plain, application/vnd.apple.mpegurl',
          'User-Agent': 'HuTV-Web/0.1',
        },
        redirect: 'manual',
        signal,
      });
      if (![301, 302, 303, 307, 308].includes(upstream.status)) break;
      const location = upstream.headers.get('location');
      await upstream.body?.cancel();
      if (!location) return json('源重定向无效', 502);
      try {
        target = allowedURL(new URL(location, target).href, env);
      } catch {
        return json('源重定向到了未允许的域名', 403);
      }
      if (i === 3) return json('源重定向次数过多', 502);
    }
    if (!upstream?.ok) {
      await upstream?.body?.cancel();
      return json(`源服务器返回 ${upstream?.status ?? '错误'}`, 502);
    }
    const type = upstream.headers.get('content-type') ?? '';
    if (/^(video|audio|image)\//i.test(type) && !/mpegurl/i.test(type)) {
      await upstream.body?.cancel();
      return json('此接口只读取订阅数据，不转发媒体', 415);
    }
    const result = await boundedText(upstream);
    return new Response(result, {
      headers: {
        'Content-Type': 'text/plain; charset=utf-8',
        'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff',
      },
    });
  } catch (e) {
    return json(
      e instanceof Error && /超过/.test(e.message) ? e.message : '源请求失败或超时，请稍后重试',
      502,
    );
  }
}
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const response = await handleAPI(request, env);
    if (response) return response;
    if (env.ASSETS) return env.ASSETS.fetch(request);
    return new Response('Not found', { status: 404 });
  },
};

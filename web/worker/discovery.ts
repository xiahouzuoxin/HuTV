import { coverURL, discoveryLifetime, discoveryURL } from '../shared/discovery.ts';
import { readBoundedText } from '../shared/bounded.ts';
const headers = { 'User-Agent': 'Mozilla/5.0', Referer: 'https://movie.douban.com/' };
const failure = (message: string, status = 502) =>
  Response.json({ error: message }, { status, headers: { 'Cache-Control': 'no-store' } });
async function edgeCache(): Promise<Cache | undefined> {
  try {
    return typeof caches === 'undefined' ? undefined : await caches.open('hutv-douban-v1');
  } catch {
    return undefined;
  }
}
export async function handleDiscovery(request: Request): Promise<Response | null> {
  const url = new URL(request.url);
  if (!['/api/discovery', '/api/douban-cover'].includes(url.pathname)) return null;
  if (request.method !== 'GET') return failure('需要 GET 请求', 405);
  const image = url.pathname === '/api/douban-cover';
  let upstream: URL;
  try {
    upstream = image
      ? coverURL(url.searchParams.get('url') ?? '')
      : discoveryURL(
          url.searchParams.get('type') ?? 'movie',
          url.searchParams.get('tag') ?? '热门',
        );
  } catch {
    return failure('推荐分类或封面地址无效', 400);
  }
  const key = new URL(url.origin + url.pathname);
  key.search = image ? new URLSearchParams({ url: upstream.href }).toString() : upstream.search;
  const cache = await edgeCache();
  if (url.searchParams.get('refresh') !== '1') {
    try {
      const cached = await cache?.match(key.href);
      if (cached) return cached;
    } catch {
      /* Network remains available when edge caching is unavailable. */
    }
  }
  try {
    const response = await fetch(upstream, {
      headers: { ...headers, Accept: image ? 'image/avif,image/webp,image/*' : 'application/json' },
      redirect: 'manual',
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) {
      await response.body?.cancel();
      return failure(image ? '封面暂时不可用' : '豆瓣暂时无法访问或请求受限，请稍后重试');
    }
    let result: Response;
    if (image) {
      const type = response.headers.get('content-type') ?? '';
      if (!/^image\/(?:jpeg|png|webp|avif)(?:;|$)/i.test(type)) {
        await response.body?.cancel();
        return failure('封面返回了无效图片');
      }
      if (Number(response.headers.get('content-length') ?? 0) > 2 * 1024 * 1024) {
        await response.body?.cancel();
        return failure('封面过大');
      }
      const reader = response.body?.getReader();
      if (!reader) return failure('封面为空');
      const chunks: Uint8Array[] = [];
      let size = 0;
      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          size += value.length;
          if (size > 2 * 1024 * 1024) {
            await reader.cancel();
            return failure('封面过大');
          }
          chunks.push(value);
        }
      } finally {
        reader.releaseLock();
      }
      const data = new Uint8Array(size);
      let offset = 0;
      for (const chunk of chunks) {
        data.set(chunk, offset);
        offset += chunk.length;
      }
      result = new Response(data, {
        headers: {
          'Content-Type': type,
          'Cache-Control': 'public, max-age=86400',
          'X-Content-Type-Options': 'nosniff',
        },
      });
    } else {
      const data: unknown = JSON.parse(await readBoundedText(response, 1024 * 1024));
      if (
        !data ||
        typeof data !== 'object' ||
        !('subjects' in data) ||
        !Array.isArray(data.subjects)
      )
        return failure('推荐服务未返回有效数据，请稍后重试');
      result = Response.json(
        { subjects: data.subjects.slice(0, 20) },
        { headers: { 'Cache-Control': `public, max-age=${discoveryLifetime / 1000}` } },
      );
    }
    try {
      await cache?.put(key.href, result.clone());
    } catch {
      /* Successful responses do not depend on cache writes. */
    }
    return result;
  } catch (error) {
    if(!image)console.warn('Douban discovery upstream failed',error instanceof Error?error.message:'unknown error');
    return failure(image ? '封面暂时不可用' : '暂时无法获取豆瓣推荐，请稍后重试');
  }
}

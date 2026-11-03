import { readBoundedText } from '../../shared/bounded';
import type { Source } from '../../shared/types';
import { parseCMS } from './model';
export type CMSOperation = 'browse' | 'categories' | 'search' | 'detail';
export async function fetchText(url: string, signal?: AbortSignal): Promise<string> {
  try {
    const response = await fetch('/api/fetch', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url }),
      signal,
    });
    if (response.ok) return await response.text();
    const problem = await response.json().catch(() => ({}));
    if (response.status !== 403) throw Error(problem.error || '源请求失败');
    // Custom sources can be fetched directly if their CORS policy allows it.
    try {
      const direct = await fetch(url, {
        signal: AbortSignal.any([...(signal ? [signal] : []), AbortSignal.timeout(20000)]),
      });
      if (!direct.ok) throw Error();
      return await readBoundedText(direct);
    } catch (e) {
      if (signal?.aborted) throw e;
      throw Error('此源无法直连，请将域名加入部署端 ALLOWED_ORIGINS 后重试');
    }
  } catch (e) {
    if (signal?.aborted) throw new DOMException('已取消', 'AbortError');
    throw e;
  }
}
export async function cms(
  source: Source,
  op: CMSOperation,
  params: Record<string, string> = {},
  signal?: AbortSignal,
) {
  const url = new URL(source.url);
  url.searchParams.set('ac', op === 'categories' ? 'list' : 'detail');
  Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v));
  return parseCMS(JSON.parse(await fetchText(url.href, signal)), source.id);
}
export async function concurrent<T>(
  values: T[],
  limit: number,
  signal: AbortSignal,
  work: (value: T) => Promise<void>,
) {
  let index = 0;
  await Promise.all(
    Array.from({ length: Math.min(values.length, Math.max(1, limit)) }, async () => {
      while (index < values.length && !signal.aborted) {
        const value = values[index++];
        await work(value);
      }
    }),
  );
}

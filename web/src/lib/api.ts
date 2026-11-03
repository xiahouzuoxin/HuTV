import { readBoundedText } from '../../shared/bounded';
import { requestMode, type RequestMode, type Source } from '../../shared/types';
import { parseCMS } from './model';
export type CMSOperation = 'browse' | 'categories' | 'search' | 'detail';
async function directText(url: string, signal: AbortSignal | undefined, timeout: number) {
  if (
    typeof location !== 'undefined' &&
    location.protocol === 'https:' &&
    new URL(url).protocol === 'http:'
  )
    throw Error('HTTPS 页面不能直连 HTTP 订阅，请使用服务器代理');
  const response = await fetch(url, {
    credentials: 'omit',
    referrerPolicy: 'no-referrer',
    signal: AbortSignal.any([...(signal ? [signal] : []), AbortSignal.timeout(timeout)]),
  });
  if (!response.ok) throw Error(`直连失败（HTTP ${response.status}）`);
  return readBoundedText(response);
}
async function proxyText(url: string, signal?: AbortSignal) {
  const response = await fetch('/api/fetch', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ url }),
    signal: AbortSignal.any([...(signal ? [signal] : []), AbortSignal.timeout(20000)]),
  });
  if (response.ok) return readBoundedText(response);
  const problem = await response.json().catch(() => ({}));
  throw Error(problem.error || `代理失败（HTTP ${response.status}）`);
}
export async function fetchText(
  url: string,
  signal?: AbortSignal,
  mode: RequestMode = 'auto',
): Promise<string> {
  if (signal?.aborted) throw new DOMException('已取消', 'AbortError');
  try {
    const selected = requestMode(mode);
    if (selected === 'proxy') return await proxyText(url, signal);
    try {
      return await directText(url, signal, selected === 'auto' ? 6000 : 20000);
    } catch (error) {
      if (signal?.aborted) throw error;
      if (selected === 'direct')
        throw Error(
          error instanceof Error && error.message.startsWith('HTTPS')
            ? error.message
            : '浏览器直连失败：请检查网络、跨域设置或改用服务器代理',
        );
    }
    return await proxyText(url, signal);
  } catch (error) {
    if (signal?.aborted) throw new DOMException('已取消', 'AbortError');
    throw error;
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
  return parseCMS(JSON.parse(await fetchText(url.href, signal, source.requestMode)), source.id);
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

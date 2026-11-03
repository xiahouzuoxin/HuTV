import { afterEach, describe, it, expect, vi } from 'vitest';
import {
  discoveryTags,
  discoveryURL,
  coverURL,
  parseDiscovery,
  discoveryLifetime,
} from '../shared/discovery';
import { cacheFresh } from '../src/lib/discovery';
import { initialLibrary, validateLibrary } from '../src/lib/store';
import worker from '../worker/index';
const cover = 'https://img9.doubanio.com/view/photo/s_ratio_poster/public/p1234567890.webp';
const subjects = [{ id: '1', title: '推荐影片', rate: '8.6', cover }];
afterEach(() => vi.unstubAllGlobals());
describe('Douban discovery', () => {
  it('uses the same categories and 20-item lazy request parameters as iOS', () => {
    expect(discoveryTags.tv).toContain('日本动画');
    expect(discoveryTags.movie).toContain('冷门佳片');
    const u = discoveryURL('movie', '热门');
    expect(u.origin).toBe('https://movie.douban.com');
    expect(u.searchParams.get('page_limit')).toBe('20');
    expect(() => discoveryURL('movie', 'unknown')).toThrow();
    expect(() => discoveryURL('evil', '热门')).toThrow();
  });
  it('deduplicates cards, parses ratings and caps results without trusting cover URLs', () => {
    const items = parseDiscovery(
      {
        subjects: [
          ...subjects,
          ...subjects,
          { id: 2, title: '另一部', rate: 9, cover: 'https://evil.test/img.jpg' },
          ...Array.from({ length: 30 }, (_, i) => ({ id: 'x' + i, title: '电影' + i, rate: 0 })),
        ],
      },
      'movie',
    );
    expect(items).toHaveLength(20);
    expect(items[0].rating).toEqual({ value: 8.6, kind: 'douban' });
    expect(items[0].poster).toContain('/api/douban-cover?url=');
    expect(items[1].poster).toBe('');
    expect(items[2].rating).toBeUndefined();
    expect(() => parseDiscovery('<html/>', 'movie')).toThrow();
  });
  it('only accepts known Douban CDN paths', () => {
    expect(coverURL(cover).hostname).toBe('img9.doubanio.com');
    for (const u of [
      'http://img9.doubanio.com/view/photo/s_ratio_poster/public/p123.jpg',
      'https://img9.doubanio.com.evil.test/view/photo/s_ratio_poster/public/p123.jpg',
      'https://127.0.0.1/a.jpg',
      'https://img9.doubanio.com/private',
      'https://img9.doubanio.com/view/photo/s_ratio_poster/public/p123.jpg?redirect=evil',
    ])
      expect(() => coverURL(u)).toThrow();
  });
  it('expires each cache record after 24 hours and rejects future timestamps', () => {
    const record = { updatedAt: 1000, items: [] };
    expect(cacheFresh(record, 1001)).toBe(true);
    expect(cacheFresh(record, 1000 + discoveryLifetime - 1)).toBe(true);
    expect(cacheFresh(record, 1000 + discoveryLifetime)).toBe(false);
    expect(cacheFresh(record, 999)).toBe(false);
  });
  it('removes only the obsolete demo subscription during data migration', () => {
    const data = initialLibrary();
    const old = {
      ...data,
      sources: [
        { id: 'demo', name: '公开演示片', url: '', kind: 'demo', enabled: true },
        ...data.sources,
      ],
    };
    expect(validateLibrary(old).sources).toEqual(data.sources);
    expect(initialLibrary().sources.some((s) => String(s.kind) === 'demo')).toBe(false);
  });
  it('rejects unknown image destinations before making network requests', async () => {
    const fetcher = vi.fn();
    vi.stubGlobal('fetch', fetcher);
    const r = await worker.fetch(
      new Request(
        'https://hutv.test/api/douban-cover?url=' + encodeURIComponent('https://evil.test/a.png'),
      ),
      {},
    );
    expect(r.status).toBe(400);
    expect(fetcher).not.toHaveBeenCalled();
  });
  it('sends fixed upstream headers and preserves edge cache until manual refresh', async () => {
    const values = new Map<string, Response>();
    vi.stubGlobal('caches', {
      open: async () => ({
        match: async (k: string) => values.get(k)?.clone(),
        put: async (k: string, r: Response) => {
          values.set(k, r.clone());
        },
      }),
    });
    const fetcher = vi.fn().mockImplementation(async () => Response.json({ subjects }));
    vi.stubGlobal('fetch', fetcher);
    const url = 'https://hutv.test/api/discovery?type=movie&tag=' + encodeURIComponent('热门');
    expect((await worker.fetch(new Request(url), {})).status).toBe(200);
    await worker.fetch(new Request(url), {});
    expect(fetcher).toHaveBeenCalledTimes(1);
    const init = fetcher.mock.calls[0][1];
    expect(init.redirect).toBe('manual');
    expect(init.headers.Referer).toBe('https://movie.douban.com/');
    expect(init.headers['User-Agent']).toBe('Mozilla/5.0');
    await worker.fetch(new Request(url + '&refresh=1'), {});
    expect(fetcher).toHaveBeenCalledTimes(2);
  });
  it('does not serve challenge HTML as an image or successful list', async () => {
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        .mockImplementation(
          async () =>
            new Response('<html>challenge</html>', { headers: { 'Content-Type': 'text/html' } }),
        ),
    );
    expect(
      (
        await worker.fetch(
          new Request('https://hutv.test/api/douban-cover?url=' + encodeURIComponent(cover)),
          {},
        )
      ).status,
    ).toBe(502);
    expect(
      (
        await worker.fetch(
          new Request(
            'https://hutv.test/api/discovery?type=movie&tag=' + encodeURIComponent('热门'),
          ),
          {},
        )
      ).status,
    ).toBe(502);
  });
});

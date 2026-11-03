import { afterEach, describe, it, expect, vi } from 'vitest';
import worker, { allowedURL, boundedText } from '../worker/index';
const req = (body: unknown) =>
  new Request('https://hutv.test/api/fetch', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: 'https://hutv.test' },
    body: JSON.stringify(body),
  });
afterEach(() => vi.unstubAllGlobals());
describe('bounded source proxy', () => {
  it('only allows preset and explicitly configured origins', () => {
    expect(allowedURL('https://bfzyapi.com/api.php/provide/vod/', {}).hostname).toBe('bfzyapi.com');
    for (const url of [
      'http://127.0.0.1/',
      'http://localhost/',
      'https://other.test/',
      'https://bfzyapi.com.evil.test/',
      'https://user:secret@bfzyapi.com/',
    ])
      expect(() => allowedURL(url, {})).toThrow();
    expect(
      allowedURL('https://custom.test/api', { ALLOWED_ORIGINS: 'https://custom.test' }).hostname,
    ).toBe('custom.test');
  });
  it('rejects cross-site requests, oversized bodies and unknown targets before fetching', async () => {
    const fetcher = vi.fn();
    vi.stubGlobal('fetch', fetcher);
    const cross = new Request('https://hutv.test/api/fetch', {
      method: 'POST',
      headers: { Origin: 'https://evil.test', 'Content-Type': 'application/json' },
      body: '{}',
    });
    expect((await worker.fetch(cross, {})).status).toBe(403);
    expect((await worker.fetch(req({ url: 'https://evil.test/api' }), {})).status).toBe(403);
    expect((await worker.fetch(req({ url: 'x', extra: 'a'.repeat(8500) }), {})).status).toBe(413);
    expect(fetcher).not.toHaveBeenCalled();
  });
  it('checks redirects instead of blindly following them', async () => {
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        .mockResolvedValue(
          new Response(null, { status: 302, headers: { Location: 'http://127.0.0.1/private' } }),
        ),
    );
    const r = await worker.fetch(req({ url: 'https://bfzyapi.com/api.php/provide/vod/' }), {});
    expect(r.status).toBe(403);
  });
  it('accepts live playlists served with an audio/x-mpegurl MIME type', async () => {
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        .mockResolvedValue(
          new Response('#EXTM3U\n#EXTINF:-1,频道\nhttps://example.com/a.m3u8', {
            headers: { 'Content-Type': 'audio/x-mpegurl' },
          }),
        ),
    );
    const response = await worker.fetch(
      req({ url: 'https://iptv-org.github.io/iptv/languages/zho.m3u' }),
      {},
    );
    expect(response.status).toBe(200);
    expect(await response.text()).toContain('#EXTM3U');
  });

  it('does not forward video payloads', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(new Response('data', { headers: { 'Content-Type': 'video/mp4' } })),
    );
    expect((await worker.fetch(req({ url: 'https://bfzyapi.com/v.mp4' }), {})).status).toBe(415);
  });
  it('returns source data without allowing cross-origin access or caching private requests', async () => {
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        .mockResolvedValue(
          new Response('{"list":[]}', { headers: { 'Content-Type': 'application/json' } }),
        ),
    );
    const r = await worker.fetch(req({ url: 'https://bfzyapi.com/api.php/provide/vod/' }), {});
    expect(await r.text()).toBe('{"list":[]}');
    expect(r.headers.get('Access-Control-Allow-Origin')).toBeNull();
    expect(r.headers.get('Cache-Control')).toBe('no-store');
  });
  it('enforces a stream size limit even without Content-Length', async () => {
    const body = new ReadableStream({
      start(c) {
        c.enqueue(new Uint8Array(5 * 1024 * 1024));
        c.enqueue(new Uint8Array(1));
        c.close();
      },
    });
    await expect(boundedText(new Response(body))).rejects.toThrow('5 MB');
  });
});

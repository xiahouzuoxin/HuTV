import { afterEach, describe, expect, it, vi } from 'vitest';
import { fetchText } from '../src/lib/api';
import { validateLibrary, initialLibrary } from '../src/lib/store';
import { importSources } from '../src/lib/model';
import { enterFullscreen } from '../src/lib/fullscreen';

afterEach(() => vi.unstubAllGlobals());
const url = 'https://example.com/api';
describe('per-source request routing', () => {
  it('auto prefers direct and never calls proxy on success', async () => {
    const fetcher = vi.fn().mockResolvedValue(new Response('direct'));
    vi.stubGlobal('fetch', fetcher);
    expect(await fetchText(url)).toBe('direct');
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(fetcher.mock.calls[0][0]).toBe(url);
    expect(fetcher.mock.calls[0][1].credentials).toBe('omit');
  });
  it('auto falls back on CORS/network errors and bad HTTP statuses', async () => {
    for (const failure of [new TypeError('Failed to fetch'), new Response('', { status: 403 })]) {
      const fetcher = vi.fn();
      if (failure instanceof Error) fetcher.mockRejectedValueOnce(failure);
      else fetcher.mockResolvedValueOnce(failure);
      fetcher.mockResolvedValueOnce(new Response('proxy'));
      vi.stubGlobal('fetch', fetcher);
      expect(await fetchText(url)).toBe('proxy');
      expect(fetcher.mock.calls[1][0]).toBe('/api/fetch');
    }
  });
  it('explicit direct never silently uses proxy; explicit proxy never tries direct', async () => {
    const fetcher = vi
      .fn()
      .mockRejectedValueOnce(new Error('CORS'))
      .mockResolvedValueOnce(new Response('proxy'));
    vi.stubGlobal('fetch', fetcher);
    await expect(fetchText(url, undefined, 'direct')).rejects.toThrow('浏览器直连失败');
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(await fetchText(url, undefined, 'proxy')).toBe('proxy');
    expect(fetcher.mock.calls[1][0]).toBe('/api/fetch');
  });
  it('cancellation does not start a fallback request', async () => {
    const controller = new AbortController();
    const fetcher = vi.fn().mockImplementation(() => {
      controller.abort();
      throw new Error('aborted');
    });
    vi.stubGlobal('fetch', fetcher);
    await expect(fetchText(url, controller.signal)).rejects.toMatchObject({ name: 'AbortError' });
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it('skips mixed-content direct fetch in auto and explains explicit direct failures', async () => {
    vi.stubGlobal('location', { protocol: 'https:' });
    const fetcher = vi.fn().mockResolvedValue(new Response('proxy'));
    vi.stubGlobal('fetch', fetcher);
    expect(await fetchText('http://example.com/api')).toBe('proxy');
    expect(fetcher.mock.calls[0][0]).toBe('/api/fetch');
    await expect(fetchText('http://example.com/api', undefined, 'direct')).rejects.toThrow('HTTPS');
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it('preserves modes in imports/backups and defaults old or invalid values to auto', () => {
    const library = initialLibrary();
    library.sources[0].requestMode = 'direct';
    expect(validateLibrary(library).sources[0].requestMode).toBe('direct');
    expect(validateLibrary(library).sources[1].requestMode).toBe('auto');
    expect(
      importSources('[{"api":"https://example.com/api","requestMode":"proxy"}]')[0].requestMode,
    ).toBe('proxy');
    expect(
      importSources('[{"api":"https://example.com/api","requestMode":"invalid"}]')[0].requestMode,
    ).toBe('auto');
  });
});
describe('mobile fullscreen fallback', () => {
  it('requests system fullscreen with browser navigation hidden', async () => {
    const requestFullscreen = vi.fn().mockResolvedValue(undefined);
    expect(
      await enterFullscreen(
        { requestFullscreen } as unknown as HTMLElement,
        {} as HTMLVideoElement,
      ),
    ).toBe('element');
    expect(requestFullscreen).toHaveBeenCalledWith({ navigationUI: 'hide' });
  });
  it('uses iPhone native video fullscreen before viewport expansion', async () => {
    const webkitEnterFullscreen = vi.fn();
    expect(
      await enterFullscreen(
        {} as HTMLElement,
        { webkitEnterFullscreen } as unknown as HTMLVideoElement,
      ),
    ).toBe('video');
    expect(webkitEnterFullscreen).toHaveBeenCalledTimes(1);
    expect(
      await enterFullscreen(
        {
          requestFullscreen: () => Promise.reject(new Error('unsupported')),
        } as unknown as HTMLElement,
        { webkitEnterFullscreen } as unknown as HTMLVideoElement,
      ),
    ).toBe('video');
    expect(await enterFullscreen({} as HTMLElement, {} as HTMLVideoElement)).toBe('viewport');
  });
});

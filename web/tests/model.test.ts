import { describe, it, expect } from 'vitest';
import {
  parseCMS,
  parseLive,
  importSources,
  downloadURL,
  rating,
  parseEpisodes,
} from '../src/lib/model';
import { concurrent } from '../src/lib/api';
import { validateLibrary, initialLibrary } from '../src/lib/store';

describe('CMS compatibility', () => {
  it('accepts numeric IDs, HTML descriptions, multiple lines and distinct ratings', () => {
    const parsed = parseCMS(
      {
        class: [{ type_id: 2, type_name: '剧集' }],
        list: [
          {
            vod_id: 12,
            vod_name: '测试',
            vod_content: '<p>内容&nbsp;介绍</p>',
            vod_score: 9,
            vod_douban_score: '8.6',
            vod_play_from: '线路A$$$线路B',
            vod_play_url:
              '第1集$https://example.com/1.m3u8#第2集$https://example.com/2.mp4$$$全集$https://example.com/all.mp4',
          },
        ],
      },
      's',
    );
    expect(parsed.items[0].id).toBe('12');
    expect(parsed.items[0].summary).toBe('内容 介绍');
    expect(parsed.items[0].episodes).toHaveLength(3);
    expect(parsed.items[0].rating).toEqual({ value: 8.6, kind: 'douban' });
    expect(parsed.categories[0].id).toBe('2');
  });
  it('rejects HTML and excludes unsafe or non-browser episode URLs', () => {
    expect(() => parseCMS('<html/>', 's')).toThrow();
    expect(
      parseEpisodes({
        vod_play_url:
          'a$javascript:alert(1)#b$rtsp://example.com/v#c$https://example.com/v?x=$token',
      }),
    ).toHaveLength(1);
    expect(rating({ vod_douban_score: '0', vod_score: '7.2' })).toEqual({
      value: 7.2,
      kind: 'source',
    });
    expect(rating({ vod_score: '100' })).toBeUndefined();
  });
});
describe('subscriptions and playlists', () => {
  it('accepts CMS and live list formats and converts GitHub blob URLs', () => {
    const sources = importSources(
      '[{"name":"点播","api":"https://example.com/api"},{"name":"直播","url":"https://example.com/a.m3u"}]',
    );
    expect(sources.map((s) => s.kind)).toEqual(['cms', 'live']);
    expect(downloadURL('https://github.com/owner/repo/blob/main/a.json')).toBe(
      'https://raw.githubusercontent.com/owner/repo/main/a.json',
    );
    expect(() => importSources('[{"url":"file:///private/a.json"}]')).toThrow();
    expect(() => importSources('[{"url":"https://example.com/","type":"jar"}]')).toThrow();
  });
  it('preserves M3U names, groups, relative URLs and TXT group changes', () => {
    const channels = parseLive(
      '#EXTM3U\n#EXTINF:-1 group-title="新闻" tvg-logo="https://example.com/logo.png",频道 A\n/a.m3u8\n#EXTINF:-1,频道 B\nrtsp://example.com/v\n影视,#genre#\n频道 C,https://example.com/c.m3u8',
      'https://example.com/list.m3u',
    );
    expect(channels).toHaveLength(2);
    expect(channels[0]).toMatchObject({
      name: '频道 A',
      group: '新闻',
      url: 'https://example.com/a.m3u8',
    });
    expect(channels[1].group).toBe('影视');
  });
  it('validates backup settings and disallows duplicate subscription IDs', () => {
    const data = initialLibrary();
    expect(validateLibrary(data).sources.length).toBeGreaterThan(1);
    data.settings.concurrency = 100;
    expect(validateLibrary(data).settings.concurrency).toBe(4);
    data.sources.push(data.sources[0]);
    expect(() => validateLibrary(data)).toThrow();
  });
});
describe('search request scheduling', () => {
  it('enforces the concurrency limit', async () => {
    let active = 0,
      max = 0,
      done = 0;
    await concurrent([1, 2, 3, 4, 5], 2, new AbortController().signal, async () => {
      max = Math.max(max, ++active);
      await new Promise((r) => setTimeout(r, 5));
      active--;
      done++;
    });
    expect(max).toBe(2);
    expect(done).toBe(5);
  });
  it('does not start additional requests after cancellation', async () => {
    const c = new AbortController();
    const calls: number[] = [];
    await concurrent([1, 2, 3], 1, c.signal, async (n) => {
      calls.push(n);
      c.abort();
    });
    expect(calls).toEqual([1]);
  });
});

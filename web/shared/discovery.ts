import type { Movie } from './types.ts';
export type DiscoveryKind = 'movie' | 'tv';
export const discoveryTags: Record<DiscoveryKind, readonly string[]> = {
  movie: [
    '热门',
    '最新',
    '经典',
    '豆瓣高分',
    '冷门佳片',
    '华语',
    '欧美',
    '韩国',
    '日本',
    '动作',
    '喜剧',
    '爱情',
    '科幻',
    '悬疑',
    '恐怖',
    '治愈',
    '可播放',
  ],
  tv: ['热门', '美剧', '英剧', '韩剧', '日剧', '国产剧', '港剧', '日本动画', '综艺', '纪录片'],
};
export const discoveryLifetime = 24 * 60 * 60 * 1000;
export function discoveryKey(kind: DiscoveryKind, tag: string) {
  return `${kind}|${tag}`;
}
export function discoveryURL(kind: string, tag: string): URL {
  if (!(kind === 'movie' || kind === 'tv') || !discoveryTags[kind].includes(tag))
    throw Error('不支持的推荐分类');
  const url = new URL('https://movie.douban.com/j/search_subjects');
  url.search = new URLSearchParams({
    type: kind,
    tag,
    sort: 'recommend',
    page_limit: '20',
    page_start: '0',
  }).toString();
  return url;
}
export function coverURL(raw: string): URL {
  const url = new URL(raw);
  if (
    url.protocol !== 'https:' ||
    url.username ||
    url.password ||
    url.port ||
    !/^img\d+\.doubanio\.com$/.test(url.hostname) ||
    !/^\/view\/photo\/[a-z0-9_]+\/public\/p\d+\.(?:jpe?g|png|webp)$/i.test(url.pathname) ||
    url.search ||
    url.hash
  )
    throw Error('不支持的封面地址');
  return url;
}
export function parseDiscovery(raw: unknown, kind: DiscoveryKind): Movie[] {
  if (!raw || typeof raw !== 'object' || !('subjects' in raw) || !Array.isArray(raw.subjects))
    throw Error('推荐服务未返回有效数据，请稍后重试');
  const seen = new Set<string>();
  return raw.subjects
    .flatMap((item: unknown) => {
      if (!item || typeof item !== 'object') return [];
      const v = item as Record<string, unknown>;
      const id = typeof v.id === 'string' || typeof v.id === 'number' ? String(v.id) : '';
      const title = typeof v.title === 'string' ? v.title.trim() : '';
      if (!id || !title || seen.has(id)) return [];
      seen.add(id);
      let poster = '';
      try {
        if (typeof v.cover === 'string')
          poster = '/api/douban-cover?url=' + encodeURIComponent(coverURL(v.cover).href);
      } catch {
        /* A blocked/malformed cover never hides a recommendation. */
      }
      const number =
        typeof v.rate === 'number' || typeof v.rate === 'string' ? Number(v.rate) : NaN;
      const movie: Movie = {
        id,
        sourceId: 'douban',
        title,
        poster,
        remarks: '',
        year: '',
        area: '',
        category: kind === 'movie' ? '电影' : '剧集',
        summary: '',
        actors: '',
        director: '',
        language: '',
        episodes: [],
        ...(number > 0 && number <= 10
          ? { rating: { value: number, kind: 'douban' as const } }
          : {}),
      };
      return [movie];
    })
    .slice(0, 20);
}

import type { Category, Channel, Episode, Movie, Rating, Source } from '../../shared/types';
const value = (x: unknown) =>
  typeof x === 'string' || typeof x === 'number' ? String(x).trim() : '';
export function clean(x: unknown): string {
  return value(x)
    .replace(/<[^>]*>/g, ' ')
    .replace(/&nbsp;|&#160;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/\s+/g, ' ')
    .trim();
}
export function httpURL(text: string): string {
  const url = new URL(text.trim());
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password)
    throw Error('需要 HTTP(S) 地址，不能包含账号密码');
  return url.href;
}
export function downloadURL(text: string): string {
  const u = new URL(httpURL(text));
  if (u.hostname === 'github.com') {
    const p = u.pathname.split('/');
    if (p[3] !== 'blob' || p.length < 6) throw Error('请使用 GitHub 文件链接');
    u.hostname = 'raw.githubusercontent.com';
    p.splice(3, 1);
    u.pathname = p.join('/');
    u.search = '';
    u.hash = '';
  }
  return u.href;
}
export function rating(v: Record<string, unknown>): Rating | undefined {
  for (const [key, kind] of [
    ['vod_douban_score', 'douban'],
    ['vod_score', 'source'],
  ] as const) {
    const raw = value(v[key]);
    if (!/^\d+(?:\.\d+)?$/.test(raw)) continue;
    const n = Number(raw);
    if (n > 0 && n <= 10) return { value: n, kind };
  }
}
export function parseEpisodes(v: Record<string, unknown>): Episode[] {
  const lines = value(v.vod_play_from).split('$$$');
  return value(v.vod_play_url)
    .split('$$$')
    .flatMap((playlist, line) =>
      playlist.split('#').flatMap((entry, i) => {
        const at = entry.indexOf('$');
        if (at < 0) return [];
        const address = entry.slice(at + 1).trim();
        try {
          return [
            {
              id: `${line}|${i}|${address}`,
              name: clean(entry.slice(0, at)) || `第 ${i + 1} 集`,
              url: httpURL(address),
              line: lines[line] || `线路 ${line + 1}`,
            },
          ];
        } catch {
          return [];
        }
      }),
    );
}
export function parseCMS(
  data: unknown,
  sourceId: string,
): { items: Movie[]; categories: Category[]; pages: number } {
  if (!data || typeof data !== 'object' || (!('list' in data) && !('class' in data)))
    throw Error('此接口没有返回 CMS JSON，请检查订阅类型和地址');
  const d = data as Record<string, unknown>;
  const categories = (Array.isArray(d.class) ? d.class : [])
    .filter((v) => v && typeof v === 'object')
    .map((v) => ({ id: value(v.type_id), name: clean(v.type_name) }));
  const items = (Array.isArray(d.list) ? d.list : [])
    .filter((v) => v && typeof v === 'object' && value(v.vod_id))
    .map((v) => ({
      id: value(v.vod_id),
      sourceId,
      title: clean(v.vod_name) || '未命名影片',
      poster: safeImage(value(v.vod_pic)),
      remarks: clean(v.vod_remarks),
      year: value(v.vod_year),
      area: clean(v.vod_area),
      category: clean(v.type_name),
      rating: rating(v),
      summary: clean(v.vod_content),
      actors: clean(v.vod_actor),
      director: clean(v.vod_director),
      language: clean(v.vod_lang),
      episodes: parseEpisodes(v),
    }));
  return { items, categories, pages: Math.max(1, Math.min(Number(d.pagecount) || 1, 10000)) };
}
export function safeImage(s: string): string {
  try {
    return httpURL(s.startsWith('//') ? 'https:' + s : s);
  } catch {
    return '';
  }
}
export function parseLive(text: string, base: string): Channel[] {
  const rows = text.replace(/^\uFEFF/, '').split(/\r?\n/);
  const channels: Channel[] = [];
  let name = '',
    logo = '',
    group = '默认分组',
    pending = false;
  for (const row of rows) {
    const line = row.trim();
    if (!line) continue;
    if (line.startsWith('#EXTINF:')) {
      const attr = (key: string) => line.match(new RegExp(key + '="([^"]*)"'))?.[1] ?? '';
      name = line.slice(line.indexOf(',') + 1).trim() || attr('tvg-name');
      logo = safeImage(attr('tvg-logo'));
      group = attr('group-title') || '默认分组';
      pending = true;
    } else if (!line.startsWith('#')) {
      if (line.includes(',#genre#')) {
        group = line.split(',')[0];
        pending = false;
        continue;
      }
      let url = line;
      if (!pending && line.includes(',')) {
        const at = line.indexOf(',');
        name = line.slice(0, at).trim();
        url = line.slice(at + 1).trim();
      }
      try {
        url = httpURL(new URL(url, base).href);
        channels.push({
          id: `${channels.length}|${url}`,
          name: name || `频道 ${channels.length + 1}`,
          url,
          logo,
          group,
        });
      } catch {
        /* UDP/RTSP require a native player. */
      }
      name = '';
      logo = '';
      pending = false;
    }
    if (channels.length >= 5000) break;
  }
  return channels;
}
export function importSources(text: string): Source[] {
  if (new TextEncoder().encode(text).length > 5 * 1024 * 1024) throw Error('订阅列表不能超过 5 MB');
  const raw = JSON.parse(text.replace(/^\uFEFF/, ''));
  if (!Array.isArray(raw) || raw.length > 200) throw Error('需要最多包含 200 项的 JSON 数组');
  return raw.map((v, i) => {
    if (!v || typeof v !== 'object') throw Error(`第 ${i + 1} 项不是订阅对象`);
    const url = downloadURL(value(v.api) || value(v.url));
    const type = value(v.kind ?? v.type).toLowerCase();
    let kind: 'cms' | 'live';
    if (['live', 'm3u', 'm3u8', 'txt'].includes(type)) kind = 'live';
    else if (['cms', 'vod', '1'].includes(type)) kind = 'cms';
    else if (!type) kind = /\.(m3u8?|txt)$/i.test(new URL(url).pathname) ? 'live' : 'cms';
    else throw Error(`第 ${i + 1} 项类型不支持，请使用 cms 或 live`);
    return {
      id: crypto.randomUUID(),
      name: clean(v.name) || new URL(url).hostname,
      url,
      kind,
      enabled: typeof v.enabled === 'boolean' ? v.enabled : true,
    };
  });
}
export function sourceKey(s: Source) {
  return `${s.kind}|${s.url.replace(/\/$/, '')}`;
}
export function recordKey(source: Source, movie: Movie) {
  return `${source.id}|${movie.id}`;
}
export function time(seconds: number): string {
  const n = Number.isFinite(seconds) ? Math.max(0, Math.floor(seconds)) : 0;
  return n >= 3600
    ? `${Math.floor(n / 3600)}:${String(Math.floor((n % 3600) / 60)).padStart(2, '0')}:${String(n % 60).padStart(2, '0')}`
    : `${Math.floor(n / 60)}:${String(n % 60).padStart(2, '0')}`;
}

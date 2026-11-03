import { openDB } from 'idb';
import { defaults, defaultSettings } from '../../shared/defaults';
import type { Library, Source, HistoryEntry, Settings } from '../../shared/types';
import { requestMode } from '../../shared/types';
import { httpURL } from './model';
export const initialLibrary = (): Library => ({
  sources: defaults.map((source) => ({ ...source, requestMode: requestMode(source.requestMode) })),
  history: [],
  searches: [],
  openings: {},
  settings: { ...defaultSettings },
});
const db = () =>
  openDB('hutv-web', 1, {
    upgrade(db) {
      db.createObjectStore('library');
    },
  });
export async function loadLibrary(): Promise<Library> {
  const data = await (await db()).get('library', 'current');
  return data ? validateLibrary(data) : initialLibrary();
}
let pending = Promise.resolve();
export function saveLibrary(data: Library): Promise<void> {
  const copy = structuredClone(data);
  pending = pending
    .catch(() => {})
    .then(async () => {
      await (await db()).put('library', copy, 'current');
    });
  return pending;
}
export function validateLibrary(raw: unknown): Library {
  if (!raw || typeof raw !== 'object') throw Error('备份格式不正确');
  const d = raw as Partial<Library>;
  if (!Array.isArray(d.sources) || d.sources.length > 200) throw Error('备份中缺少有效的订阅列表');
  const seen = new Set<string>();
  const sources: Source[] = d.sources
    .filter((s) => String(s?.kind) !== 'demo')
    .map((s) => {
      if (
        !s ||
        typeof s.id !== 'string' ||
        !s.id ||
        seen.has(s.id) ||
        typeof s.name !== 'string' ||
        !['cms', 'live'].includes(s.kind)
      )
        throw Error('备份订阅数据不正确');
      seen.add(s.id);
      return {
        ...s,
        name: s.name.slice(0, 100),
        url: httpURL(s.url),
        enabled: s.enabled !== false,
        requestMode: requestMode(s.requestMode),
      };
    });
  const settings: Settings = { ...defaultSettings, ...d.settings };
  if (![2, 4, 6, 8].includes(settings.concurrency)) settings.concurrency = 4;
  if (![0.5, 0.75, 1, 1.25, 1.5, 1.75, 2].includes(settings.rate)) settings.rate = 1;
  settings.autoNext = typeof settings.autoNext === 'boolean' ? settings.autoNext : true;
  settings.buffer = [15, 30, 60].includes(settings.buffer) ? settings.buffer : 30;
  const history: HistoryEntry[] = Array.isArray(d.history)
    ? d.history
        .filter(
          (h) =>
            h &&
            typeof h.id === 'string' &&
            h.movie &&
            h.source &&
            typeof h.episodeId === 'string' &&
            Number.isFinite(h.position) &&
            h.position >= 0 &&
            Number.isFinite(h.duration) &&
            h.duration >= 0 &&
            Number.isFinite(h.updatedAt) &&
            Array.isArray(h.movie.episodes) &&
            typeof h.source.id === 'string' &&
            typeof h.source.name === 'string' &&
            ['cms', 'live'].includes(h.source.kind) &&
            typeof h.movie.id === 'string' &&
            typeof h.movie.title === 'string' &&
            typeof h.movie.poster === 'string' &&
            typeof h.movie.summary === 'string' &&
            typeof h.movie.actors === 'string' &&
            typeof h.movie.director === 'string' &&
            typeof h.movie.language === 'string' &&
            h.movie.episodes.length <= 5000 &&
            h.movie.episodes.every((e) => {
              try {
                return (
                  typeof e.id === 'string' &&
                  typeof e.name === 'string' &&
                  typeof e.line === 'string' &&
                  Boolean(httpURL(e.url))
                );
              } catch {
                return false;
              }
            }) &&
            h.movie.episodes.some((e) => e.id === h.episodeId),
        )
        .slice(0, 200)
    : [];
  const openings = Object.fromEntries(
    Object.entries(d.openings ?? {}).filter(
      ([, v]) => typeof v === 'number' && Number.isFinite(v) && v >= 0 && v <= 86400,
    ),
  );
  return {
    sources,
    history,
    openings,
    searches: Array.isArray(d.searches)
      ? d.searches
          .filter((x) => typeof x === 'string')
          .map((x) => x.slice(0, 100))
          .slice(0, 30)
      : [],
    settings,
  };
}

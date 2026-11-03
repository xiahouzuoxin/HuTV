import { openDB } from 'idb';
import type { Movie } from '../../shared/types';
import {
  discoveryKey,
  discoveryLifetime,
  parseDiscovery,
  type DiscoveryKind,
} from '../../shared/discovery';
export interface DiscoveryRecord {
  updatedAt: number;
  items: Movie[];
}
const database = () =>
  openDB('hutv-discovery', 1, {
    upgrade(db) {
      db.createObjectStore('lists');
    },
  });
export function cacheFresh(record: DiscoveryRecord, now = Date.now()): boolean {
  const age = now - record.updatedAt;
  return age >= 0 && age < discoveryLifetime;
}
export async function readDiscovery(
  kind: DiscoveryKind,
  tag: string,
): Promise<DiscoveryRecord | undefined> {
  try {
    const record = await (await database()).get('lists', discoveryKey(kind, tag));
    if (
      record &&
      Number.isFinite(record.updatedAt) &&
      Array.isArray(record.items) &&
      record.items.every(
        (m: Movie) =>
          typeof m.id === 'string' && typeof m.title === 'string' && typeof m.poster === 'string',
      )
    )
      return record;
  } catch {
    /* Browsing works without persistent storage. */
  }
}
export async function requestDiscovery(
  kind: DiscoveryKind,
  tag: string,
  signal: AbortSignal,
  refresh = false,
): Promise<DiscoveryRecord> {
  const params = new URLSearchParams({ type: kind, tag, ...(refresh ? { refresh: '1' } : {}) });
  const response = await fetch('/api/discovery?' + params, {
    signal,
    cache: refresh ? 'no-store' : 'default',
  });
  const data = await response.json().catch(() => null);
  if (!response.ok) throw Error(data?.error || '暂时无法获取豆瓣推荐，请稍后重试');
  const record = { updatedAt: Date.now(), items: parseDiscovery(data, kind) };
  if (signal.aborted) throw new DOMException('已取消', 'AbortError');
  try {
    await (await database()).put('lists', record, discoveryKey(kind, tag));
  } catch {
    /* Do not fail a successful request when the disk cache is unavailable. */
  }
  return record;
}
export async function clearDiscoveryCache() {
  await (await database()).clear('lists');
}

import { useEffect, useState } from 'react';
import { RefreshCw, Search, ExternalLink } from 'lucide-react';
import type { Movie } from '../../shared/types';
import { discoveryTags, type DiscoveryKind } from '../../shared/discovery';
import { cacheFresh, readDiscovery, requestDiscovery } from '../lib/discovery';
import { Card } from './Card';
export function Discovery({ onSearch }: { onSearch: (title: string) => void }) {
  const [kind, setKind] = useState<DiscoveryKind>('movie'),
    [tag, setTag] = useState('热门'),
    [items, setItems] = useState<Movie[]>([]),
    [loading, setLoading] = useState(false),
    [error, setError] = useState(''),
    [refresh, setRefresh] = useState(0),
    [updatedAt, setUpdatedAt] = useState(0);
  useEffect(() => {
    const controller = new AbortController();
    setError('');
    setLoading(true);
    setItems([]);
    setUpdatedAt(0);
    void (async () => {
      const cached = await readDiscovery(kind, tag);
      if (controller.signal.aborted) return;
      if (cached) {
        setItems(cached.items);
        setUpdatedAt(cached.updatedAt);
        if (!refresh && cacheFresh(cached)) {
          setLoading(false);
          return;
        }
      }
      try {
        const record = await requestDiscovery(kind, tag, controller.signal, refresh > 0);
        if (controller.signal.aborted) return;
        setItems(record.items);
        setUpdatedAt(record.updatedAt);
      } catch (e) {
        if (!controller.signal.aborted)
          setError(e instanceof Error ? e.message : '暂时无法获取推荐');
      } finally {
        if (!controller.signal.aborted) setLoading(false);
      }
    })();
    return () => controller.abort();
  }, [kind, tag, refresh]);
  return (
    <div className="discovery-content">
      <div className="discovery-toolbar">
        <div className="segmented" aria-label="豆瓣推荐类型">
          <button
            className={kind === 'movie' ? 'active' : ''}
            aria-pressed={kind === 'movie'}
            onClick={() => {
              setKind('movie');
              setTag('热门');
              setRefresh(0);
            }}
          >
            电影
          </button>
          <button
            className={kind === 'tv' ? 'active' : ''}
            aria-pressed={kind === 'tv'}
            onClick={() => {
              setKind('tv');
              setTag('热门');
              setRefresh(0);
            }}
          >
            剧集
          </button>
        </div>
        <div className="discovery-status">
          {updatedAt > 0 && (
            <span>
              更新于{' '}
              {new Date(updatedAt).toLocaleDateString('zh-CN', {
                month: 'numeric',
                day: 'numeric',
              })}
            </span>
          )}
          <button
            className="icon-button"
            aria-label="刷新豆瓣推荐"
            disabled={loading}
            onClick={() => setRefresh((n) => n + 1)}
          >
            <RefreshCw size={17} className={loading ? 'spinning' : ''} />
          </button>
        </div>
      </div>
      <div className="tabs discovery-tags" aria-label="推荐分类">
        {discoveryTags[kind].map((t) => (
          <button
            key={t}
            className={tag === t ? 'active' : ''}
            aria-pressed={tag === t}
            onClick={() => {
              setTag(t);
              setRefresh(0);
            }}
          >
            {t}
          </button>
        ))}
      </div>
      <div className="discovery-caption">
        <Search size={14} />
        <span>点击影片，在你的点播订阅中搜索播放</span>
        <a href="https://movie.douban.com/" target="_blank" rel="noreferrer">
          来自豆瓣
          <ExternalLink size={12} />
        </a>
      </div>
      {error && (
        <div className="state-error" role="alert">
          <p>
            {error}
            {items.length > 0 ? '，当前保留上次的推荐。' : ''}
          </p>
          <button className="button ghost" onClick={() => setRefresh((n) => n + 1)}>
            重新尝试
          </button>
        </div>
      )}
      {loading && !items.length ? (
        <div className="skeleton-grid">
          {Array.from({ length: 6 }, (_, i) => (
            <div className="skeleton-card" key={i} />
          ))}
        </div>
      ) : items.length > 0 ? (
        <div className="movie-grid">
          {items.map((movie) => (
            <Card
              key={movie.id}
              movie={movie}
              onClick={() => onSearch(movie.title)}
              foot="搜索片源"
            />
          ))}
        </div>
      ) : !error ? (
        <div className="empty-state">
          <h3>这个分类暂时没有推荐</h3>
          <p>试试其他分类，或浏览你的点播订阅。</p>
        </div>
      ) : null}
    </div>
  );
}

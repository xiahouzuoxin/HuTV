import { clearDiscoveryCache } from './lib/discovery';
import { Discovery } from './components/Discovery';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import {
  Compass,
  Radio,
  History,
  Layers,
  Settings as SettingsIcon,
  Search,
  Plus,
  ArrowRight,
  ArrowLeft,
  ChevronDown,
  Play,
  RefreshCw,
  Film,
  ArrowUp,
  ArrowDown,
  Pencil,
  Trash2,
  Download,
  Upload,
  Check,
  ExternalLink,
  LoaderCircle,
  Globe,
  Menu,
} from 'lucide-react';
import type {
  Source,
  Movie,
  Episode,
  Library,
  SearchResult,
  Category,
  Channel,
  HistoryEntry,
} from '../shared/types';
import { defaults } from '../shared/defaults';
import { cms, concurrent, fetchText } from './lib/api';
import { loadLibrary, saveLibrary, initialLibrary, validateLibrary } from './lib/store';
import { parseLive, recordKey, sourceKey, time } from './lib/model';
import { Card } from './components/Card';
import { Player } from './components/Player';
import { SourceEditor } from './components/SourceEditor';

type View = 'library' | 'search' | 'live' | 'history' | 'sources' | 'settings';
const nav: { id: View; label: string; icon: typeof Compass }[] = [
  { id: 'library', label: '发现片库', icon: Compass },
  { id: 'live', label: '在线直播', icon: Radio },
  { id: 'history', label: '观看历史', icon: History },
  { id: 'sources', label: '我的订阅', icon: Layers },
];
interface Detail {
  movie: Movie;
  source: Source;
  episode?: Episode;
  start: number;
  live?: boolean;
}
const message = (e: unknown) => (e instanceof Error ? e.message : '请求失败，请稍后重试');
function Empty({
  icon = <Film />,
  title,
  description,
  children,
}: {
  icon?: ReactNode;
  title: string;
  description: string;
  children?: ReactNode;
}) {
  return (
    <div className="empty-state">
      <div className="empty-icon">{icon}</div>
      <h3>{title}</h3>
      <p>{description}</p>
      {children}
    </div>
  );
}
function StateError({ text, retry }: { text: string; retry?: () => void }) {
  return (
    <div className="state-error" role="alert">
      <p>{text}</p>
      {retry && (
        <button className="button ghost" onClick={retry}>
          <RefreshCw size={15} />
          重新尝试
        </button>
      )}
    </div>
  );
}
export default function App() {
  const [library, setLibrary] = useState<Library>(initialLibrary),
    [hydrated, setHydrated] = useState(false),
    [canPersist, setCanPersist] = useState(false),
    [storageError, setStorageError] = useState('');
  const [view, setView] = useState<View>('library'),
    [query, setQuery] = useState(''),
    [keyword, setKeyword] = useState(''),
    [searchRun, setSearchRun] = useState(0),
    [results, setResults] = useState<SearchResult[]>([]),
    [resultSource, setResultSource] = useState('all'),
    [searching, setSearching] = useState(false);
  const [selectedSource, setSelectedSource] = useState('douban'),
    [category, setCategory] = useState(''),
    [categories, setCategories] = useState<Category[]>([]),
    [movies, setMovies] = useState<Movie[]>([]),
    [page, setPage] = useState(1),
    [pages, setPages] = useState(1),
    [loading, setLoading] = useState(false),
    [loadError, setLoadError] = useState(''),
    [browseRun, setBrowseRun] = useState(0);
  const [detail, setDetail] = useState<Detail | null>(null),
    [detailLoading, setDetailLoading] = useState(false),
    [detailError, setDetailError] = useState(''),
    [line, setLine] = useState('');
  const detailController = useRef<AbortController | null>(null),
    searchController = useRef<AbortController | null>(null),
    stateRef = useRef(library);
  stateRef.current = library;
  const [editor, setEditor] = useState<Source | null | undefined>(undefined),
    [toast, setToast] = useState(''),
    [sourceKind, setSourceKind] = useState<'cms' | 'live'>('cms'),
    [dragged, setDragged] = useState<string | null>(null),
    [mobileNav, setMobileNav] = useState(false);
  const [liveSource, setLiveSource] = useState('live-0'),
    [channels, setChannels] = useState<Channel[]>([]),
    [liveLoading, setLiveLoading] = useState(false),
    [liveError, setLiveError] = useState(''),
    [liveQuery, setLiveQuery] = useState(''),
    [liveGroup, setLiveGroup] = useState('all'),
    [liveRun, setLiveRun] = useState(0);
  const source = library.sources.find((s) => s.id === selectedSource),
    enabledCMS = library.sources.filter((s) => s.enabled && s.kind !== 'live'),
    enabledLive = library.sources.filter((s) => s.enabled && s.kind === 'live');
  useEffect(() => {
    let alive = true;
    loadLibrary()
      .then((data) => {
        if (alive) {
          setLibrary(data);
          setCanPersist(true);
        }
      })
      .catch(() => {
        if (alive) setStorageError('浏览器无法读取本地数据。当前仍可使用，记录可能无法保留。');
      })
      .finally(() => {
        if (alive) setHydrated(true);
      });
    return () => {
      alive = false;
    };
  }, []);
  useEffect(() => {
    if (hydrated && canPersist)
      saveLibrary(library).catch(() =>
        setStorageError('本地存储写入失败，请导出数据备份并检查浏览器可用空间。'),
      );
  }, [library, hydrated, canPersist]);
  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(''), 3500);
    return () => clearTimeout(t);
  }, [toast]);
  useEffect(() => {
    if (selectedSource !== 'douban' && !enabledCMS.some((s) => s.id === selectedSource)) {
      setSelectedSource('douban');
      setCategory('');
      setPage(1);
    }
  }, [library.sources]);
  useEffect(() => {
    if (enabledLive.length && !enabledLive.some((s) => s.id === liveSource))
      setLiveSource(enabledLive[0].id);
  }, [library.sources]);
  const navigate = (v: View) => {
    detailController.current?.abort();
    setDetail(null);
    setDetailError('');
    setDetailLoading(false);
    setView(v);
    setMobileNav(false);
    if (v !== 'search') {
      searchController.current?.abort();
      setSearching(false);
    }
    window.scrollTo({ top: 0 });
  };
  const notify = (s: string) => setToast(s);
  useEffect(() => {
    if (!hydrated || view !== 'library' || !source?.enabled) return;
    const c = new AbortController();
    setLoading(true);
    setLoadError('');
    setMovies([]);
    setCategories([]);
    Promise.all([
      cms(source, 'browse', { pg: String(page), ...(category ? { t: category } : {}) }, c.signal),
      cms(source, 'categories', {}, c.signal).catch(() => ({ categories: [] })),
    ])
      .then(([data, cat]) => {
        if (c.signal.aborted) return;
        setMovies(data.items);
        setPages(data.pages);
        setCategories(cat.categories);
      })
      .catch((e) => {
        if (!c.signal.aborted) setLoadError(message(e));
      })
      .finally(() => {
        if (!c.signal.aborted) setLoading(false);
      });
    return () => c.abort();
  }, [view, selectedSource, page, category, browseRun, hydrated, source?.url, source?.enabled]);
  useEffect(() => {
    if (!keyword || view !== 'search' || !hydrated) return;
    const c = new AbortController();
    searchController.current?.abort();
    searchController.current = c;
    setSearching(true);
    setResultSource('all');
    const sources = library.sources.filter((s) => s.enabled && s.kind !== 'live');
    setResults(sources.map((source) => ({ source, items: [], status: 'loading' })));
    concurrent(sources, library.settings.concurrency, c.signal, async (source) => {
      try {
        const response = await cms(source, 'search', { wd: keyword }, c.signal);
        if (!c.signal.aborted)
          setResults((old) =>
            old.map((r) =>
              r.source.id === source.id ? { source, items: response.items, status: 'done' } : r,
            ),
          );
      } catch (e) {
        if (!c.signal.aborted)
          setResults((old) =>
            old.map((r) =>
              r.source.id === source.id
                ? { source, items: [], status: 'error', error: message(e) }
                : r,
            ),
          );
      }
    }).finally(() => {
      if (!c.signal.aborted) setSearching(false);
    });
    return () => c.abort();
  }, [keyword, searchRun, view, hydrated]);
  const search = (text: string) => {
    const k = text.trim().slice(0, 100);
    if (!k) return;
    navigate('search');
    setQuery(k);
    setKeyword(k);
    setSearchRun((n) => n + 1);
    setLibrary((old) => ({
      ...old,
      searches: [k, ...old.searches.filter((s) => s !== k)].slice(0, 30),
    }));
  };
  useEffect(() => {
    if (view !== 'live' || !hydrated) return;
    const s = library.sources.find((s) => s.id === liveSource && s.enabled);
    if (!s) return;
    const c = new AbortController();
    setLiveLoading(true);
    setLiveError('');
    setChannels([]);
    setLiveGroup('all');
    fetchText(s.url, c.signal, s.requestMode)
      .then((text) => {
        if (!c.signal.aborted) {
          const rows = parseLive(text, s.url);
          if (!rows.length) throw Error('此列表没有浏览器可用的 HTTP(S) 频道');
          setChannels(rows);
        }
      })
      .catch((e) => {
        if (!c.signal.aborted) setLiveError(message(e));
      })
      .finally(() => {
        if (!c.signal.aborted) setLiveLoading(false);
      });
    return () => c.abort();
  }, [view, liveSource, liveRun, hydrated, library.sources]);
  const openMovie = async (movie: Movie, s: Source, entry?: HistoryEntry) => {
    s = stateRef.current.sources.find((source) => source.id === s.id) ?? s;
    detailController.current?.abort();
    const c = new AbortController();
    detailController.current = c;
    setDetail({ movie, source: s, start: entry?.position ?? 0 });
    setLine('');
    setDetailError('');
    setDetailLoading(true);
    window.scrollTo({ top: 0 });
    try {
      const response = await cms(s, 'detail', { ids: movie.id }, c.signal);
      if (c.signal.aborted) return;
      const fresh = response.items[0];
      if (!fresh) throw Error('源未返回影片详情');
      const ep = entry
        ? fresh.episodes.find((e) => e.id === entry.episodeId) ||
          fresh.episodes.find(
            (e) => e.name === movie.episodes.find((e) => e.id === entry.episodeId)?.name,
          )
        : undefined;
      setDetail({ movie: fresh, source: s, start: entry?.position ?? 0, episode: ep });
      setLine(ep?.line ?? fresh.episodes[0]?.line ?? '');
    } catch (e) {
      if (!c.signal.aborted) setDetailError(message(e));
    } finally {
      if (!c.signal.aborted) setDetailLoading(false);
    }
  };
  const openingKey = detail ? recordKey(detail.source, detail.movie) : '';
  const chooseEpisode = (episode: Episode, start = 0) => {
    setDetail((old) =>
      old
        ? {
            ...old,
            episode,
            start: Math.max(
              start,
              stateRef.current.openings[recordKey(old.source, old.movie)] || 0,
            ),
          }
        : old,
    );
    setLine(episode.line);
  };
  const recordProgress = (active: Detail, position: number, duration: number) => {
    if (!active.episode) return;
    const id = recordKey(active.source, active.movie);
    const entry: HistoryEntry = {
      id,
      movie: active.movie,
      source: active.source,
      episodeId: active.episode.id,
      position,
      duration,
      updatedAt: Date.now(),
      live: active.live,
    };
    setLibrary((old) => ({
      ...old,
      history: [entry, ...old.history.filter((h) => h.id !== id)].slice(0, 200),
    }));
  };
  const playChannel = (channel: Channel, s: Source) => {
    const movie: Movie = {
      id: channel.url,
      sourceId: s.id,
      title: channel.name,
      poster: channel.logo,
      remarks: '直播',
      year: '',
      area: '',
      category: channel.group,
      summary: '此频道由你的直播订阅提供。直播内容与可用性取决于源服务器。',
      actors: '',
      director: '',
      language: '',
      episodes: [{ id: channel.id, name: channel.name, url: channel.url, line: channel.group }],
    };
    setDetail({ movie, source: s, episode: movie.episodes[0], start: 0, live: true });
    setDetailError('');
    setDetailLoading(false);
  };
  const exportData = () => {
    const url = URL.createObjectURL(
      new Blob([JSON.stringify(stateRef.current, null, 2)], { type: 'application/json' }),
    );
    const a = document.createElement('a');
    a.href = url;
    a.download = 'HuTV-Web-backup.json';
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };
  const reorder = (from: string, to: string) => {
    setLibrary((old) => {
      const list = [...old.sources];
      const a = list.findIndex((s) => s.id === from),
        b = list.findIndex((s) => s.id === to);
      if (a < 0 || b < 0) return old;
      const [item] = list.splice(a, 1);
      list.splice(b, 0, item);
      return { ...old, sources: list };
    });
  };
  const sortedResults = [...results].sort((a, b) => b.items.length - a.items.length),
    selectedResults =
      resultSource === 'all'
        ? sortedResults
        : sortedResults.filter((r) => r.source.id === resultSource);
  const totalResults = results.reduce((n, r) => n + r.items.length, 0),
    validSources = results.filter((r) => r.items.length).length;
  const sectionHeading = (
    eyebrow: string,
    title: string,
    description: string,
    action?: ReactNode,
  ) => (
    <div className="page-heading">
      <div>
        <span className="eyebrow">{eyebrow}</span>
        <h1>{title}</h1>
        <p>{description}</p>
      </div>
      {action}
    </div>
  );
  return (
    <div className="app-shell">
      <aside className={'sidebar ' + (mobileNav ? 'open' : '')}>
        <a
          href="#"
          className="brand"
          onClick={(e) => {
            e.preventDefault();
            navigate('library');
          }}
        >
          <img src="/app-icon.png" alt="" />
          <span>
            HuTV<small>WEB PLAYER</small>
          </span>
        </a>
        <div className="sidebar-label">我的观影空间</div>
        <nav>
          {nav.map(({ id, label, icon: Icon }) => (
            <button
              key={id}
              className={view === id || (view === 'search' && id === 'library') ? 'active' : ''}
              onClick={() => navigate(id)}
            >
              <Icon size={19} />
              <span>{label}</span>
              {id === 'sources' && <small>{library.sources.length}</small>}
            </button>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="local-note">
            <span className="online-dot" />
            <div>
              只属于你的片库<small>数据保存在当前浏览器</small>
            </div>
          </div>
          <button
            className={view === 'settings' ? 'nav-settings active' : 'nav-settings'}
            onClick={() => navigate('settings')}
          >
            <SettingsIcon size={19} />
            偏好设置
          </button>
          <p>简单连接，自由观看。</p>
          <span className="version">HuTV Web · 0.1</span>
        </div>
      </aside>
      {mobileNav && <div className="nav-shade" onClick={() => setMobileNav(false)} />}
      <main className="main">
        <header className="topbar">
          <button
            className="icon-button mobile-menu"
            aria-label="打开导航"
            onClick={() => setMobileNav(!mobileNav)}
          >
            <Menu size={22} />
          </button>
          <div className="breadcrumb">
            我的空间 <span>/</span>{' '}
            {view === 'search' ? '搜索结果' : (nav.find((n) => n.id === view)?.label ?? '偏好设置')}
          </div>
          <form
            className="global-search"
            onSubmit={(e) => {
              e.preventDefault();
              search(query);
            }}
          >
            <Search size={18} />
            <input
              aria-label="搜索影片"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="搜索电影、剧集，发现下一部好片"
            />
            <kbd>↵</kbd>
          </form>
          <button className="button compact add-top" onClick={() => setEditor(null)}>
            <Plus size={16} />
            添加订阅
          </button>
        </header>
        {storageError && (
          <div className="storage-notice" role="alert">
            {storageError}
            <button onClick={exportData}>导出备份</button>
          </div>
        )}
        <div className="page-content">
          {!hydrated ? (
            <div className="loading-state">
              <LoaderCircle className="spinning" />
              正在打开你的片库…
            </div>
          ) : detail ? (
            <>
              <button
                className="back-button"
                onClick={() => {
                  detailController.current?.abort();
                  setDetail(null);
                  setDetailLoading(false);
                  setDetailError('');
                }}
              >
                <ArrowLeft size={17} />
                返回
                {view === 'history'
                  ? '观看历史'
                  : view === 'search'
                    ? '搜索结果'
                    : view === 'live'
                      ? '直播列表'
                      : '片库'}
              </button>
              {detail.episode && (
                <Player
                  movie={detail.movie}
                  episode={detail.episode}
                  settings={{
                    ...library.settings,
                    autoNext: !detail.live && library.settings.autoNext,
                  }}
                  start={detail.start}
                  opening={library.openings[openingKey] || 0}
                  onProgress={(position, duration) => recordProgress(detail, position, duration)}
                  onEpisode={(e) => chooseEpisode(e)}
                  onOpening={(v) => {
                    if (detail.live) return;
                    setLibrary((old) => ({
                      ...old,
                      openings: { ...old.openings, [openingKey]: Math.floor(v) },
                    }));
                    notify(v ? '已记录起播位置 ' + time(v) : '已清除起播位置');
                  }}
                  onReload={async () => {
                    if (detail.live) return;
                    const fresh = (await cms(detail.source, 'detail', { ids: detail.movie.id }))
                      .items[0];
                    const episode = fresh?.episodes.find(
                      (e) => e.line === detail.episode!.line && e.name === detail.episode!.name,
                    );
                    if (!episode) throw Error('未找到当前集数，请尝试其他线路');
                    setDetail((old) =>
                      old
                        ? {
                            ...old,
                            movie: fresh,
                            episode,
                            start:
                              stateRef.current.history.find((h) => h.id === openingKey)?.position ??
                              0,
                          }
                        : old,
                    );
                  }}
                />
              )}
              {detailLoading ? (
                <div className="loading-state">
                  <LoaderCircle className="spinning" />
                  正在读取影片详情…
                </div>
              ) : detailError ? (
                <StateError
                  text={detailError}
                  retry={() => openMovie(detail.movie, detail.source)}
                />
              ) : (
                <>
                  <section className="detail-card">
                    <img
                      className="detail-poster"
                      src={detail.movie.poster || '/app-icon.png'}
                      alt={detail.movie.title}
                      referrerPolicy="no-referrer"
                      onError={(e) => {
                        e.currentTarget.src = '/app-icon.png';
                      }}
                    />
                    <div className="detail-copy">
                      <span className="eyebrow">{detail.source.name}</span>
                      <h1>{detail.movie.title}</h1>
                      <div className="detail-meta">
                        {[
                          detail.movie.year,
                          detail.movie.area,
                          detail.movie.category,
                          detail.movie.language,
                        ]
                          .filter(Boolean)
                          .join(' · ')}
                        {detail.movie.rating && (
                          <span className="detail-rating">
                            {detail.movie.rating.kind === 'douban'
                              ? '豆瓣评分（源提供）'
                              : '源评分'}{' '}
                            {detail.movie.rating.value.toFixed(1)}
                          </span>
                        )}
                      </div>
                      {detail.movie.director && (
                        <p className="credits">
                          <span>导演</span>
                          {detail.movie.director}
                        </p>
                      )}
                      {detail.movie.actors && (
                        <p className="credits actors">
                          <span>演员</span>
                          {detail.movie.actors}
                        </p>
                      )}
                      <p className="summary">
                        {detail.movie.summary || '此订阅源未提供内容介绍。'}
                      </p>
                      {!detail.episode && detail.movie.episodes[0] && (
                        <button
                          className="button primary"
                          onClick={() => chooseEpisode(detail.movie.episodes[0])}
                        >
                          <Play size={17} fill="currentColor" />
                          开始观看
                        </button>
                      )}
                      {!detail.live && (
                        <button
                          className="button ghost same-name"
                          onClick={() => search(detail.movie.title)}
                        >
                          <Search size={16} />
                          搜索其他源
                        </button>
                      )}
                    </div>
                  </section>
                  {!detail.live && (
                    <section className="episode-section">
                      <div className="section-title">
                        <h2>
                          选集播放{' '}
                          <small>
                            {detail.movie.episodes.filter((e) => e.line === line).length} 集
                          </small>
                        </h2>
                        <span className="muted">点击集数即可播放</span>
                      </div>
                      <div className="tabs">
                        {[...new Set(detail.movie.episodes.map((e) => e.line))].map((l) => (
                          <button
                            key={l}
                            className={line === l ? 'active' : ''}
                            onClick={() => setLine(l)}
                          >
                            {l}
                          </button>
                        ))}
                      </div>
                      {!detail.movie.episodes.length ? (
                        <Empty
                          title="没有可直接播放的地址"
                          description="此资源可能需要额外解析，请尝试其他订阅源。"
                        />
                      ) : (
                        <div className="episode-grid">
                          {detail.movie.episodes
                            .filter((e) => e.line === line)
                            .map((e) => (
                              <button
                                className={e.id === detail.episode?.id ? 'active' : ''}
                                key={e.id}
                                onClick={() => chooseEpisode(e)}
                              >
                                {e.name}
                              </button>
                            ))}
                        </div>
                      )}
                    </section>
                  )}
                </>
              )}
            </>
          ) : view === 'library' ? (
            <>
              {sectionHeading(
                'A LITTLE TIME FOR YOURSELF',
                '今天，想看点什么？',
                '从你的订阅中，找到下一段好故事。',
              )}
              {!!library.history.length && (
                <section className="continue-section">
                  <div className="section-title">
                    <h2>接着上次的故事</h2>
                    <button className="text-button" onClick={() => navigate('history')}>
                      全部历史
                      <ArrowRight size={15} />
                    </button>
                  </div>
                  <div className="continue-list">
                    {library.history.slice(0, 3).map((h) => (
                      <button
                        key={h.id}
                        className="continue-card"
                        onClick={() =>
                          h.live
                            ? playChannel(
                                {
                                  id: h.episodeId,
                                  name: h.movie.title,
                                  url: h.movie.episodes[0].url,
                                  logo: h.movie.poster,
                                  group: '直播',
                                },
                                h.source,
                              )
                            : openMovie(h.movie, h.source, h)
                        }
                      >
                        <img
                          src={h.movie.poster || '/app-icon.png'}
                          alt=""
                          referrerPolicy="no-referrer"
                          onError={(e) => {
                            e.currentTarget.src = '/app-icon.png';
                          }}
                        />
                        <div>
                          <strong>{h.movie.title}</strong>
                          <small>
                            {h.live ? '重新连接直播' : `继续观看 · ${time(h.position)}`}
                          </small>
                          <span className="mini-progress">
                            <i
                              style={{
                                width: `${Math.min(100, (h.position / (h.duration || 1)) * 100)}%`,
                              }}
                            />
                          </span>
                        </div>
                        <Play size={18} />
                      </button>
                    ))}
                  </div>
                </section>
              )}
              <section className="library-section">
                <div className="section-title">
                  <div className="title-with-icon">
                    <span className="section-icon">
                      <Compass size={19} />
                    </span>
                    <h2>发现片库</h2>
                  </div>
                  {selectedSource !== 'douban' && (
                    <button
                      className="icon-button"
                      aria-label="刷新片库"
                      onClick={() => setBrowseRun((x) => x + 1)}
                      disabled={loading}
                    >
                      <RefreshCw size={17} className={loading ? 'spinning' : ''} />
                    </button>
                  )}
                </div>
                <div className="library-toolbar">
                  <div className="source-select">
                    <Layers size={16} />
                    <select
                      aria-label="选择点播源"
                      value={selectedSource}
                      onChange={(e) => {
                        setSelectedSource(e.target.value);
                        setPage(1);
                        setCategory('');
                      }}
                    >
                      <option value="douban">豆瓣推荐</option>
                      {enabledCMS.map((s) => (
                        <option key={s.id} value={s.id}>
                          {s.name}
                        </option>
                      ))}
                    </select>
                    <ChevronDown size={14} />
                  </div>
                  {selectedSource !== 'douban' && (
                    <div className="tabs category-tabs">
                      <button
                        className={!category ? 'active' : ''}
                        onClick={() => {
                          setCategory('');
                          setPage(1);
                        }}
                      >
                        全部
                      </button>
                      {categories
                        .filter((c) => c.id !== 'all')
                        .map((c) => (
                          <button
                            key={c.id}
                            className={category === c.id ? 'active' : ''}
                            onClick={() => {
                              setCategory(c.id);
                              setPage(1);
                            }}
                          >
                            {c.name}
                          </button>
                        ))}
                    </div>
                  )}
                </div>
                {selectedSource === 'douban' ? (
                  <Discovery onSearch={search} />
                ) : loading ? (
                  <div className="skeleton-grid">
                    {Array.from({ length: 6 }, (_, i) => (
                      <div key={i} className="skeleton-card" />
                    ))}
                  </div>
                ) : loadError ? (
                  <StateError text={loadError} retry={() => setBrowseRun((n) => n + 1)} />
                ) : !enabledCMS.length ? (
                  <Empty
                    title="先添加一个点播订阅"
                    description="连接 CMS JSON 接口，即可浏览和搜索影片。"
                  >
                    <button className="button primary" onClick={() => setEditor(null)}>
                      <Plus size={16} />
                      添加订阅
                    </button>
                  </Empty>
                ) : !movies.length ? (
                  <Empty title="这个分类还没有影片" description="试试其他分类或切换订阅源。" />
                ) : (
                  <div className="movie-grid">
                    {movies.map((m) => (
                      <Card key={m.id} movie={m} onClick={() => source && openMovie(m, source)} />
                    ))}
                  </div>
                )}
                {selectedSource !== 'douban' && pages > 1 && (
                  <div className="pagination">
                    <button
                      className="button ghost"
                      disabled={page <= 1 || loading}
                      onClick={() => setPage((p) => p - 1)}
                    >
                      上一页
                    </button>
                    <span>
                      {page} / {pages}
                    </span>
                    <button
                      className="button ghost"
                      disabled={page >= pages || loading}
                      onClick={() => setPage((p) => p + 1)}
                    >
                      下一页
                    </button>
                  </div>
                )}
              </section>
              {library.searches.length > 0 && (
                <section className="recent-searches">
                  <span>最近搜索</span>
                  {library.searches.slice(0, 6).map((s) => (
                    <button key={s} onClick={() => search(s)}>
                      {s}
                      <ArrowRight size={12} />
                    </button>
                  ))}
                </section>
              )}
            </>
          ) : view === 'search' ? (
            <>
              {sectionHeading(
                'FIND YOUR NEXT FAVORITE',
                `“${keyword}” 的搜索结果`,
                searching
                  ? '正在为你搜索各个订阅源…'
                  : `${totalResults} 个结果，来自 ${validSources} 个订阅源`,
                searching ? (
                  <button
                    className="button ghost"
                    onClick={() => {
                      searchController.current?.abort();
                      setSearching(false);
                      setResults((old) =>
                        old.map((r) =>
                          r.status === 'loading'
                            ? { ...r, status: 'error', error: '已取消搜索' }
                            : r,
                        ),
                      );
                    }}
                  >
                    停止搜索
                  </button>
                ) : (
                  <button className="button ghost" onClick={() => setSearchRun((n) => n + 1)}>
                    <RefreshCw size={15} />
                    重新搜索
                  </button>
                ),
              )}
              <div className="search-layout">
                <aside className="result-sources">
                  <button
                    className={resultSource === 'all' ? 'active' : ''}
                    onClick={() => setResultSource('all')}
                  >
                    全部资源<span>{totalResults}</span>
                  </button>
                  {sortedResults.map((r) => (
                    <button
                      className={resultSource === r.source.id ? 'active' : ''}
                      key={r.source.id}
                      onClick={() => setResultSource(r.source.id)}
                    >
                      <span>{r.source.name}</span>
                      {r.status === 'loading' ? (
                        <LoaderCircle size={14} className="spinning" />
                      ) : (
                        <small>{r.status === 'error' ? '—' : r.items.length}</small>
                      )}
                    </button>
                  ))}
                </aside>
                <div className="search-results">
                  {selectedResults.map((r) => (
                    <section key={r.source.id}>
                      <div className="section-title">
                        <h2>
                          {r.source.name}
                          <small>{r.items.length ? `${r.items.length} 个结果` : ''}</small>
                        </h2>
                        {r.status === 'loading' && <LoaderCircle size={17} className="spinning" />}
                      </div>
                      {r.status === 'error' ? (
                        <p className="source-error">{r.error}</p>
                      ) : r.items.length ? (
                        <div className="movie-grid">
                          {r.items.map((m) => (
                            <Card key={m.id} movie={m} onClick={() => openMovie(m, r.source)} />
                          ))}
                        </div>
                      ) : r.status === 'done' ? (
                        <p className="source-error">没有找到匹配结果</p>
                      ) : (
                        <div className="loading-line" />
                      )}
                    </section>
                  ))}
                  {!results.length && (
                    <Empty title="还没有可搜索的订阅" description="请添加或启用点播订阅后重试。" />
                  )}
                </div>
              </div>
            </>
          ) : view === 'live' ? (
            <>
              {sectionHeading(
                'A WINDOW TO THE WORLD',
                '此刻，正在直播',
                '打开一个频道，看看世界的另一面。',
                <button
                  className="button ghost"
                  onClick={() => setLiveRun((n) => n + 1)}
                  disabled={liveLoading}
                >
                  <RefreshCw size={15} />
                  刷新频道
                </button>,
              )}
              <div className="live-toolbar">
                <select
                  aria-label="选择直播源"
                  value={liveSource}
                  onChange={(e) => setLiveSource(e.target.value)}
                >
                  {enabledLive.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.name}
                    </option>
                  ))}
                </select>
                <div className="input-icon">
                  <Search size={16} />
                  <input
                    aria-label="搜索频道"
                    value={liveQuery}
                    onChange={(e) => setLiveQuery(e.target.value)}
                    placeholder="搜索频道名称"
                  />
                </div>
              </div>
              {!enabledLive.length ? (
                <Empty
                  icon={<Radio />}
                  title="连接你的直播列表"
                  description="添加 M3U 或 TXT 订阅，频道就会出现在这里。"
                >
                  <button className="button primary" onClick={() => setEditor(null)}>
                    添加直播订阅
                  </button>
                </Empty>
              ) : liveLoading ? (
                <div className="loading-state">
                  <LoaderCircle className="spinning" />
                  正在读取频道列表…
                </div>
              ) : liveError ? (
                <StateError text={liveError} retry={() => setLiveRun((n) => n + 1)} />
              ) : (
                <>
                  <div className="tabs live-groups">
                    <button
                      className={liveGroup === 'all' ? 'active' : ''}
                      onClick={() => setLiveGroup('all')}
                    >
                      全部频道
                    </button>
                    {[...new Set(channels.map((c) => c.group))].map((g) => (
                      <button
                        key={g}
                        className={g === liveGroup ? 'active' : ''}
                        onClick={() => setLiveGroup(g)}
                      >
                        {g}
                      </button>
                    ))}
                  </div>
                  <div className="channel-grid">
                    {channels
                      .filter(
                        (c) =>
                          (liveGroup === 'all' || c.group === liveGroup) &&
                          c.name.toLowerCase().includes(liveQuery.toLowerCase()),
                      )
                      .map((c) => (
                        <button
                          className="channel-card"
                          key={c.id}
                          onClick={() => {
                            const s = library.sources.find((s) => s.id === liveSource);
                            if (s) playChannel(c, s);
                          }}
                        >
                          {c.logo ? (
                            <img
                              src={c.logo}
                              alt=""
                              referrerPolicy="no-referrer"
                              onError={(e) => {
                                e.currentTarget.style.visibility = 'hidden';
                              }}
                            />
                          ) : (
                            <Radio size={28} />
                          )}
                          <strong>{c.name}</strong>
                          <span>{c.group}</span>
                          <Play size={16} className="channel-play" />
                        </button>
                      ))}
                  </div>
                </>
              )}
            </>
          ) : view === 'history' ? (
            <>
              {sectionHeading(
                'PICK UP WHERE YOU LEFT OFF',
                '故事，还没看完',
                '每一次暂停，都为下一次相遇留个位置。',
                library.history.length ? (
                  <button
                    className="button ghost"
                    onClick={() => {
                      if (confirm('清空所有观看记录？'))
                        setLibrary((old) => ({ ...old, history: [] }));
                    }}
                  >
                    <Trash2 size={15} />
                    清空历史
                  </button>
                ) : undefined,
              )}
              {!library.history.length ? (
                <Empty
                  icon={<History />}
                  title="你的故事，从第一部开始"
                  description="播放影片后，观看进度会自动保存在这里。"
                >
                  <button className="button primary" onClick={() => navigate('library')}>
                    去发现片库
                    <ArrowRight size={16} />
                  </button>
                </Empty>
              ) : (
                <div className="movie-grid history-grid">
                  {library.history.map((h) => (
                    <Card
                      key={h.id}
                      movie={h.movie}
                      foot={
                        h.live
                          ? '直播 · ' + h.source.name
                          : `${time(h.position)} / ${time(h.duration)} · ${h.source.name}`
                      }
                      onClick={() =>
                        h.live
                          ? playChannel(
                              {
                                id: h.episodeId,
                                name: h.movie.title,
                                url: h.movie.episodes[0].url,
                                logo: h.movie.poster,
                                group: '直播',
                              },
                              h.source,
                            )
                          : openMovie(h.movie, h.source, h)
                      }
                      onRemove={() =>
                        setLibrary((old) => ({
                          ...old,
                          history: old.history.filter((x) => x.id !== h.id),
                        }))
                      }
                    />
                  ))}
                </div>
              )}
            </>
          ) : view === 'sources' ? (
            <>
              {sectionHeading(
                'CONNECTED TO WHAT YOU LOVE',
                '我的订阅',
                '把喜欢的内容，放在同一个地方。',
                <button className="button primary" onClick={() => setEditor(null)}>
                  <Plus size={17} />
                  添加订阅
                </button>,
              )}
              <div className="section-title">
                <div className="segmented">
                  <button
                    className={sourceKind === 'cms' ? 'active' : ''}
                    onClick={() => setSourceKind('cms')}
                  >
                    点播订阅{' '}
                    <small>{library.sources.filter((s) => s.kind !== 'live').length}</small>
                  </button>
                  <button
                    className={sourceKind === 'live' ? 'active' : ''}
                    onClick={() => setSourceKind('live')}
                  >
                    直播订阅{' '}
                    <small>{library.sources.filter((s) => s.kind === 'live').length}</small>
                  </button>
                </div>
                <span className="muted desktop-only">拖动卡片调整顺序</span>
              </div>
              <div className="source-grid">
                {library.sources
                  .filter((s) => (sourceKind === 'live' ? s.kind === 'live' : s.kind !== 'live'))
                  .map((s, i, group) => (
                    <article
                      key={s.id}
                      className={'source-card ' + (!s.enabled ? 'disabled' : '')}
                      draggable
                      onDragStart={() => setDragged(s.id)}
                      onDragOver={(e) => e.preventDefault()}
                      onDrop={() => {
                        if (dragged) reorder(dragged, s.id);
                        setDragged(null);
                      }}
                    >
                      <div className="source-card-heading">
                        <span className="source-avatar">
                          {s.kind === 'live' ? <Radio size={22} /> : <Layers size={22} />}
                        </span>
                        <div>
                          <h3>{s.name}</h3>
                          <span>{s.kind === 'cms' ? 'CMS JSON · 点播' : 'M3U / TXT · 直播'}</span>
                        </div>
                        <label className="switch">
                          <input
                            type="checkbox"
                            aria-label={'启用 ' + s.name}
                            checked={s.enabled}
                            onChange={(e) =>
                              setLibrary((old) => ({
                                ...old,
                                sources: old.sources.map((x) =>
                                  x.id === s.id ? { ...x, enabled: e.target.checked } : x,
                                ),
                              }))
                            }
                          />
                          <i />
                        </label>
                      </div>
                      <p className="source-address" title={s.url}>
                        {s.url}
                      </p>
                      <div className="source-card-actions">
                        <button
                          onClick={() => {
                            if (s.kind === 'live') {
                              setLiveSource(s.id);
                              navigate('live');
                            } else {
                              setSelectedSource(s.id);
                              setCategory('');
                              setPage(1);
                              navigate('library');
                            }
                          }}
                          disabled={!s.enabled}
                        >
                          浏览内容
                          <ArrowRight size={14} />
                        </button>
                        <span />
                        <button
                          className="icon-button"
                          aria-label={'上移 ' + s.name}
                          disabled={!i}
                          onClick={() => reorder(s.id, group[i - 1].id)}
                        >
                          <ArrowUp size={15} />
                        </button>
                        <button
                          className="icon-button"
                          aria-label={'下移 ' + s.name}
                          disabled={i === group.length - 1}
                          onClick={() => reorder(s.id, group[i + 1].id)}
                        >
                          <ArrowDown size={15} />
                        </button>
                        {
                          <button
                            className="icon-button"
                            aria-label={'编辑 ' + s.name}
                            onClick={() => setEditor(s)}
                          >
                            <Pencil size={15} />
                          </button>
                        }
                        <button
                          className="icon-button"
                          aria-label={'删除 ' + s.name}
                          onClick={() => {
                            if (confirm(`删除“${s.name}”订阅？`))
                              setLibrary((old) => ({
                                ...old,
                                sources: old.sources.filter((x) => x.id !== s.id),
                              }));
                          }}
                        >
                          <Trash2 size={15} />
                        </button>
                      </div>
                    </article>
                  ))}
              </div>
              <div className="source-footnote">
                <Globe size={16} />
                <p>
                  源的内容与可用性由提供方决定。网页端兼容性取决于源的跨域策略和浏览器解码能力。订阅资源仅供学习研究用途。
                </p>
              </div>
            </>
          ) : (
            <>
              {sectionHeading('MAKE IT YOURS', '偏好设置', '让每一次观看，都更合你的习惯。')}
              <div className="settings-grid">
                <section className="settings-card">
                  <h2>
                    <Play size={18} />
                    播放与搜索
                  </h2>
                  <label className="setting-row">
                    <span>
                      默认播放速度<small>播放页中也可以随时调整</small>
                    </span>
                    <select
                      value={library.settings.rate}
                      onChange={(e) =>
                        setLibrary((old) => ({
                          ...old,
                          settings: { ...old.settings, rate: Number(e.target.value) },
                        }))
                      }
                    >
                      {[0.5, 0.75, 1, 1.25, 1.5, 1.75, 2].map((r) => (
                        <option key={r} value={r}>
                          {r}×
                        </option>
                      ))}
                    </select>
                  </label>
                  <label className="setting-row">
                    <span>
                      自动播放下一集<small>在当前线路中顺序播放</small>
                    </span>
                    <span className="switch">
                      <input
                        type="checkbox"
                        aria-label="自动播放下一集"
                        checked={library.settings.autoNext}
                        onChange={(e) =>
                          setLibrary((old) => ({
                            ...old,
                            settings: { ...old.settings, autoNext: e.target.checked },
                          }))
                        }
                      />
                      <i />
                    </span>
                  </label>
                  <label className="setting-row">
                    <span>
                      搜索并发数<small>同时请求的点播源数量</small>
                    </span>
                    <select
                      value={library.settings.concurrency}
                      onChange={(e) =>
                        setLibrary((old) => ({
                          ...old,
                          settings: { ...old.settings, concurrency: Number(e.target.value) },
                        }))
                      }
                    >
                      {[2, 4, 6, 8].map((n) => (
                        <option key={n}>{n}</option>
                      ))}
                    </select>
                  </label>
                  <label className="setting-row">
                    <span>
                      HLS 前向缓冲目标<small>仅用于 HLS.js，实际缓冲由浏览器决定</small>
                    </span>
                    <select
                      value={library.settings.buffer}
                      onChange={(e) =>
                        setLibrary((old) => ({
                          ...old,
                          settings: { ...old.settings, buffer: Number(e.target.value) },
                        }))
                      }
                    >
                      {[15, 30, 60].map((n) => (
                        <option key={n} value={n}>
                          {n} 秒
                        </option>
                      ))}
                    </select>
                  </label>
                </section>
                <section className="settings-card">
                  <h2>
                    <Layers size={18} />
                    本地数据
                  </h2>
                  <div className="setting-row">
                    <span>
                      备份与迁移<small>导出订阅、设置、起播位置和观看历史</small>
                    </span>
                    <button className="button ghost" onClick={exportData}>
                      <Download size={15} />
                      导出
                    </button>
                  </div>
                  <div className="setting-row">
                    <span>
                      恢复备份<small>导入后将替换此浏览器中的现有数据</small>
                    </span>
                    <label className="button ghost file-input">
                      <Upload size={15} />
                      导入
                      <input
                        type="file"
                        aria-label="导入备份"
                        accept=".json,application/json"
                        onChange={async (e) => {
                          const f = e.target.files?.[0];
                          if (!f) return;
                          try {
                            if (f.size > 5 * 1024 * 1024) throw Error('文件不能超过 5 MB');
                            const data = validateLibrary(JSON.parse(await f.text()));
                            if (confirm('用此备份替换现有本地数据？')) {
                              setLibrary(data);
                              setCanPersist(true);
                              setStorageError('');
                              notify('备份已恢复');
                            }
                          } catch (e) {
                            notify(message(e));
                          }
                        }}
                      />
                    </label>
                  </div>
                  <div className="setting-row">
                    <span>
                      搜索历史<small>{library.searches.length} 条记录</small>
                    </span>
                    <button
                      className="text-button"
                      onClick={() => {
                        setLibrary((old) => ({ ...old, searches: [] }));
                        notify('搜索历史已清空');
                      }}
                    >
                      清空
                    </button>
                  </div>
                  <div className="setting-row">
                    <span>
                      恢复默认订阅<small>只添加缺少的源，保留你的现有订阅</small>
                    </span>
                    <button
                      className="text-button"
                      onClick={() => {
                        setLibrary((old) => {
                          const keys = new Set(old.sources.map(sourceKey));
                          return {
                            ...old,
                            sources: [
                              ...old.sources,
                              ...structuredClone(defaults)
                                .filter((s) => !keys.has(sourceKey(s)))
                                .map((s) => ({ ...s, id: crypto.randomUUID() })),
                            ],
                          };
                        });
                        notify('默认订阅已补齐');
                      }}
                    >
                      恢复
                    </button>
                  </div>
                  <div className="setting-row">
                    <span>
                      重置此浏览器的数据<small>删除所有订阅、历史与个性化设置</small>
                    </span>
                    <button
                      className="text-button danger"
                      onClick={() => {
                        if (confirm('确定删除全部本地数据并恢复初始设置？此操作不可撤销。')) {
                          void clearDiscoveryCache().catch(() => {});
                          setLibrary(initialLibrary());
                          setCanPersist(true);
                          setStorageError('');
                          notify('已恢复初始设置');
                        }
                      }}
                    >
                      重置
                    </button>
                  </div>
                </section>
                <section className="settings-card about-card">
                  <img src="/app-icon.png" alt="" />
                  <h2>HuTV Web</h2>
                  <p>简单连接，自由观看。</p>
                  <span>独立网页版本 · 0.1.0</span>
                  <p className="help">
                    订阅、关键词和观看记录保存在当前浏览器，与 iOS App
                    不同步。读取源数据时可能经本站代理发送至对应服务器；媒体和封面直接连接提供方。清除浏览器数据会删除本地记录，建议定期导出备份。
                  </p>
                  <a
                    className="text-button"
                    href="https://github.com/xiahouzuoxin/HuTV"
                    target="_blank"
                    rel="noreferrer"
                  >
                    GitHub 开源项目
                    <ExternalLink size={14} />
                  </a>
                </section>
              </div>
            </>
          )}
          <footer className="page-footer">
            <span>
              HuTV <i>Web</i>
            </span>
            <p>订阅资源仅供学习研究用途 · 内容由订阅源提供</p>
            <span className="footer-dot" />
          </footer>
        </div>
      </main>
      {editor !== undefined && (
        <SourceEditor
          source={editor ?? undefined}
          sources={library.sources}
          onClose={() => setEditor(undefined)}
          onSave={async (sources) => {
            if (canPersist) await saveLibrary({ ...stateRef.current, sources });
            setLibrary((old) => ({ ...old, sources }));
          }}
        />
      )}
      {toast && (
        <div className="toast" role="status">
          <Check size={17} />
          {toast}
        </div>
      )}
    </div>
  );
}

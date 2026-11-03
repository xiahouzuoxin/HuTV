import { useEffect, useRef, useState } from 'react';
import type Hls from 'hls.js';
import {
  Play,
  Pause,
  SkipBack,
  SkipForward,
  RotateCcw,
  RotateCw,
  Maximize,
  Minimize,
  LockKeyhole,
  UnlockKeyhole,
  RefreshCw,
  Volume2,
  VolumeX,
} from 'lucide-react';
import type { Movie, Episode, Settings } from '../../shared/types';
import { enterFullscreen, type FullscreenMode, type WebkitVideo } from '../lib/fullscreen';
import { time } from '../lib/model';
interface Props {
  movie: Movie;
  episode: Episode;
  settings: Settings;
  start: number;
  opening: number;
  onProgress: (position: number, duration: number) => void;
  onEpisode: (episode: Episode) => void;
  onOpening: (value: number) => void;
  onReload: () => Promise<void>;
}
export function Player({
  movie,
  episode,
  settings,
  start,
  opening,
  onProgress,
  onEpisode,
  onOpening,
  onReload,
}: Props) {
  const video = useRef<HTMLVideoElement>(null),
    box = useRef<HTMLDivElement>(null),
    ready = useRef(false),
    lastSave = useRef(0),
    latest = useRef(onProgress);
  latest.current = onProgress;
  const [paused, setPaused] = useState(true),
    [position, setPosition] = useState(0),
    [duration, setDuration] = useState(0),
    [buffered, setBuffered] = useState(0),
    [error, setError] = useState(''),
    [busy, setBusy] = useState(true),
    [revision, setRevision] = useState(0),
    [visible, setVisible] = useState(true),
    [locked, setLocked] = useState(false),
    [fullscreenMode, setFullscreenMode] = useState<FullscreenMode>('inline'),
    [muted, setMuted] = useState(false),
    [scrub, setScrub] = useState<number | null>(null),
    [reloading, setReloading] = useState(false),
    [activity, setActivity] = useState(0);
  const full = fullscreenMode !== 'inline';
  const [rate, setRate] = useState(settings.rate);
  const initialStart = useRef(start);
  initialStart.current = start;
  const save = () => {
    const v = video.current;
    if (v && ready.current && Number.isFinite(v.currentTime))
      latest.current(v.currentTime, Number.isFinite(v.duration) ? v.duration : 0);
  };
  useEffect(() => {
    const v = video.current!;
    ready.current = false;
    lastSave.current = 0;
    setPosition(0);
    setDuration(0);
    setError('');
    setBusy(true);
    setScrub(null);
    setBuffered(0);
    let hls: Hls | undefined;
    let alive = true;
    let connectionTimer: ReturnType<typeof setTimeout>;
    const metadata = () => {
      if (!alive) return;
      clearTimeout(connectionTimer);
      ready.current = true;
      setDuration(Number.isFinite(v.duration) ? v.duration : 0);
      if (Number.isFinite(v.duration) && v.duration > 0)
        v.currentTime = Math.min(initialStart.current, Math.max(0, v.duration - 1));
      v.playbackRate = rate;
      v.play().catch(() => {
        if (alive) {
          setPaused(true);
          setBusy(false);
          setVisible(true);
        }
      });
    };
    const fail = () => {
      if (alive) {
        setBusy(false);
        setVisible(true);
        setError('视频无法播放，请尝试其他线路或重试。');
      }
    };
    connectionTimer = setTimeout(fail, 30000);
    v.addEventListener('loadedmetadata', metadata);
    v.addEventListener('error', fail);
    if (
      /\.m3u8(?:[?#]|$)/i.test(episode.url) &&
      !(navigator.vendor.includes('Apple') && v.canPlayType('application/vnd.apple.mpegurl'))
    ) {
      void import('hls.js')
        .then(({ default: Engine }) => {
          if (!alive) return;
          if (!Engine.isSupported()) {
            fail();
            return;
          }
          hls = new Engine({
            startLevel: 0,
            capLevelToPlayerSize: true,
            maxBufferLength: settings.buffer,
            maxMaxBufferLength: Math.max(60, settings.buffer),
          });
          hls.loadSource(episode.url);
          hls.attachMedia(v);
          hls.on(Engine.Events.MANIFEST_PARSED, () => {
            if (alive)
              v.play().catch(() => {
                if (alive) {
                  setPaused(true);
                  setVisible(true);
                }
              });
          });
          hls.on(Engine.Events.ERROR, (_event, data) => {
            if (data.fatal) fail();
          });
        })
        .catch(fail);
    } else v.src = episode.url;
    return () => {
      alive = false;
      clearTimeout(connectionTimer);
      if (ready.current && Number.isFinite(v.currentTime))
        onProgress(v.currentTime, Number.isFinite(v.duration) ? v.duration : 0);
      ready.current = false;
      v.removeEventListener('loadedmetadata', metadata);
      v.removeEventListener('error', fail);
      v.pause();
      hls?.destroy();
      v.removeAttribute('src');
      v.load();
    };
    // Source changes restart playback; time/progress updates must not recreate the player.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [episode.id, episode.url, revision]);
  useEffect(() => {
    if (video.current) video.current.playbackRate = rate;
  }, [rate]);
  useEffect(() => {
    const v = video.current!;
    const changed = () =>
      setFullscreenMode(document.fullscreenElement === box.current ? 'element' : 'inline');
    const began = () => setFullscreenMode('video');
    const ended = () => setFullscreenMode('inline');
    document.addEventListener('fullscreenchange', changed);
    v.addEventListener('webkitbeginfullscreen', began);
    v.addEventListener('webkitendfullscreen', ended);
    return () => {
      document.removeEventListener('fullscreenchange', changed);
      v.removeEventListener('webkitbeginfullscreen', began);
      v.removeEventListener('webkitendfullscreen', ended);
    };
  }, []);
  useEffect(() => {
    if (fullscreenMode !== 'viewport') return;
    const previous = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const escape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setFullscreenMode('inline');
    };
    window.addEventListener('keydown', escape);
    return () => {
      document.body.style.overflow = previous;
      window.removeEventListener('keydown', escape);
    };
  }, [fullscreenMode]);
  useEffect(() => {
    const persist = () => save();
    window.addEventListener('pagehide', persist);
    const visibility = () => {
      if (document.hidden) save();
    };
    document.addEventListener('visibilitychange', visibility);
    return () => {
      window.removeEventListener('pagehide', persist);
      document.removeEventListener('visibilitychange', visibility);
    };
  }, []);
  useEffect(() => {
    if (!visible || paused || locked) return;
    const t = setTimeout(() => setVisible(false), 5000);
    return () => clearTimeout(t);
  }, [visible, paused, activity, locked]);
  const toggle = () => {
    if (locked) return;
    const v = video.current;
    if (v) {
      if (v.paused) v.play().catch(() => setError('浏览器阻止了播放，请再点击播放按钮'));
      else v.pause();
    }
  };
  const seek = (seconds: number) => {
    if (locked) return;
    const v = video.current;
    if (v && Number.isFinite(v.duration)) {
      v.currentTime = Math.min(v.duration, Math.max(0, seconds));
      setPosition(v.currentTime);
      setBusy(true);
    }
  };
  const line = movie.episodes.filter((e) => e.line === episode.line),
    index = line.findIndex((e) => e.id === episode.id);
  const move = (offset: number) => {
    const e = line[index + offset];
    if (e) {
      save();
      onEpisode(e);
    }
  };
  useEffect(() => {
    const key = (e: KeyboardEvent) => {
      if (
        locked ||
        e.altKey ||
        e.metaKey ||
        e.ctrlKey ||
        /INPUT|TEXTAREA|SELECT|BUTTON|A/.test((e.target as HTMLElement)?.tagName) ||
        (e.target as HTMLElement)?.isContentEditable
      )
        return;
      if (e.code === 'Space') {
        e.preventDefault();
        toggle();
      }
      if (e.key === 'ArrowRight') {
        e.preventDefault();
        seek((video.current?.currentTime ?? 0) + 10);
      }
      if (e.key === 'ArrowLeft') {
        e.preventDefault();
        seek((video.current?.currentTime ?? 0) - 10);
      }
    };
    window.addEventListener('keydown', key);
    return () => window.removeEventListener('keydown', key);
  });
  const fullscreen = async () => {
    try {
      if (document.fullscreenElement === box.current) {
        await document.exitFullscreen();
      } else if (fullscreenMode === 'video') {
        (video.current as WebkitVideo)?.webkitExitFullscreen?.();
      } else if (fullscreenMode === 'viewport') {
        setFullscreenMode('inline');
      } else if (box.current && video.current) {
        setFullscreenMode(await enterFullscreen(box.current, video.current));
      }
    } catch {
      // Keep the actual fullscreen state when the browser refuses an exit request.
    }
  };
  const progress = () => {
    const v = video.current;
    if (!v || !ready.current) return;
    setPosition(v.currentTime);
    if (v.buffered.length) {
      for (let i = 0; i < v.buffered.length; i++)
        if (v.buffered.start(i) <= v.currentTime && v.buffered.end(i) >= v.currentTime)
          setBuffered(v.buffered.end(i));
    }
    if (Date.now() - lastSave.current > 5000) {
      save();
      lastSave.current = Date.now();
    }
  };
  return (
    <div
      ref={box}
      className={`player ${fullscreenMode === 'element' || fullscreenMode === 'viewport' ? 'fullscreen' : ''}`}
      data-fullscreen={fullscreenMode}
      onPointerMove={(event) => {
        if (event.pointerType === 'mouse' && !locked) {
          setVisible(true);
          setActivity((x) => x + 1);
        }
      }}
      onClick={() => !locked && setVisible((v) => !v)}
      onDoubleClick={() => toggle()}
    >
      <video
        ref={video}
        playsInline
        preload="metadata"
        aria-label={movie.title + ' 播放画面'}
        muted={muted}
        onTimeUpdate={progress}
        onPlaying={() => {
          setPaused(false);
          setBusy(false);
        }}
        onPause={() => {
          setPaused(true);
          save();
        }}
        onWaiting={() => setBusy(true)}
        onCanPlay={() => setBusy(false)}
        onSeeked={() => {
          setBusy(false);
          save();
        }}
        onEnded={() => {
          save();
          if (settings.autoNext && line[index + 1]) move(1);
          else {
            setPaused(true);
            setVisible(true);
          }
        }}
      />
      {locked && (
        <div
          className="touch-shield"
          aria-hidden="true"
          onClick={(e) => e.stopPropagation()}
          onDoubleClick={(e) => e.stopPropagation()}
        />
      )}
      {busy && !error && (
        <div className="player-status">
          <span className="spinner" />
          <span>正在连接媒体…</span>
        </div>
      )}
      {error && (
        <div className="player-status player-error">
          <p>{error}</p>
          <button
            className="button"
            onClick={(e) => {
              e.stopPropagation();
              setRevision((x) => x + 1);
            }}
          >
            重试
          </button>
        </div>
      )}
      {(visible || paused || locked) && (
        <button
          className="lock-button"
          aria-label={locked ? '解锁播放器' : '锁定播放器'}
          onClick={(e) => {
            e.stopPropagation();
            setLocked(!locked);
            setVisible(locked);
          }}
        >
          {locked ? <LockKeyhole size={19} /> : <UnlockKeyhole size={19} />}
        </button>
      )}
      {(visible || paused) && !locked && (
        <>
          <div
            className="player-heading"
            onClick={(e) => e.stopPropagation()}
            onDoubleClick={(e) => e.stopPropagation()}
          >
            <span>
              {movie.title}
              <small>
                {episode.line} · {episode.name}
              </small>
              {fullscreenMode === 'viewport' && (
                <small>当前浏览器仅支持页面内放大，地址栏由浏览器控制</small>
              )}
            </span>
            <button
              className="icon-button"
              aria-label="重新加载"
              disabled={reloading}
              onClick={async () => {
                save();
                setReloading(true);
                try {
                  await onReload();
                  setRevision((x) => x + 1);
                } catch (e) {
                  setError(e instanceof Error ? e.message : '重新加载失败');
                } finally {
                  setReloading(false);
                }
              }}
            >
              <RefreshCw size={19} className={reloading ? 'spinning' : ''} />
            </button>
          </div>
          {!error && !busy && (
            <div
              className="center-controls"
              onClick={(e) => e.stopPropagation()}
              onDoubleClick={(e) => e.stopPropagation()}
            >
              <button aria-label="后退10秒" onClick={() => seek(position - 10)}>
                <RotateCcw size={26} />
              </button>
              <button
                className="center-play"
                aria-label={paused ? '播放' : '暂停'}
                onClick={toggle}
              >
                {paused ? <Play size={35} fill="currentColor" /> : <Pause size={35} />}
              </button>
              <button aria-label="快进10秒" onClick={() => seek(position + 10)}>
                <RotateCw size={26} />
              </button>
            </div>
          )}
          <div
            className="player-controls"
            onClick={(e) => e.stopPropagation()}
            onDoubleClick={(e) => e.stopPropagation()}
          >
            <div className="player-options">
              <button
                title="点击记录当前时间，右键清除"
                onClick={() => onOpening(position)}
                onContextMenu={(e) => {
                  e.preventDefault();
                  onOpening(0);
                }}
              >
                {opening ? time(opening) : '起播'}
              </button>
              <select
                aria-label="播放速度"
                value={rate}
                onChange={(e) => setRate(Number(e.target.value))}
              >
                {[0.5, 0.75, 1, 1.25, 1.5, 1.75, 2].map((r) => (
                  <option key={r} value={r}>
                    {r}×
                  </option>
                ))}
              </select>
              <button aria-label={muted ? '取消静音' : '静音'} onClick={() => setMuted(!muted)}>
                {muted ? <VolumeX size={18} /> : <Volume2 size={18} />}
              </button>
            </div>
            <div className="transport">
              <button aria-label="上一集" disabled={index <= 0} onClick={() => move(-1)}>
                <SkipBack size={19} />
              </button>
              <button aria-label={paused ? '开始播放' : '暂停播放'} onClick={toggle}>
                {paused ? <Play size={21} fill="currentColor" /> : <Pause size={21} />}
              </button>
              <button aria-label="下一集" disabled={!line[index + 1]} onClick={() => move(1)}>
                <SkipForward size={19} />
              </button>
              <span>
                {time(scrub ?? position)}
                <small className="mobile-total"> / {time(duration)}</small>
              </span>
              <input
                aria-label="播放进度"
                type="range"
                min="0"
                max={duration || 1}
                step="0.1"
                disabled={!duration}
                value={scrub ?? Math.min(position, duration || 1)}
                style={{
                  background: `linear-gradient(to right,#48d4bc ${((scrub ?? position) / (duration || 1)) * 100}%,#ffffff70 0%,#ffffff70 ${(buffered / (duration || 1)) * 100}%,#ffffff30 0%)`,
                }}
                onChange={(e) => setScrub(Number(e.target.value))}
                onPointerUp={(e) => {
                  seek(Number(e.currentTarget.value));
                  setScrub(null);
                }}
                onKeyUp={(e) => {
                  seek(Number(e.currentTarget.value));
                  setScrub(null);
                }}
              />
              <span>{time(duration)}</span>
              <button aria-label={full ? '退出全屏' : '全屏播放'} onClick={fullscreen}>
                {full ? <Minimize size={20} /> : <Maximize size={20} />}
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}

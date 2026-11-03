import { useState } from 'react';
import { X, Plus, Link, FileJson, Upload, Check } from 'lucide-react';
import { requestMode, requestModes, type Source } from '../../shared/types';
import { httpURL, downloadURL, importSources, sourceKey } from '../lib/model';
import { fetchText } from '../lib/api';
export function SourceEditor({
  source,
  sources,
  onClose,
  onSave,
}: {
  source?: Source;
  sources: Source[];
  onClose: () => void;
  onSave: (sources: Source[]) => void;
}) {
  const [tab, setTab] = useState('single'),
    [name, setName] = useState(source?.name ?? ''),
    [url, setUrl] = useState(source?.url ?? ''),
    [kind, setKind] = useState<'cms' | 'live'>(source?.kind === 'live' ? 'live' : 'cms'),
    [mode, setMode] = useState(requestMode(source?.requestMode)),
    [text, setText] = useState(''),
    [error, setError] = useState(''),
    [busy, setBusy] = useState(false),
    [preview, setPreview] = useState<Source[] | null>(null);
  const commit = (entries: Source[]) => {
    const keys = new Set(sources.filter((s) => s.id !== source?.id).map(sourceKey));
    const unique = entries.filter((s) => !keys.has(sourceKey(s)) && (keys.add(sourceKey(s)), true));
    if (!unique.length) {
      setError('这些订阅已经存在');
      return;
    }
    onSave(
      source ? sources.map((s) => (s.id === source.id ? unique[0] : s)) : [...sources, ...unique],
    );
    onClose();
  };
  return (
    <div
      className="modal-backdrop"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <section
        className="modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="source-editor-title"
      >
        <div className="section-title">
          <div>
            <span className="eyebrow">YOUR SOURCES</span>
            <h2 id="source-editor-title">{source ? '编辑订阅' : '添加你喜欢的内容'}</h2>
          </div>
          <button className="icon-button" aria-label="关闭" onClick={onClose}>
            <X />
          </button>
        </div>
        {!source && (
          <div className="segmented">
            <button
              className={tab === 'single' ? 'active' : ''}
              onClick={() => {
                setTab('single');
                setError('');
              }}
            >
              单个订阅
            </button>
            <button
              className={tab === 'batch' ? 'active' : ''}
              onClick={() => {
                setTab('batch');
                setError('');
              }}
            >
              JSON 批量导入
            </button>
          </div>
        )}
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            setError('');
            try {
              if (tab === 'single') {
                commit([
                  {
                    id: source?.id ?? crypto.randomUUID(),
                    name: name.trim() || new URL(url).hostname,
                    url: httpURL(url),
                    kind,
                    enabled: source?.enabled ?? true,
                    requestMode: mode,
                  },
                ]);
              } else {
                if (preview) {
                  commit(preview);
                  return;
                }
                setBusy(true);
                const input = text.trim().startsWith('[')
                  ? text
                  : await fetchText(downloadURL(text));
                setPreview(importSources(input));
              }
            } catch (e) {
              setError(e instanceof Error ? e.message : '导入失败');
            } finally {
              setBusy(false);
            }
          }}
        >
          {tab === 'single' ? (
            <>
              <label>
                订阅名称
                <input
                  autoFocus
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="例如：我的电影源"
                  maxLength={100}
                />
              </label>
              <label>
                订阅类型
                <select value={kind} onChange={(e) => setKind(e.target.value as 'cms' | 'live')}>
                  <option value="cms">CMS JSON · 点播</option>
                  <option value="live">M3U / TXT · 直播</option>
                </select>
              </label>
              <label>
                请求模式
                <select
                  aria-label="请求模式"
                  value={mode}
                  onChange={(e) => setMode(requestMode(e.target.value))}
                >
                  {Object.entries(requestModes).map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
              </label>
              <p className="help">
                自动先直连，失败后使用服务器代理；仅影响订阅数据，视频仍由浏览器直连。
              </p>
              <label>
                订阅地址
                <div className="input-icon">
                  <Link size={17} />
                  <input
                    required
                    value={url}
                    onChange={(e) => setUrl(e.target.value)}
                    placeholder="https://example.com/api.php/provide/vod/"
                  />
                </div>
              </label>
            </>
          ) : (
            <>
              <label>
                JSON 内容或在线列表链接
                <textarea
                  value={text}
                  onChange={(e) => {
                    setText(e.target.value);
                    setPreview(null);
                  }}
                  placeholder={'[{"name":"我的源","api":"https://…","kind":"cms"}]'}
                  rows={6}
                />
              </label>
              <label className="file-input">
                <Upload size={17} /> 选择 JSON 文件
                <input
                  type="file"
                  accept=".json,application/json"
                  onChange={async (e) => {
                    const f = e.target.files?.[0];
                    if (f) {
                      if (f.size > 5 * 1024 * 1024) {
                        setError('文件不能超过 5 MB');
                        return;
                      }
                      setText(await f.text());
                      setPreview(null);
                    }
                  }}
                />
              </label>
              {preview && (
                <div className="import-preview">
                  <Check size={17} />
                  <span>识别到 {preview.length} 个订阅，确认后导入。重复地址会跳过。</span>
                </div>
              )}
            </>
          )}
          <p className="help">
            订阅保存在此浏览器中。仅支持直连 CMS JSON 和 HTTP(S) 直播列表，不执行 JAR / JS 爬虫。
          </p>
          {error && (
            <p className="error" role="alert">
              {error}
            </p>
          )}
          <div className="modal-actions">
            <button type="button" className="button ghost" onClick={onClose}>
              取消
            </button>
            <button className="button primary" disabled={busy || (!text.trim() && tab === 'batch')}>
              {busy ? (
                <span className="spinner" />
              ) : tab === 'single' ? (
                <Plus size={17} />
              ) : (
                <FileJson size={17} />
              )}{' '}
              {source
                ? '保存修改'
                : tab === 'single'
                  ? '添加订阅'
                  : preview
                    ? '确认导入'
                    : '预览订阅'}
            </button>
          </div>
        </form>
      </section>
    </div>
  );
}

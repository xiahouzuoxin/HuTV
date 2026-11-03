# HuTV Web

独立运行的 HuTV 网页播放器。标识与浏览器图标直接复用 iOS App 的浅色蓝绿图标。前端为 React / TypeScript / Vite，视频使用浏览器原生 `<video>` 和按需加载的 HLS.js；轻量 Cloudflare Worker 只转发订阅数据。iOS 项目不依赖本目录，两个版本的订阅、设置和观看记录分别保存。

## 当前功能

- CMS JSON 点播、M3U / TXT 直播；订阅添加、编辑、开关、删除、拖动及按钮排序。
- 单个地址、JSON 数组、在线 JSON 链接和 GitHub 文件链接导入，重复订阅跳过。
- 多源并发搜索、取消搜索、按有效结果数排列源、搜索历史标签。
- 影片卡片、源提供的豆瓣／源评分、年份、地区、导演、演员、完整简介、线路和集数。
- 原生 MP4 / HLS，以及按需加载的 HLS.js；缓冲进度、倍速、静音、全屏、上一集／下一集、自动连播、手动重新加载、起播位置和防误触锁。
- 键盘空格播放／暂停，左右方向键快退／快进 10 秒。播放器显示控制后 5 秒自动隐藏，暂停时保留。
- IndexedDB 本地观看历史和进度、继续观看、设置、备份导入导出和数据重置。
- 桌面、平板和手机布局；首页默认显示豆瓣推荐，电影／剧集分类按需加载，每类最多 20 条，缓存 24 小时，支持手动刷新；点击推荐在点播订阅中搜索。

网页端暂未实现账号／跨设备同步、离线下载、网盘解析、JAR / JS 爬虫、媒体转码和视频分片代理。播放器不能绕过浏览器的格式、跨域、自动播放和后台运行限制；HLS.js 不会增加浏览器解码器。豆瓣推荐不代表订阅源一定有可播放资源，读取失败时保留已有缓存并可手动重试。

在线地址：[https://hutv-web.hutv-web.workers.dev](https://hutv-web.hutv-web.workers.dev)

## 本地运行

需要 Node.js 22.22+（推荐 Node 22 LTS）与 npm。

```bash
cd web
npm ci
npm run dev
```

打开终端打印的本地地址（默认 `http://127.0.0.1:5173`）。开发服务器包含与线上相同的受限订阅代理。

```bash
npm test          # 解析、导入、请求并发与代理边界测试
npm run build    # TypeScript 检查、前端及独立 Worker 构建
npm run validate # 检查独立 Worker 产物
npm run preview  # 使用 Wrangler 检查生产构建，默认端口 8787
```

浏览器自动化测试：安装 Chromium（`npx playwright install chromium`），然后 `npm run test:e2e`。也可设置 `PLAYWRIGHT_CHROME_PATH` 使用已安装的 Chrome。测试接口使用本地固定响应，不能据此认定所有远程源可用；远程源与真实播放需另外验证。

## 免费部署到自己的 Cloudflare 账号

直接 Cloudflare 部署使用 Static Assets 托管前端，只有 `/api/*` 进入 Worker。无需数据库、对象存储或付费转码服务。

```bash
cd web
npm ci
npx wrangler login
npm run deploy
```

部署后 Wrangler 会返回 `https://hutv-web.<你的子域>.workers.dev`。如需 GitHub 自动部署：在 Cloudflare Workers & Pages 中连接仓库，项目根目录设为 `web`，构建命令设为 `npm run build`，部署命令设为 `npx wrangler deploy`。先用免费默认域名验证页面、接口、播放在实际网络中的可达性，再绑定自己的域名。

截至 2026-11-03，Workers Free 动态请求额度为每天 100,000 次、每次 10ms CPU；静态资源请求免费且不限量。每个搜索源请求独立消耗一次动态请求，转发等待不等于 CPU 时间。保持 Free 方案即可从小规模使用开始，不要把视频文件或媒体分片转发放进本项目的数据代理。具体额度以[Cloudflare 定价](https://developers.cloudflare.com/workers/platform/pricing/)和[静态资源说明](https://developers.cloudflare.com/workers/static-assets/billing-and-limitations/)为准。

### 自定义订阅和代理白名单

内置点播／直播域名及 `raw.githubusercontent.com` 默认允许通过服务器读取。自定义订阅先尝试代理；不在白名单时尝试浏览器直连。若源不允许跨域，需要在 `wrangler.jsonc` 的 `vars.ALLOWED_ORIGINS` 中添加准确的源 origin，例如：

```json
{"ALLOWED_ORIGINS":"https://your-cms.example,https://your-playlist.example"}
```

部署后生效。只添加你信任的公开域名，不使用 `*`。重定向目标也必须在白名单中。代理限制为 HTTP(S)、同站 JSON POST、8KB 请求和 5MB 响应、15 秒超时、最多 3 次重定向；不转发浏览器 Cookie 或源账号。源 URL 中自带的查询令牌仍会发送给对应源，请勿公开分享含凭证的订阅。

视频及订阅源封面直接连接提供方；豆瓣封面使用仅允许固定豆瓣 CDN 地址的专用代理，不需要加入通用代理白名单。出现跨域、HTTP 混合内容或编码问题时，切换其他线路／源；在 Worker 添加 API 域名不能解决视频 CDN 的跨域限制。自用源接口可能拒绝云端 IP，需要实测。

## 数据与隐私

- 订阅和历史使用独立 IndexedDB 数据库 `hutv-web`，推荐缓存使用 `hutv-discovery`。正常播放约每 5 秒写入进度，暂停、切集和离开播放器时补存；强制关闭浏览器可能丢失最后几秒。
- 浏览器清理站点数据会删除订阅和历史，请在设置中导出备份。备份可能包含订阅令牌，不应提交到 GitHub。
- 本站不提供账户系统，不会自动把本机历史或订阅同步给其他设备或 iOS App。
- 代理把订阅请求发给源服务器，媒体和封面直接连接提供方；它们可能收到 IP 地址、请求关键词、时间和来源信息。界面字体请求 Google Fonts，失败时使用系统字体。
- `dist/` 是包含前端资源的独立 Worker 产物，可用于 Sites 预览；直接部署自己的 Cloudflare 账号使用 `wrangler.jsonc` 与 `client-dist/`，两者执行相同的 API 实现。

## 文件结构

- `src/`：页面、播放器、数据存储与客户端请求。
- `shared/`：独立的 Web 数据类型、默认订阅、演示内容与响应体大小限制。
- `worker/`：源白名单与订阅代理。
- `tests/`、`e2e/`：核心单元测试与浏览器流程测试。
- `scripts/`：独立 Worker 打包和产物验证。

## 内容来源

默认订阅与 iOS 版本的 `Core/Subscription/DefaultSubscriptions.swift` 初始保持一致，但 Web 使用自己的快照，后续分别维护；资源来源见仓库根目录 [README](../README.md)。

豆瓣推荐使用 `https://movie.douban.com/j/search_subjects` 网页 JSON 接口，分类与 iOS 版本一致。接口不是稳定性承诺的开放 API，可能限流或拒绝云端访问。封面只通过专用代理请求豆瓣图片域名，带固定的 User-Agent / Referer；浏览器与边缘节点缓存一天。推荐列表按“电影／剧集＋分类”分别存入浏览器 IndexedDB，默认只请求电影热门，其他分类在选中时才加载；手动刷新只更新当前分类。

公开演示订阅和影片素材已移除。升级时会删除旧版演示订阅及其观看历史，保留其他订阅和进度。

订阅资源仅供学习研究用途。

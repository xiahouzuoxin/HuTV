# HuTV

iPhone 原生视频订阅客户端，支持独立的 CMS JSON 点播接口、M3U / TXT 直播列表及 TVBox 聚合配置。用户可自行添加源；当前内置十三个默认点播接口和三个直播列表，详见“默认点播源”。

## 使用

点击订阅页右上角加号，选择类型并填写 URL、可选名称：

- **点播 API**：填写标准苹果 CMS JSON 接口，例如 `https://example.com/api.php/provide/vod/`。导入时校验分类响应，点击订阅直接进入分类和影视列表。支持分页、多源搜索、详情及分线路选集。
- **直播 M3U / TXT**：填写频道列表 URL，导入时校验能否解析出频道。点击订阅直接进入频道页，支持分组、搜索、同频道多线路及列表中的请求头。
- **TVBox 配置**：填写含有效 `sites` 或 `lives` 的配置直链，进入订阅后按源选择点播或直播。支持仅含直播的配置。

每种订阅按自身协议刷新；左滑显示删除、右滑刷新，也可在首页下拉刷新全部。订阅页按点播源、直播源、聚合配置分组，显示各组数量。点击左上角“编辑”，可删除订阅或在各组内拖动右侧排序手柄，点“完成”退出。顺序保存在本机，刷新、重复导入和重启后保留。订阅保存到 Application Support 下的 `TVBoxiOS/subscriptions-v2.json`。本次模型调整不迁移旧版本实验数据。

导入成功表示接口或频道列表格式通过校验，不保证所有视频均可播放。点播优先选择提供 M3U8 / MP4 媒体地址的线路。网页地址、待解析 ID、DRM 或不受系统支持的媒体格式不能当作普通直链播放。当前没有通用网页解析或 JS 爬虫引擎；可选择 AVPlayer 或 VLC 内核。

## 架构

- `SubscriptionKind` / `Warehouse`：订阅类型、地址、名称及解析后的源。
- `SubscriptionLoader`：按协议验证并构建订阅；TVBox 支持 ETag / Last-Modified 条件刷新。
- `TVBoxConfigDecoder`：独立处理 UTF-8 BOM、字符串外 JSON 注释、尾逗号，以及 JPEG / PNG 尾部 `标记**Base64` 包装。
- `ContentProvider` / `StandardCMSProvider`：点播分类、列表、搜索和详情。仅将有效 HTTP(S) `type: 1` 接口作为原生支持。
- `LivePlaylistLoader`：M3U、TVBox TXT 解析及频道去重。
- `HTTPDataLoading` / `BoundedHTTPClient`：可替换的网络访问边界及响应大小限制，用于确定性测试。
- AVPlayer：本机播放，提供加载失败和重试提示。

`type: 3`、`csp_*`、Spider JAR 只保存配置并显示不支持状态，不在 iOS 执行。饭太硬 `/tv` 的图片包装格式已通过实际响应验证，但其中的爬虫影视源仍不能直接播放。

## 构建与测试

需要安装 Xcode、XcodeGen 和 iOS 模拟器运行时，部署目标为 iOS 17。首次检出后先下载 VLC 依赖，再生成工程：

```sh
./scripts/fetch-vlckit.sh
xcodegen generate
```

打开 `HuTV.xcodeproj`，选择 `HuTV` Scheme 和模拟器运行。真机运行需自行配置签名团队。

```sh
xcodebuild -project HuTV.xcodeproj -scheme HuTV \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

自动测试覆盖三种订阅验证、错误格式拒绝、直播独立保存与刷新、TVBox 图片包装和 JSON 扩展、直播请求头解析等。外部源联网与媒体播放另行实测，不作为依赖外站可用性的自动测试。

## 搜索与观看历史

搜索结果按订阅内的数据源显示为横向 Tab，分别显示加载状态、数量和错误。切换关键词或清空搜索时，旧请求不会覆盖新的结果。搜索词保存在本机，最多 30 条，可点击重搜、删除或清空。

“历史”页以自适应卡片网格展示最近 200 条点播/直播记录，包含封面、集数和进度。点击卡片继续观看，卡片右上角菜单可删除单条记录，顶部可清空。点播在媒体就绪后记录集数，每 2 秒以及退出播放器/进入后台时保存进度。继续观看会重新获取详情和集数 URL，再尝试跳到上次位置；临近片尾的记录从头播放。直播记录用于重新打开频道，不进行进度定位。两类历史保存在 Application Support 的 `TVBoxiOS/history.json`，不会上传。

## 集数与连续播放

详情页使用自适应集数网格。播放器默认在当前线路内自动播放下一集，最后一集结束后停止，不跳到其他线路。底部同一行按“上一集／播放或暂停／下一集／当前时间／进度条／总时长”排列；首集、末集会禁用对应按钮。可在播放菜单/设置中关闭自动连播。切集会重新创建播放器状态，并将观看历史更新为新的集数。

点播可选择系统自动、30 秒（默认）或 60 秒的前向缓冲目标；直播保持系统自动。预缓冲目标不代表开播前必须等待该时长，也不保证源站能提供足够速度。播放器显示加载/缓冲状态及当前播放位置之后可用的连续缓冲秒数。

## 默认订阅源

首次运行添加下表的 13 个 CMS JSON 点播接口和 3 个直播列表。升级只补充新增预置项，不恢复用户删除的旧源；已有同类型同地址订阅保留原名称和身份。删除后重启不会恢复，设置页可手动添加缺少的默认源。

新增源已做接口/列表、媒体分片和短时解码抽样，详见[验证记录](Docs/DefaultSources.md)。部分直播条目是网页或受地区限制，导入列表不代表全部频道都能播放。默认配置只包含接口/列表地址，连接与播放受第三方服务可用性影响。


### 默认资源地址与来源

点播接口发现于 [cms-player/vod-source](https://github.com/cms-player/vod-source/blob/main/source.json)，360 接口另见 [fangkuia/XPTV](https://github.com/fangkuia/XPTV/blob/main/allinone.json)。这些是接口收录来源，不代表服务由 GitHub 或本 App 运营，也不代表已取得内容授权。

| 点播源 | CMS JSON 地址 | 收录来源 |
|---|---|---|
| 暴风资源 | `https://bfzyapi.com/api.php/provide/vod/` | 原有默认配置 |
| 非凡资源 | `https://api.ffzyapi.com/api.php/provide/vod/` | 原有默认配置 |
| 索尼资源 | `https://suoniapi.com/api.php/provide/vod/` | 原有默认配置；cms-player/vod-source 亦收录 |
| 魔都动漫 | `https://www.mdzyapi.com/api.php/provide/vod/` | 原有默认配置 |
| 量子资源 | `https://cj.lziapi.com/api.php/provide/vod/` | cms-player/vod-source |
| 红牛资源 | `https://www.hongniuzy2.com/api.php/provide/vod/` | cms-player/vod-source |
| 360资源 | `https://360zy.com/api.php/provide/vod/` | fangkuia/XPTV |
| 无尽资源 | `https://api.wujinapi.com/api.php/provide/vod/` | cms-player/vod-source |
| 极速资源 | `https://jszyapi.com/api.php/provide/vod/` | cms-player/vod-source |
| 光速资源 | `https://api.guangsuapi.com/api.php/provide/vod/` | cms-player/vod-source |
| ikun资源 | `https://ikunzyapi.com/api.php/provide/vod/` | cms-player/vod-source |
| U酷资源 | `https://api.ukuapi.com/api.php/provide/vod/` | cms-player/vod-source |
| 闪电资源 | `https://sdzyapi.com/api.php/provide/vod/` | cms-player/vod-source |

暴风、非凡、索尼、魔都为项目原有预置接口，除表中注明外，本轮未重新追溯其收录来源或重新测试；未用猜测的 GitHub 地址补全出处。

| 直播列表 | M3U 地址 | 来源项目 |
|---|---|---|
| IPTV-org 中文 | `https://iptv-org.github.io/iptv/languages/zho.m3u` | [iptv-org/iptv](https://github.com/iptv-org/iptv) |
| Free-TV 国际 | `https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8` | [Free-TV/IPTV](https://github.com/Free-TV/IPTV) |
| IPTV-org 新闻 | `https://iptv-org.github.io/iptv/categories/news.m3u` | [iptv-org/iptv](https://github.com/iptv-org/iptv) |

2026-10-30 新增的极速、光速、ikun、U酷、闪电和新闻列表均通过当前 Mac 网络下的接口/清单、媒体分片访问和至少一个视频样本的两秒解码抽测。未逐项做 iPad 实机、长时播放或全量内容验证。测试可用不等于获得内容授权，源站、网络和地区限制会影响结果。

## 播放器连接、续播与触屏操作

播放器使用独立的 `PlaybackController` 管理每次加载。连接就绪等待上限为 45 秒，进度定位单独限时 15 秒；错误显示底层错误码。退出会保存进度、停止播放、取消定位与媒体加载、断开旧播放项，旧任务不能修改新会话。打开集数前重新获取详情中的播放地址。第三方源自身超时、限速或失效仍可能导致无法播放。

观看进度每 2 秒、退出及切后台时保存。从历史、详情的“继续观看”或再次点开上次集数都可恢复进度。定位失败时可重试或选择从头播放，不会在加载阶段把原进度覆盖成 0。

播放器画面中部支持：横滑预览进度，松手跳转；右侧上下滑调节视频音量（相对于系统音量）；左侧上下滑调节屏幕亮度，退出后恢复进入前亮度。底部进度条、播放按钮与顶部操作区不参与这些手势。无可定位时长的直播不支持横滑跳转。

前台播放及缓冲时保持亮屏；暂停、退出或切到后台时释放保持亮屏状态。多个播放会话交接时按所有权管理，避免旧会话释放新会话的亮屏设置。


## HuTV 双内核构建

App 显示名、工程、Scheme 和主模块均为 HuTV。保留原实验版本的 Application Support 存储路径，避免已有订阅与历史丢失。

采用官方稳定版 MobileVLCKit 3.7.3，二进制包 SHA-256 为
`0d04059906962ddc9a7bd1ebaa12e1f9ae85eb2466116a97a2f46886dd27a0a9`。
首次获取工程依赖后生成工程：

```sh
./scripts/fetch-vlckit.sh
xcodegen generate
```

打开 `HuTV.xcodeproj`，选择 HuTV Scheme。设置页可选择默认内核；点播与直播播放菜单也可切换，失败界面可直接改用另一个内核。切换时保存并尝试恢复当前进度。VLC 提供独立播放/暂停和进度条，共享手势、观看历史、自动连播和亮屏管理。

AVPlayer 的前向缓冲目标与 VLC 的网络缓存不是同一种参数；VLC 网络缓存限制为最多 3 秒，避免把 30/60 秒目标直接变成长时间开播等待。VLC 3 的适配支持 User-Agent 和 Referer；其他自定义请求头会提示切换 AVPlayer。第三方源是否稳定仍需实际对比，接入 VLC 不保证所有源可播。

二进制未经修改。App 内“开源许可”包含 LGPL 文本及对应源码链接；依赖元数据位于 `Vendor/MobileVLCKit-3.7.3.podspec.json`。发布构建应保留相应源码、修改说明（如有）及适用的重新链接材料。

播放器使用统一控制条。AVPlayer 的浅色轨道显示实际 loadedTimeRanges 缓冲范围，主色显示已播放部分，并显示连续缓冲到的时间。MobileVLCKit 3.7.3 的公开 API 不提供缓存时间范围，VLC 仅显示缓冲状态，不将配置的缓存时长伪装成实际下载进度。

画面中部双击可暂停/继续播放，单击显示或隐藏底部控制条。两种内核共用点击识别；单击等待双击识别失败后再触发，滑动操作不会同时触发点击。

## 发布准备

提交前检查与待补材料见 [发布清单](Docs/Release/Checklist.md)。隐私说明正文随 App 打包在 `App/Resources/PrivacyPolicy.txt`，设置页可查看。当前仍保留默认点播接口；发布准备不代表已取得内容授权或已满足全部审核条件。

## 全屏控制与倍速

全屏点播/直播默认隐藏顶部信息、系统状态栏和底部进度控件。单击视频中间区域同时显示或隐藏上下控件；双击仍切换播放/暂停，不额外唤出控件。显示控件后可从底部的速度菜单选择 0.5×、0.75×、1×、1.25×、1.5×、1.75×、2×，选择保存在本机，适用于 AVPlayer 和 VLC。切集、重试和切换内核继续使用所选速度。直播服务可能限制变速或没有可跳转进度。

## 版本管理

提交源码、资源、测试、文档、`project.yml` 和依赖下载脚本。Xcode 工程由 XcodeGen 生成，不提交生成工程、用户界面状态、构建目录、签名 IPA、证书或配对文件。官方 VLC 二进制不入库，通过带 SHA-256 校验的脚本获取；许可证和依赖元数据保留在仓库。

源码中的 `TVBoxiOS` 本机数据目录沿用已有路径，用于保留订阅和观看记录；TVBox JSON 兼容解析属于当前功能，不是待删除的旧代码。

## 签名续期

免费/付费侧载有效期、Mac Xcode 覆盖安装、Mac/Windows 后台自动刷新、IPA 打包和过期恢复见[签名到期与刷新指南](Docs/SigningRefresh.md)。文档不代表已安装或配置第三方刷新工具。

## 播放中切换源

单击视频中间显示控件，点右上角“切换源”。可更新当前影片的播放线路并手动选集，或进入“搜索其他源中的同名影片”，在其他订阅的搜索结果中确认影片版本、线路与集数。搜索期间原视频继续播放，不自动按名称或集数猜测匹配。

默认保留当前进度，可关闭后从头播放；不同版本时长可能不同，切换后可能需要微调。新会话使用实际选中的影片和订阅源记录历史，并在新线路内上一集、下一集及自动连播。旧播放会话的延迟回调不会覆盖新会话的进度。倍速、缓冲和内核偏好沿用现有设置。列表中需要额外网页解析的集数不支持直接切换播放。

直播也使用右上角独立的“切换源”入口：选择当前频道备用线路，或加载其他直播订阅、按频道名筛选后手动确认频道和线路。搜索不会中断原直播，切换后更新频道、节目单与观看历史；直播不迁移点播进度。播放器设置只保留适用的内核选项，倍速仍在底部控制栏。

直播与点播播放器页面统一使用 `PlayerPage`（全屏布局、顶部控件、控件显隐、关闭/换源入口和播放设置），下层共用 `NativePlayerView` / `PlaybackController`（内核、倍速、手势、缓冲、进度和亮屏）。只保留业务差异：点播的选集/连播与续播，直播的频道/备用线路与节目单。节目单显示在顶部信息区，避免覆盖底部进度控件。

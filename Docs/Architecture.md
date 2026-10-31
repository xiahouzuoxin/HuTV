# 架构与播放器依赖

## 架构

- `SubscriptionKind` / `Warehouse`：订阅类型、地址、名称及解析后的源。
- `SubscriptionLoader`：按协议验证并构建订阅；TVBox 支持 ETag / Last-Modified 条件刷新。
- `TVBoxConfigDecoder`：独立处理 UTF-8 BOM、字符串外 JSON 注释、尾逗号，以及 JPEG / PNG 尾部 `标记**Base64` 包装。
- `ContentProvider` / `StandardCMSProvider`：点播分类、列表、搜索和详情。仅将有效 HTTP(S) `type: 1` 接口作为原生支持。
- `LivePlaylistLoader`：M3U、TVBox TXT 解析及频道去重。
- `HTTPDataLoading` / `BoundedHTTPClient`：可替换的网络访问边界及响应大小限制，用于确定性测试。
- AVPlayer：本机播放，提供加载失败和重试提示。

`type: 3`、`csp_*` 来源保留基本信息并显示不支持状态，不在 iOS 执行爬虫。配置只持久化当前使用的 sites/lives 字段，忽略未使用的 spider、parses、ext 等元数据。饭太硬 `/tv` 的图片包装格式已通过实际响应验证，但其中的爬虫影视源仍不能直接播放。

## 播放器依赖

App 显示名、工程、Scheme 和主模块均为 HuTV。保留原实验版本的 Application Support 存储路径，避免已有订阅与历史丢失。

采用官方稳定版 MobileVLCKit 3.7.3，二进制包 SHA-256 为
`0d04059906962ddc9a7bd1ebaa12e1f9ae85eb2466116a97a2f46886dd27a0a9`。
首次获取工程依赖后生成工程：

```sh
./scripts/fetch-vlckit.sh
xcodegen generate
```

打开 `HuTV.xcodeproj`，选择 HuTV Scheme。设置页可选择默认内核；点播与直播播放菜单也可切换，失败界面可直接改用另一个内核。切换时保存并尝试恢复当前进度。两种内核共用播放/暂停、进度条、手势、观看历史、自动连播和亮屏管理。

AVPlayer 的前向缓冲目标与 VLC 的网络缓存不是同一种参数；VLC 网络缓存限制为最多 3 秒，避免把 30/60 秒目标直接变成长时间开播等待。VLC 3 的适配支持 User-Agent 和 Referer；其他自定义请求头会提示切换 AVPlayer。第三方源是否稳定仍需实际对比，接入 VLC 不保证所有源可播。

Vendor 中保留官方原始二进制；侧载打包时在临时副本中只保留 arm64 并移除旧签名，由侧载工具重新签名。App 内“开源许可”包含 LGPL 文本及对应源码链接；依赖元数据位于 `Vendor/MobileVLCKit-3.7.3.podspec.json`。发布构建应保留相应源码、修改说明（如有）及适用的重新链接材料。

播放器使用统一控制条。AVPlayer 的浅色轨道显示实际 loadedTimeRanges 缓冲范围，主色显示已播放部分，并显示连续缓冲到的时间。MobileVLCKit 3.7.3 的公开 API 不提供缓存时间范围，VLC 仅显示缓冲状态，不将配置的缓存时长伪装成实际下载进度。

画面中部双击可暂停/继续播放，单击显示或隐藏底部控制条。两种内核共用点击识别；单击等待双击识别失败后再触发，滑动操作不会同时触发点击。

## 版本管理

提交源码、资源、测试、文档、`project.yml` 和依赖下载、IPA 打包脚本。Xcode 工程由 XcodeGen 生成，不提交生成工程、用户界面状态、构建目录、IPA（含未签名包）、证书或配对文件。官方 VLC 二进制不入库，通过带 SHA-256 校验的脚本获取；许可证和依赖元数据保留在仓库。

源码中的 `TVBoxiOS` 本机数据目录沿用已有路径，用于保留订阅和观看记录；TVBox JSON 兼容解析属于当前功能，不是待删除的旧代码。

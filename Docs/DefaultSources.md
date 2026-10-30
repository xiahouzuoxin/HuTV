# 默认订阅源验证记录

测试日期：2026-10-30（Asia/Shanghai），从当前 Mac 网络测试。测试结果反映当时的连接状态，不是内容授权声明，也不保证所有视频、频道或地区可用。

候选发现：
- CMS：[cms-player/vod-source](https://github.com/cms-player/vod-source/blob/main/source.json)；360 接口另见 [fangkuia/XPTV](https://github.com/fangkuia/XPTV/blob/main/allinone.json)。
- 直播：[iptv-org/iptv](https://github.com/iptv-org/iptv)、[Free-TV/IPTV](https://github.com/Free-TV/IPTV)。

## 验证范围

CMS：分类 JSON → 第一页详情 → 按 ID 详情 → 原始 HLS 主/子清单 → 少量媒体分片 → FFmpeg 解码两秒视频。每个新增点播接口成功解码一个样本；未穷举全部内容，未验证持续播放、搜索、音轨及 iOS AVPlayer/VLC 的逐源实机表现。

直播：下载 M3U、统计 EXTINF 条目，抽测直接 HTTPS HLS 地址及分片，每个列表至少一个样本解码两秒视频。忽略网页地址，不把网页响应当成可播放媒体。Mac FFmpeg 解码通过不代表所有 iOS 内核均兼容。

| 候选 | 类型 | 接口/列表检查 | 媒体解码 | 默认配置 |
|---|---|---|---|---|
| 量子资源 | 点播 | 40 分类 / 20 条详情 | 通过 | 新增 |
| 红牛资源 | 点播 | 44 分类 / 20 条详情 | 通过 | 新增 |
| 天空资源 | 点播 | 响应不是有效 JSON | 未通过/未执行 | 不加入 |
| 360资源 | 点播 | 51 分类 / 20 条详情 | 通过 | 新增 |
| 卧龙资源 | 点播 | DNS 解析失败 | 未通过/未执行 | 不加入 |
| 无尽资源 | 点播 | 63 分类 / 20 条详情 | 通过 | 新增 |
| IPTV-org中文 | 直播 | 221 个频道条目 | 通过 | 新增 |
| Free-TV | 直播 | 2053 个频道条目 | 通过 | 新增 |

Free-TV 抽样的 CNA TV 清单/分片可获取，但 FFmpeg 请求返回 403；另一个 News24 样本成功解码。因此该列表是抽样通过，部分频道仍受请求环境或访问限制。其列表也含 Twitch 等网页地址，App 不提供通用网页解析。

## 新增订阅地址

- 量子资源：`https://cj.lziapi.com/api.php/provide/vod/`
- 红牛资源：`https://www.hongniuzy2.com/api.php/provide/vod/`
- 360资源：`https://360zy.com/api.php/provide/vod/`
- 无尽资源：`https://api.wujinapi.com/api.php/provide/vod/`
- IPTV-org中文：`https://iptv-org.github.io/iptv/languages/zho.m3u`
- Free-TV：`https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8`

## 升级与删除

默认配置版本升级至 2，总计 8 个 CMS 点播和 2 个直播列表。已有用户只补充本次新增的六项，保留订阅名称、身份和先前删除的旧默认源；本次新增项被删除后也不会在下次启动时重新出现。“添加缺少的默认源”仍可手动恢复所有缺失的预置源。

## 第二批补充（默认配置版本 3）

2026-10-30 从 cms-player/vod-source 再发现极速、光速、ikun、U酷、闪电五个 CMS 接口，及 iptv-org 的新闻分类列表。接口/列表、HLS 清单、媒体分片和两秒视频解码抽样均通过；实际地址及来源链接完整列于 README 的“默认资源地址与来源”。新闻列表当时含 1051 个 EXTINF 条目，不代表所有频道都可播。

飞速域名解析失败，樱花样本媒体 TLS 连接异常，YanG 的六个 HTTPS 样本返回 404；YueChan 列表当时主要为运营商 RTP 组播地址，不作为普通公网直连推荐。以上未加入默认配置。

版本 3 总计 13 个 CMS 和 3 个直播列表。版本 2 用户只补本次六项；版本 1 用户补两批新增项。保留已有订阅顺序、名称及身份，不恢复用户删除的旧源。

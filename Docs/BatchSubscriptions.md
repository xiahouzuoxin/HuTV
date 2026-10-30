# JSON 多订阅导入

入口：订阅页 → 添加（+）→ 通过 JSON 批量导入。

支持三种输入：在线 JSON 地址、粘贴 JSON、本地 JSON/文本文件。GitHub 文件页面地址（`https://github.com/owner/repo/blob/main/source.json`）会转换为 raw 地址，不能把仓库首页当作 JSON 地址。包含斜杠或特殊引用的分支建议直接提供 Raw 链接。

## 数据格式

```json
[
  {"name": "点播示例", "api": "https://example.com/api.php/provide/vod/"},
  {"name": "直播示例", "url": "https://example.com/live.m3u", "kind": "live"},
  {"name": "聚合示例", "api": "https://example.com/config.json", "kind": "tvbox"}
]
```

- 顶层必须是数组，每项是对象。`api` 与 `url` 为地址字段，优先使用 `api`；`name` 可省略，默认使用域名。
- `kind` 或 `type` 可指定 `cms`/`vod`、`live`/`m3u`/`m3u8`/`txt`、`tvbox`。数字 `1` 也按 CMS 点播处理，其他未知类型明确跳过。
- 未填类型时，地址路径以 `.m3u`、`.m3u8`、`.txt` 结尾的按直播验证，其余按 CMS 点播验证。没有扩展名的直播地址请明确写 `kind: "live"`；TVBox 配置也应明确标注类型。
- 支持 UTF-8 BOM、JSON 注释与尾逗号，不修改字符串中的 URL、转义或查询参数。
- 单次最多 200 项、5 MB。只接受 HTTP(S) 订阅；`cms://`、爬虫代码、本地文件路径不会作为网络订阅导入。

## 操作与结果

1. 输入地址、粘贴文本或选择文件，点击“读取列表”。读取这一步只下载/解析清单，不验证所有订阅接口。
2. 预览并勾选要导入的条目；不支持的项显示原因。
3. 点击“导入所选”。最多并发验证 4 个接口，按输入顺序追加成功项。每项采用和单个订阅相同的格式校验。
4. 查看添加、跳过、失败的明细。一个源失败不影响其他成功源；重复项跳过，保留既有订阅的名称、身份和排序。
5. 操作中可取消。结果尚未写入时取消，不提交本次部分条目；持久化失败时回滚本次追加。完成后可关闭结果页。

格式验证通过不代表全部媒体可播放，也不代表已取得内容授权。订阅列表可能包含失效源；工具不绕过登录、加密或网页解析限制。

兼容示例：[cms-player/vod-source/source.json](https://github.com/cms-player/vod-source/blob/main/source.json)。该清单含 `name`、`api`，部分项使用不支持的 `cms://` 协议；它们会在预览中标出，不会导致整份导入失败。第三方清单可能变化，不把其内容打包进 App。

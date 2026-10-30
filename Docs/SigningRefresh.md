# HuTV 签名到期与 Mac / Windows 刷新指南

核对日期：2026-10-30。本文提供操作方法，不代表已在你的电脑配置自动任务；本项目也没有集成、安装或验证下述第三方刷新工具。当前 HuTV 可通过 Mac 上的 Xcode 构建安装。

## 1. 为什么会过期

免费 Apple 开发者账号的开发描述文件通常签发后 7 天到期。通过电脑侧载的 App 到期可能无法启动，重新签名并覆盖安装即可恢复；已安装不等于永久有效。[Apple 账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account)

付费账号侧载通常最长约一年，实际以描述文件、证书和账号状态为准。会员续费不会自动替换 iPad 上的签名；不要把付费当成一次买断。[Sideloadly 有效期说明](https://sideloadly.io/faq.html)

“刷新签名”实际包含向 Apple 获取有效签名材料、重新签名和覆盖安装，不是修改设备时间或延长原文件日期。本文针对电脑侧载，不是 App Store 安装或 TestFlight。

## 2. 选择路线

| 路线 | 电脑 | 自动程度 | 适合情况 |
|---|---|---|---|
| Xcode 覆盖安装 | Mac | 手动；可设置日历提醒 | 不想把 Apple ID 交给第三方签名软件 |
| Sideloadly 后台刷新 | Mac / Windows | 后台程序在条件满足时自动尝试 | 接受第三方工具，希望减少每周操作 |
| AltServer + AltStore Classic | Mac / Windows | 电脑服务配合 iPad 后台刷新 | 需要在 iPad 管理多个侧载应用 |

Windows 不能直接用 Xcode 编译本项目，需要先从 Mac 获得完整 HuTV IPA，再在 Windows 签名安装。仅“打开电脑”或创建定时启动任务都不保证刷新成功，必须检查工具的成功记录和新的到期时间。

## 3. 先保住已有数据

HuTV 的订阅、搜索历史和观看进度保存在 App 容器内。覆盖安装前：

1. 不要先删除 iPad 上的 HuTV，删除 App 通常也会删除本机数据。
2. 沿用原 Apple 开发团队、原签名账号和实际 Bundle ID。仓库里的 `com.example.HuTV` 是开发占位值，不能直接拿它覆盖以前使用其他 ID 安装的版本。
3. 切换签名工具前检查其最终生成的应用标识。有些工具会追加账号标记；即使同一个 Apple ID，也可能装成另一份 App，原数据不会自动迁移。
4. 条件允许时，先在 Xcode 的 Devices and Simulators 中下载原 App 数据容器备份。已有备份应放在仓库外；订阅可能含令牌，勿公开上传。
5. 只有确认是同一 App、原数据仍可读取后，再启用长期自动刷新。遇到证书冲突，不要直接撤销整个团队的证书，这可能影响其他 App。

上述标识一致是覆盖安装的必要条件，不是跨工具迁移必然成功的保证。Sideloadly 官方也要求相同账号和 Bundle ID 以保留本机进度。[覆盖安装说明](https://sideloadly.io/faq.html)

## 4. Mac：用 Xcode 手动续期（第三方凭据暴露最少）

### 首次准备

- 安装 Xcode、XcodeGen，下载项目所需 VLC 依赖并生成工程：

```sh
./scripts/fetch-vlckit.sh
xcodegen generate
```

- Xcode → Settings → Accounts：自行登录 Apple ID。
- USB 连接 iPad，解锁并信任电脑；iPad 开启开发者模式。
- 打开 `HuTV.xcodeproj`，在 HuTV target 的 Signing & Capabilities 选择正确团队和原 Bundle ID，启用自动管理签名。修改工程长期配置时同步维护 `project.yml`，否则重新生成工程会覆盖手动设置。

### 每次刷新

1. 连接、解锁 iPad，在 Xcode 顶部选择这台真机。
2. 使用原账号、团队与 Bundle ID，Product → Run（⌘R），覆盖安装。
3. 在 iPad 打开 HuTV，检查订阅、历史和播放正常。
4. 确认使用了新的有效描述文件。若 Xcode 复用了尚未过期的文件，重新运行不一定从今天重新计满 7 天，不应仅凭安装成功判断续期天数。

建议设置每 4～5 天一次的日历提醒，每天留意剩余有效期。提醒是人工安排，不是 Apple 提供的自动签名机制。签名到期后仍可以用相同标识重装，通常不必先卸载。

### 查看本地构建的实际到期时间

以下仅解码本地 `.app` 的描述文件，不输出密码或完整描述文件。将路径换成这次安装的真机 App，模拟器 App 没有该文件：

```sh
HUTV_APP_PATH='/absolute/path/to/Debug-iphoneos/HuTV.app'
python3 - "$HUTV_APP_PATH/embedded.mobileprovision" <<'PY'
import plistlib, subprocess, sys
raw = subprocess.check_output(['security', 'cms', '-D', '-i', sys.argv[1]])
profile = plistlib.loads(raw)
print('签发时间（UTC）:', profile.get('CreationDate'))
print('到期时间（UTC）:', profile.get('ExpirationDate'))
PY
```

这里显示的是该本地构建的有效期；必须确认它就是刚安装到设备的那一份。不要把整个描述文件或账户日志发布到 GitHub。

## 5. Mac / Windows：Sideloadly 自动刷新

只从 [Sideloadly 官网](https://sideloadly.io/) 下载，具体界面和系统依赖以当前官方说明为准。它提供后台 Daemon，为已登记的 App 自动尝试续期；需要电脑能通过 USB 或局域网找到设备。[自动刷新机制](https://sideloadly.io/)

### 5.1 Mac 设置

1. 安装并打开官方 Sideloadly，USB 连接已解锁的 iPad，确认信任。
2. 若需要无线刷新，在 Finder 选择 iPad → 通用 → 勾选“接入 Wi-Fi 时显示此 iPad”，应用设置。
3. 导入完整 `HuTV.ipa`，选择这台 iPad，使用原签名 Apple ID。核对最终 Bundle ID，保留默认签名模式，不添加注入插件。
4. 在这次侧载时启用 Automatic Refresh / 自动刷新，完成第一次签名安装。只有通过 Xcode 安装过，并不会自动成为 Sideloadly 管理的任务。
5. 允许其后台刷新组件按需启动，在菜单栏检查 HuTV 已列入受管理应用。系统若提供登录项/后台活动设置，确认没有禁用相应组件。
6. 保持电脑在线、用户已登录且未睡眠；无线时与 iPad 处于可互相发现的局域网。首次测试保持 iPad 解锁亮屏。

### 5.2 Windows 设置

1. 从官网获取 Windows 安装器，按其当前要求准备 Apple 设备驱动。当前官方要求 Apple 官网版 iTunes 与 iCloud，并说明 Microsoft Store 版本存在兼容问题；不要为了本文盲目卸载现有同步软件，先查看官方兼容说明并备份。
2. USB 连接 iPad，先确认 iTunes 能识别设备，完成信任。需要无线刷新时，在 iTunes 设备摘要中开启“通过 Wi-Fi 与此 iPad 同步”。无线发现还可能依赖 Bonjour。
3. 打开 Sideloadly，导入 Mac 构建的 HuTV IPA，核对账号、设备和最终 Bundle ID，启用自动刷新后安装一次。
4. 在系统托盘确认 Daemon 正在运行、HuTV 已登记；不要被启动项管理或电源策略关闭。
5. 电脑与设备满足连接条件后，查看刷新成功记录与到期日。工具提示需要解锁或重新登录时，由本人完成操作。

Wi-Fi 同步入口及无线检测条件参见 [Sideloadly FAQ](https://sideloadly.io/faq.html)；Windows 组件下载应从 [官网依赖链接](https://sideloadly.io/) 进入，避免第三方驱动包。

### 5.3 “定时”的正确理解

优先使用工具内置后台刷新，不额外叠加模拟点击脚本。可以在登录项/启动应用中让工具启动；Windows 任务计划程序也只能用来启动官方程序，不能代替其签名流程。本文不提供未经验证的刷新命令行参数。

推荐日常安排是每天给电脑和 iPad 一段同时在线、可互相发现的时间，每隔几天检查一次到期日；不要等到第 7 天才连接。电脑关机、睡眠、未登录、设备离线或 Apple 认证要求交互时，自动流程可能中断。若要启用系统定时唤醒，按实际操作系统和硬件支持配置，并先实测，不把它当成刷新成功的保障。

### 5.4 接管新版本与已过期 App

更新 HuTV 时向同一工具重新导入新 IPA，使用原账号和应用标识，并保持自动刷新开启。只更新电脑某处的 IPA 文件不会自动更新 Daemon 已缓存的包。[更新已登记应用](https://sideloadly.io/faq.html)

若已过期，先用 USB 连接并解锁设备，通过相同工具、相同标识覆盖安装，成功后重新核对自动刷新任务；不要先卸载来“清理”。

## 6. 备选：AltServer + AltStore Classic

它也需要电脑参与，不是 iPad 完全独立自签；这里指 Classic，不是欧盟的 AltStore PAL。电脑运行 AltServer，iPad 安装 AltStore Classic 并导入 HuTV IPA；iPad 开启后台 App 刷新，电脑和 iPad 同一局域网或 USB 相连时尝试续期。[AltServer 刷新条件](https://faq.altstore.io/altstore-classic/altserver)

- Mac：[官方安装步骤](https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos)。
- Windows：[官方安装步骤及 Apple 组件要求](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)。
- 手动确认：iPad 打开 AltStore → My Apps → Refresh All，检查 HuTV 和 AltStore 自身剩余有效期。
- 免费账号的可同时安装侧载 App 数有限，AltStore 自身也占名额；后台唤醒由系统调度，不保证固定时刻执行。

若工具本身已过期，先用 AltServer 恢复 AltStore，再按官方故障排查恢复 HuTV。跨工具接管同样先核对标识和备份。此前 SideStore 已放弃并卸载；本文不需要重新安装 SideStore、LocalDevVPN 或任何配套 VPN。

## 7. Windows 所需 IPA 从哪里来

本项目代码无法直接在 Windows 本机构建 iOS 包。可以从自己信任的 Mac 构建环境导出 IPA，或让维护者提供同版本 IPA。不要把模拟器 `.app`、仅改后缀的 ZIP、缺少 VLC 的包当作 iPad 安装包。

Mac 上可生成一个供侧载工具重新签名的未签名真机 IPA；它本身不能直接安装。以下从仓库根目录执行，输出被 `.gitignore` 忽略：

```sh
./scripts/fetch-vlckit.sh
xcodegen generate
xcodebuild -project HuTV.xcodeproj -scheme HuTV \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build

# 每次使用新建目录，避免旧 Payload 混入本次打包。
mkdir -p output
HUTV_PACKAGE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/HuTV-ipa.XXXXXX")
mkdir "$HUTV_PACKAGE_DIR/Payload"
ditto 'DerivedData/Build/Products/Release-iphoneos/HuTV.app' \
  "$HUTV_PACKAGE_DIR/Payload/HuTV.app"
# 应包含 Frameworks/MobileVLCKit.framework。
test -d "$HUTV_PACKAGE_DIR/Payload/HuTV.app/Frameworks/MobileVLCKit.framework"
ditto -c -k --keepParent "$HUTV_PACKAGE_DIR/Payload" output/HuTV.ipa
```

以上命令逐步执行，任何一步失败都应停止。生成后检查 ZIP 顶层为 `Payload/HuTV.app/`，再传输到 Windows，由签名工具签名主 App 及嵌入框架。临时打包目录不含账户凭据，但有构建副本，用完可自行删除。本文未实机验证 Sideloadly 对当前 HuTV/VLC 包的接管流程，首次必须验证启动和播放。

## 8. 常见失败与检查顺序

| 表现 | 优先检查 |
|---|---|
| App 到期打不开 | 电脑 USB 覆盖安装，不先卸载；核对账号和最终应用标识 |
| 工具启动了但天数没变 | HuTV 是否登记自动刷新、是否真的成功签名安装、是否复用旧描述文件 |
| 无线找不到 iPad | 先 USB 信任；检查 Finder/iTunes 的 Wi-Fi 选项、同网段与设备发现；访客网络/AP 隔离会阻断连接 |
| 只能 USB 刷新 | 检查 Bonjour、工具局域网访问和防火墙对该程序的许可；不要直接关闭整个防火墙 |
| Apple 登录失败 | 查看完整错误码、更新官方工具、核对系统时间与账号状态；由本人完成二次验证，避免反复盲试 |
| 需要重新登录/验证码 | 自动任务不能绕过认证，手动完成后再次验证刷新 |
| 提示安装名额/App ID 限额 | 免费团队有限额；不要随意换 Bundle ID 创建更多 App ID，优先检查现有安装 |
| 多出第二个 HuTV、历史为空 | 最终 Bundle ID 或团队改变；原 App 先保留，从备份或原安装恢复，切勿继续删改 |
| 安装后立刻闪退 | 检查主 App 和 VLC 框架签名、框架是否完整；区分签名失败与播放器自身故障 |

## 9. 账号与自动化边界

第三方签名工具需要处理 Apple 登录凭据，即使作者声明密码仅发送给 Apple，也仍然需要信任其程序和更新来源。介意第三方处理主账号时，选择 Xcode 官方路径；专用 Apple ID 可以隔离其他个人数据，但换账号不能保证接管原 App 的数据。

不要把密码、验证码、会话、证书私钥或配对文件写进 README、脚本、任务计划参数或 Git。是否允许工具保存登录状态由用户自行决定；不保存时，完全无人值守可能不可行。开机启动、自动续期、证书撤销和账号权限是不同事项，不应以自动化为由关闭系统安全保护。

# HuTV 发布清单

状态：发布准备中，未提交审核。按用户要求保留默认点播接口，其授权尚未核实；这是独立的发布阻塞项，不能在审核备注中声称 App 无默认源。

## 已落地

- 设置 → 隐私与数据：内置可离线阅读的隐私说明、历史数量、带确认的搜索与观看历史清理。
- 设置页显示版本和构建号。
- App/PrivacyInfo.xcprivacy 声明本 App 的 UserDefaults 用于本 App 自身偏好（CA92.1），不跟踪、不由开发者收集数据。
- 已有 MobileVLCKit 许可与源码链接；1024 图标无透明通道。
- 隐私正文唯一来源：App/Resources/PrivacyPolicy.txt。公开发布时使用同一正文，不要另写不一致的版本。

## 提交前必须补齐

- [ ] 注册并保持有效的 Apple Developer Program 会员；确定 App Store 发布地区。
- [ ] 确定最终 Bundle ID、开发者团队及 App Store Connect 应用记录。当前 com.example.HuTV 是开发占位值，不用于正式发布。真机曾使用的开发 Bundle ID 也不应无意替换。
- [ ] 为隐私政策和技术支持提供可公开访问的 HTTPS 网页、发布者身份及有效联系渠道。内置说明不能替代 App Store Connect 的 Privacy Policy URL。把政策末尾的支持指引与实际上线渠道核对。
- [ ] 核实默认源、演示内容、海报及截图的使用授权。当前保留的默认源尚未完成此项。
- [ ] 准备获授权且稳定可播放的审核演示内容；审核可完整访问，无隐藏开关或针对审核的不同配置。
- [ ] 核实 MobileVLCKit 3.7.3 及其包含的库的许可证、对应源码可获取性、隐私 API 使用及维护状态。现有许可页不等于完整依赖合规审计。
- [ ] 使用 Archive 隐私报告检查 App 和第三方库。当前清单覆盖 App 已确认的 UserDefaults，不代表已扫描全部 VLC 二进制 API。
- [ ] 完成加密出口合规问卷。VLC 包含的加密实现需核实，不要直接写 ITSAppUsesNonExemptEncryption=false 或套用“只使用系统 HTTPS”的豁免。
- [ ] App Store 隐私标签按实际网络行为核对。无开发者后端不等于第三方媒体/图片服务器不处理数据；核实各合作方的数据用途，勿仅凭当前清单选“不收集数据”。
- [ ] 年龄分级、内容权利声明、售价、版权、支持 URL、隐私 URL、应用介绍、关键词、iPhone/iPad 实际截图。
- [ ] 审核 NSAllowsArbitraryLoads=true：当前为兼容用户导入的任意 HTTP 订阅/API/图片而保留。优先 HTTPS；评估是否可收紧为必要例外，并在提交说明中如实解释。不要只替换为媒体例外而破坏 HTTP API 获取。

## 构建与验证

当前开发环境 Xcode 26.4.1，最低系统 iOS 17；较新 SDK 构建不要求把最低系统改成 iOS 26。

1. `xcodegen generate`。
2. 运行 HuTV Scheme 的测试，覆盖订阅解析、历史持久化、播放恢复等。
3. Xcode → HuTV target → Signing：使用确认后的正式 Bundle ID 和开发者团队。同步维护 project.yml，避免工程重新生成后丢失设置。
4. 选择 Any iOS Device，Product → Archive（Release），Organizer → Validate App → Distribute App → App Store Connect。
5. 检查归档中的 PrivacyInfo.xcprivacy、PrivacyPolicy.txt、MobileVLCKit-LGPL.txt、Frameworks/MobileVLCKit.framework，生成并检查隐私报告。
6. 先内部 TestFlight：首次安装、升级、删除订阅、历史清理、失效源、无网络、缓冲重试、暂停恢复、手势、亮屏、连播、iPhone/iPad 横竖屏；VLC 与 AVPlayer 分别验证。
7. 上传和验证成功不代表审核通过；TestFlight 构建也有有效期，不能当作永久自用安装。

## 发布资料草稿

见 StoreMetadata.md。提交时逐项核对；不得把占位文字直接上传。

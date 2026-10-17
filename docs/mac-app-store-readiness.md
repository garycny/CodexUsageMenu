# Mac App Store 上架就绪度

> 审核日期：2026-09-09

## 结论

当前版本可以继续作为 Developer ID 签名、公证后的官网分发版，但不能直接提交 Mac App Store。

主要阻断项不是界面，而是当前的数据获取方式与 App Sandbox 冲突。

## 当前阻断项

1. Xcode 目标显式设置了 `ENABLE_APP_SANDBOX = NO`。Mac App Store 的 macOS App 必须使用 App Sandbox。
2. App 通过 `NSTask` 启动 `/usr/bin/env python3`。这依赖外部解释器，不符合上架版应自包含、不依赖可选技术的方向。
3. 数据读取已统一到 Codex App Server，不再读取 `~/.codex/sessions`、`~/.codex/auth.json` 或私有接口；但 helper 仍将快照写到 `~/.codex/usage-menu`，开启沙盒后需要迁移到应用容器。
4. 当前 Bundle ID 是 `local.codexusage.menubar`，签名方式是手动 ad-hoc，尚未配置 Apple Developer Team、Mac App Distribution 证书和 App Store provisioning profile。
5. 尚未准备 App Store Connect 所需的隐私政策 URL、数据处理问卷、审核说明、截图和联系方式。
6. `Codex` 和 `ChatGPT` 属于第三方品牌。上架前需确认应用名称、图标、商店文案和数据接口的使用授权，避免暗示官方关联。

## 建议的上架架构

1. 用 Objective-C/Swift 原生代码取代 Python helper，不再启动外部进程。
2. 保留当前有文档的 Codex App Server 数据链，并确认 App Store 审核环境允许发现和启动用户已安装的 Codex 运行时。
3. 如果必须读取本地文件，由用户通过 `NSOpenPanel` 选择目录，使用 user-selected file entitlement 和 security-scoped bookmark 持久化授权。
4. 启用 App Sandbox 和 Hardened Runtime，只申请必要的网络与文件权限。
5. 配置唯一的正式 Bundle ID、Developer Team、版本号、应用分类和 App Store 签名。
6. 根据实际数据收集和 Required Reason API 使用情况添加 `PrivacyInfo.xcprivacy`，并完成 App Store Connect 隐私申报。
7. 提供可审核的演示数据或演示模式，确保审核员没有本地 Codex 会话时也能看到完整功能。

## 两条发布路线

- **官网分发（当前可行）**：保留现有数据获取方式，完成 Developer ID 签名和 Apple 公证后发布。
- **Mac App Store（需要重构数据层）**：原生化 helper，重做文件/账户授权，启用沙盒，然后通过 Xcode Archive 上传 App Store Connect。

## Apple 参考

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
- [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [Adding a privacy manifest](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)

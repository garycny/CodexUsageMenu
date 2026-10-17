# 公开发布检查记录

检查日期：2026-10-17。

## 已完成

- Apache-2.0 许可证、NOTICE、中英文说明及隐私 / 安全 / 贡献指南。
- Issue / PR 模板、最小只读权限的 GitHub Actions CI。
- 微信支持页面、README 打赏入口和 `.github/FUNDING.yml`。
- 收款码仅保留二维码，中央替换为项目图标；本机识别确认与原码的收款内容一致。
- 作者确认图标与随仓库发布素材的来源和公开授权无问题。
- 真实 AppKit 面板的浅色 / 深色预览，使用虚构账户和额度数据。
- 以清理后的工作区作为独立新仓库来源，不携带旧 Git 历史或备份 refs。
- 排除本地缓存、快照、凭据、构建产物和旧安装包。

## 本地验证

- Python 回归测试：19 项通过。
- 原生快照与 helper 检查通过。
- `make app` 构建与 ad-hoc 签名严格校验通过。
- Xcode Debug scheme 已在上次清点时构建成功；CI 继续检查。

## 发布范围

首次公开以源码为主。运行应用仍需本机 Python 3.9+ 和已登录的 Codex 运行时。
本记录不代表已经签名、公证或完成另一台 Mac 的安装验证。
正式安装包需从对应提交重新构建，按[打包说明](packaging.md)签名、公证并验证。
GitHub CI 的实际状态以仓库 Actions 页面为准。

界面预览可通过以下命令重新生成，不会读取真实账户：

```bash
clang -fobjc-arc scripts/render_previews.m -framework Cocoa -o /tmp/codexusage-previews
/tmp/codexusage-previews docs/assets
```

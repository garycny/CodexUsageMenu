# 构建与发布

所有命令从仓库根目录执行。Python 3.9+ 与 Codex 运行时仍是用户机器上的前置依赖，
并未打包进应用。先阅读 README 的使用要求。

## 本机开发

```bash
make test
make native-test
make app
open "apps/CodexUsageMenuBar/.build/Codex Usage.app"
```

`make app` 为当前 Mac 架构编译，最低系统目标为 macOS 13，使用 ad-hoc 临时签名。
它适合源码开发，不能冒充已通过 Developer ID 公证的公开安装包。
`make -C apps/CodexUsageMenuBar app-zip` 可创建本机构建的 ZIP。

如果需要支持 Intel 与 Apple Silicon，请分别构建、验证并标明架构，
或通过 Xcode 的 Release 配置创建并验证通用二进制后再签名。
不要把单一架构包描述为通用版本。

## Developer ID 签名与公证

安装包版本从 `apps/CodexUsageMenuBar/Info.plist` 读取，发布前更新版本号和构建号。
需要维护者自己的 Apple Developer 证书：

- Developer ID Application：签名应用。
- Developer ID Installer：签名 PKG。
- `notarytool` 的 Keychain profile：提交公证。

查看可用证书：

```bash
make signing-info
```

不要提交证书、私钥、Apple 密码或 Keychain profile 内容。凭据由本机 Keychain 管理。
如自动发现身份不符合预期，可显式传入 `DEVELOPER_ID_APP` 和 `DEVELOPER_ID_INSTALLER`。

签名但不公证（用于可信测试）：

```bash
make release-signed
```

公开分发包：

```bash
make release NOTARY_PROFILE=codex-usage-notary
```

该命令签名应用与 PKG，提交公证，staple 并验证票据，最后运行系统安装策略检查。
只有命令成功且在另一台 Mac 验证后，才将 PKG 作为正式下载发布。

| 产物 | 路径 |
| --- | --- |
| 仅签名测试包 | `dist/Codex Usage-signed.pkg` |
| 公证安装包 | `dist/Codex Usage.pkg` |
| 公证包压缩文件 | `dist/Codex Usage.pkg.zip` |

PKG 将应用安装到 `/Applications`，安装结束会尝试为当前用户打开应用。
用户卸载时退出应用，删除 `/Applications/Codex Usage.app`，按隐私说明删除快照即可。
CI 只做测试与本机临时签名构建，不持有维护者的发布证书，也不自动发布下载包。

## 干净的源码包

```bash
make source-archive
```

生成 `dist/CodexUsage-source.tar.gz`，包含当前工作区的源码、文档、许可证和 GitHub 配置，
排除 Git 历史、已删除文件、Git 忽略项、缓存、系统资源分叉文件与构建产物。
压缩包使用中性的文件所有者信息。新加的源码也会包含，因此发布前仍需检查文件清单。

源码开源不需要 Apple 开发者证书；只有发布签名、公证的应用下载包时才需要这些证书。
GitHub Release 的自动生成源码包只包含已提交内容，与此工作区导出包不同。

## 发布前

参阅 [公开发布检查记录](release-readiness.md)，确认历史隐私、素材授权、二维码与验证结果，
再推送 / 公开仓库。不要将整个工作目录拖入 GitHub；上传这里生成的源码内容。

如已安装 Xcode 但命令行默认使用 Command Line Tools，可只为本次构建指定：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make xcode-build
```

外置卷或同步目录的 SQLite 构建缓存若提示 permission denied，可额外指定
`XCODE_DERIVED_DATA=/tmp/codexusage-xcode`，无需修改全局 Xcode 选择。

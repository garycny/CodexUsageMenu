# 贡献指南 / Contributing

欢迎提交问题和 PR。修改前先阅读 README 与快照协议，尽量让一次 PR 只解决一个问题。

## 本地验证

Python 3.9+，无第三方 Python 依赖。macOS 应用需要 macOS 13+ 和 Command Line Tools。

```bash
make test
make native-test
make app
```

修改 Xcode 工程时额外运行 `make xcode-build`。CI 使用模拟数据，不依赖维护者账户或密钥。
涉及 UI 的变更请附脱敏截图，说明 macOS 版本、浅色 / 深色模式和验证方式。

## 数据边界

- 额度只来自已安装 Codex 的 App Server；不要读取凭据、对话历史或使用私有接口。
- 缺失与不可用必须明确表示；不要估算额度、编造到期日期或把未知数据当成 0 / 100%。
- 不提交真实账户快照、日志、收款信息以外的个人数据、证书、签名凭据或构建产物。
- 修改通信、解析和失败处理时，增加能够复现问题的回归测试。

## 报告问题与提交 PR

使用 Issue 模板提供复现步骤、预期 / 实际结果和系统版本。
报错可提供 `lastError.code` 与 `lastError.stage`；不要粘贴完整账户快照。
PR 请说明问题、最终行为和实际运行的验证命令。
安全问题请按 [SECURITY.md](SECURITY.md) 私下报告。

提交贡献即表示你有权按项目的 Apache-2.0 许可证提供这些改动；不要求额外 CLA。

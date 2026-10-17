# Codex Usage Menu

A native macOS menu bar app for Codex's remaining five-hour and weekly allowances,
with reset times, automatic refresh every minute, dark mode, and optional reset-credit details.
An independent community project, not affiliated with or endorsed by OpenAI.

[中文](../README.md) · [Apache-2.0](../LICENSE) · [Privacy](../PRIVACY.md)

## Preview

<p>
  <img src="assets/panel-light.png" width="200" alt="Light mode: allowances and reset details">
  <img src="assets/panel-dark.png" width="200" alt="Dark mode: allowances and reset details">
</p>

Rendered from the actual AppKit interface using fictional data, with no real account information.

## Requirements and build

- macOS 13+, Python 3.9+ (also required by packaged apps).
- An installed Codex runtime signed in with a ChatGPT account that exposes both quota windows.
- Xcode Command Line Tools to build; Xcode 16+ for the optional Xcode project.

```bash
git clone https://github.com/garycny/CodexUsageMenu.git
cd CodexUsageMenu
make app
open "apps/CodexUsageMenuBar/.build/Codex Usage.app"
```

The development build uses ad-hoc signing. For public binaries, follow the
[Developer ID and notarization guide](packaging.md).
The interface currently uses Chinese labels alongside the quota-window names.

The menu bar percentage is the **remaining five-hour allowance**. Click it for
both windows and locally formatted reset times. Reset-credit details are optional
and display-only: this app cannot redeem credits. Missing values display `--`.
There is no automatic updater or launch-at-login setting.

## Data source

The standard-library-only Python helper starts the installed
[Codex App Server](https://learn.chatgpt.com/docs/app-server), then calls
`account/read` and `account/rateLimits/read`. It writes a local snapshot at
`~/.codex/usage-menu/usage.json` with owner-only permissions (`0600`). This file
may contain an email, display name, plan, and usage data. Do not upload it publicly.

The app does not directly read credential files or conversation history, expose
an HTTP server, or include telemetry. Codex manages authentication and remote
requests. Failed requests clear the display after one transient retry, and the UI
rejects snapshots older than three minutes. API-key accounts and unsupported
quota windows display unavailable values. See [Privacy](../PRIVACY.md).

## Development and troubleshooting

```bash
make test
make native-test
make app
make xcode-build
python3 scripts/codex_usage.py snapshot
```

The snapshot command prints account display fields. Share only sanitized error
codes and stages when reporting a problem. Confirm `python3 --version`,
`codex --version`, account sign-in, and network access first.

Use `--snapshot` or `CODEX_USAGE_SNAPSHOT_PATH` to override the snapshot location.
The native app also accepts `CODEX_USAGE_HELPER_PATH` for development.
See [Contributing](../CONTRIBUTING.md), [Snapshot schema](usage-snapshot-schema.md),
and [Support](support.md).

## Support the project

Stars, bug reports, and pull requests are welcome. You can also support maintenance
with a voluntary [WeChat Pay donation](support.md). Donations do not unlock features
or change support priority.

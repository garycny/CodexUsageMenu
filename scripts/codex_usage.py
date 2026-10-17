#!/usr/bin/env python3
"""Create a Codex usage snapshot through the official Codex App Server."""

from __future__ import annotations

import argparse
import json
import math
import os
import select
import subprocess
import tempfile
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_DIR = Path.home() / ".codex" / "usage-menu"
DEFAULT_SNAPSHOT_PATH = DEFAULT_DIR / "usage.json"
APP_SERVER_COMMAND = ["app-server", "--listen", "stdio://"]
BUNDLED_CODEX_PATHS = [
    "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
    "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
    "/Applications/ChatGPT.app/Contents/Resources/codex",
    "/Applications/Codex.app/Contents/Resources/codex",
]


def now_local() -> datetime:
    return datetime.now().astimezone()


def parse_iso(value: str) -> datetime:
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=now_local().tzinfo)
    return parsed.astimezone()


def iso(dt: datetime) -> str:
    return dt.astimezone().isoformat(timespec="seconds")


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Each writer gets its own file; account display fields stay owner-readable.
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix=f".{path.name}.", suffix=".tmp", delete=False) as output:
            tmp_path = Path(output.name)
            json.dump(payload, output, indent=2, sort_keys=True, allow_nan=False)
            output.write("\n")
        tmp_path.replace(path)
    finally:
        if tmp_path is not None:
            tmp_path.unlink(missing_ok=True)


@dataclass
class WindowUsage:
    limit: float
    used: float
    remaining: float
    reset_at: datetime
    confidence: str
    source: str

    def to_json(self) -> dict[str, Any]:
        percentage = 0.0 if self.limit <= 0 else max(0.0, min(100.0, self.remaining / self.limit * 100.0))
        return {
            "limit": round(self.limit, 3),
            "used": round(self.used, 3),
            "remaining": round(self.remaining, 3),
            "remainingPercent": round(percentage, 1),
            "resetAt": iso(self.reset_at),
            "confidence": self.confidence,
            "source": self.source,
        }


def reset_summary(five_hour: WindowUsage, weekly: WindowUsage) -> dict[str, Any]:
    return {
        "expiresAt": iso(weekly.reset_at),
        "rolling5hResetAt": iso(five_hour.reset_at),
        "weeklyResetAt": iso(weekly.reset_at),
    }


def numeric(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    try:
        result = float(value)
        return result if math.isfinite(result) else None
    except (TypeError, ValueError, OverflowError):
        return None


def find_codex_executable() -> str | None:
    path = os.environ.get("PATH", "")
    home = str(Path.home())
    fallback_paths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        f"{home}/.npm-global/bin",
        f"{home}/.local/bin",
        f"{home}/.volta/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]
    seen: set[str] = set()
    for directory in path.split(os.pathsep) + fallback_paths:
        if not directory or directory in seen:
            continue
        seen.add(directory)
        candidate = Path(directory) / "codex"
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    for candidate in BUNDLED_CODEX_PATHS:
        if Path(candidate).is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


class AppServerError(Exception):
    def __init__(self, code: str, stage: str, retryable: bool = True):
        super().__init__(f"{stage}: {code}")
        self.code = code
        self.stage = stage
        self.retryable = retryable


class AppServerRPC:
    """Frame raw pipe bytes ourselves; text read-ahead is incompatible with select."""

    def __init__(self, process: subprocess.Popen):
        self.process = process
        self.pending = bytearray()

    def send(self, message: dict[str, Any]) -> None:
        try:
            self.process.stdin.write((json.dumps(message, separators=(",", ":")) + "\n").encode())
            self.process.stdin.flush()
        except (BrokenPipeError, OSError):
            raise AppServerError("connection_closed", message["method"]) from None

    def notify(self, method: str) -> None:
        self.send({"method": method})

    def request(self, request_id: int, method: str, params: dict[str, Any] | None = None,
                timeout: float = 10.0) -> dict[str, Any]:
        message: dict[str, Any] = {"id": request_id, "method": method}
        if params is not None:
            message["params"] = params
        self.send(message)
        deadline = time.monotonic() + timeout
        while True:
            if time.monotonic() >= deadline:
                raise AppServerError("timeout", method)
            if b"\n" not in self.pending:
                try:
                    readable, _, _ = select.select(
                        [self.process.stdout], [], [], max(0, deadline - time.monotonic())
                    )
                    if not readable:
                        raise AppServerError("timeout", method)
                    chunk = os.read(self.process.stdout.fileno(), 65536)
                except OSError:
                    raise AppServerError("connection_closed", method) from None
                if not chunk:
                    raise AppServerError("connection_closed", method)
                self.pending.extend(chunk)
                continue
            line, _, rest = self.pending.partition(b"\n")
            self.pending = bytearray(rest)
            try:
                payload = json.loads(line)
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
            if not isinstance(payload, dict) or payload.get("id") != request_id:
                continue
            if payload.get("error"):
                # Keep only the numeric RPC code, never raw server messages or credentials.
                error = payload["error"]
                code = error.get("code") if isinstance(error, dict) else None
                safe_code = str(code) if isinstance(code, int) else "unknown"
                raise AppServerError(f"rpc_error_{safe_code}", method,
                                     retryable=code not in {-32600, -32601, -32602})
            result = payload.get("result")
            if not isinstance(result, dict):
                raise AppServerError("invalid_response", method, retryable=False)
            return result


def app_server_rate_limit_snapshot() -> dict[str, Any] | None:
    executable = find_codex_executable()
    if not executable:
        raise AppServerError("executable_missing", "startup", retryable=False)

    environment = os.environ.copy()
    environment.setdefault("TERM", "xterm-256color")
    try:
        process = subprocess.Popen(
            [executable] + APP_SERVER_COMMAND,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            bufsize=0,
            env=environment,
        )
    except OSError:
        raise AppServerError("start_failed", "startup") from None
    rpc = AppServerRPC(process)
    try:
        rpc.request(
            1,
            "initialize",
            {
                "clientInfo": {
                    "name": "codex_usage_menu",
                    "title": "Codex Usage Menu",
                    "version": "0.1.0",
                }
            },
        )
        rpc.notify("initialized")
        account = rpc.request(2, "account/read", {"refreshToken": False})
        if not account.get("account"):
            raise AppServerError("signed_out", "account/read", retryable=False)
        rate_limits = rpc.request(3, "account/rateLimits/read", timeout=20.0)
        snapshot = normalize_app_server_rate_limits(rate_limits)
        if not snapshot:
            raise AppServerError("invalid_response", "account/rateLimits/read", retryable=False)
        account_info = normalize_app_server_account(account)
        if snapshot and account_info:
            snapshot["account"] = account_info
        return snapshot
    finally:
        try:
            if process.stdin:
                process.stdin.close()
        except OSError:
            pass
        if process.poll() is None:
            try:
                process.terminate()
                process.wait(timeout=1)
            except OSError:
                pass
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        if process.stdout:
            process.stdout.close()


def normalize_app_server_account(payload: dict[str, Any] | None) -> dict[str, str] | None:
    if not isinstance(payload, dict) or not isinstance(payload.get("account"), dict):
        return None
    account = payload["account"]
    normalized: dict[str, str] = {}
    fields = {
        "email": account.get("email"),
        "displayName": account.get("displayName", account.get("name")),
        "planType": account.get("planType", account.get("plan_type")),
        "accountType": account.get("type"),
    }
    for key, value in fields.items():
        if isinstance(value, str) and value.strip():
            normalized[key] = value.strip()
    return normalized or None


def normalize_app_server_rate_limits(payload: dict[str, Any] | None) -> dict[str, Any] | None:
    if not isinstance(payload, dict):
        return None
    root = payload.get("rateLimits")
    by_limit_id = payload.get("rateLimitsByLimitId")
    if isinstance(by_limit_id, dict) and isinstance(by_limit_id.get("codex"), dict):
        root = by_limit_id["codex"]
    if not isinstance(root, dict):
        return None

    # Older servers omit durations. When supplied, never label an unrelated
    # window (for example a 15-minute quota) as the five-hour allowance.
    windows = [root.get("primary"), root.get("secondary")]
    durations = [window.get("windowDurationMins", window.get("window_duration_mins"))
                 if isinstance(window, dict) else None for window in windows]
    if any(duration is not None for duration in durations):
        by_duration = {numeric(duration): window for duration, window in zip(durations, windows)}
        primary = app_server_window(by_duration.get(300))
        secondary = app_server_window(by_duration.get(10080))
    else:
        primary, secondary = [app_server_window(window) for window in windows]
    if not primary or not secondary:
        return None

    low_remaining = min(primary.remaining / primary.limit, secondary.remaining / secondary.limit)
    status = "critical" if low_remaining <= 0.05 else "low" if low_remaining <= 0.2 else "ok"
    snapshot = {
        "schemaVersion": 1,
        "updatedAt": iso(now_local()),
        "status": status,
        "rolling5h": primary.to_json(),
        "weekly": secondary.to_json(),
        "resetSummary": reset_summary(primary, secondary),
        "notes": ["Actual rate-limit values read from Codex app-server."],
    }
    reset_grant = normalize_app_server_reset_credits(payload.get("rateLimitResetCredits"))
    if reset_grant is not None:
        snapshot["resetGrant"] = reset_grant
    return snapshot


def app_server_datetime(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, str):
        try:
            return parse_iso(value)
        except ValueError:
            try:
                value = float(value)
            except ValueError:
                return None
    try:
        return datetime.fromtimestamp(float(value), tz=timezone.utc).astimezone()
    except (TypeError, OSError, OverflowError, ValueError):
        return None


def normalize_app_server_reset_credits(payload: Any) -> dict[str, Any] | None:
    if not isinstance(payload, dict):
        return None

    raw_credits = payload.get("credits")
    credits: list[dict[str, Any]] = []
    if isinstance(raw_credits, list):
        for raw_credit in raw_credits:
            if not isinstance(raw_credit, dict):
                continue
            status = str(raw_credit.get("status", "available"))
            if status != "available":
                continue
            entry: dict[str, Any] = {"status": status}
            granted_at = app_server_datetime(raw_credit.get("grantedAt", raw_credit.get("granted_at")))
            expires_at = app_server_datetime(raw_credit.get("expiresAt", raw_credit.get("expires_at")))
            if granted_at is not None:
                entry["grantedAt"] = iso(granted_at)
            if expires_at is not None:
                entry["expiresAt"] = iso(expires_at)
            for source_key, target_key in (("title", "title"), ("description", "description"), ("resetType", "resetType")):
                value = raw_credit.get(source_key)
                if isinstance(value, str) and value.strip():
                    entry[target_key] = value.strip()
            credits.append(entry)

    credits.sort(key=lambda entry: parse_iso(entry["expiresAt"]).timestamp()
                 if "expiresAt" in entry else float("inf"))
    expiration_dates = [entry["expiresAt"] for entry in credits if "expiresAt" in entry]
    available_count_value = payload.get("availableCount", payload.get("available_count"))
    count = numeric(available_count_value)
    available_count = len(credits) if count is None else max(0, int(count))
    result: dict[str, Any] = {
        "availableCount": available_count,
        "credits": credits,
        "expirationDates": expiration_dates,
        "source": "codex-app-server",
    }
    if expiration_dates:
        result["expiresAt"] = expiration_dates[0]
    return result


def app_server_window(payload: Any) -> WindowUsage | None:
    if not isinstance(payload, dict):
        return None
    used_percent = numeric(payload.get("usedPercent", payload.get("used_percent")))
    resets_at = numeric(payload.get("resetsAt", payload.get("resets_at")))
    if used_percent is None or resets_at is None:
        return None
    used = max(0.0, min(100.0, used_percent))
    try:
        reset_at = datetime.fromtimestamp(resets_at, tz=timezone.utc).astimezone()
    except (OSError, OverflowError, ValueError):
        return None
    return WindowUsage(
        100.0,
        used,
        100.0 - used,
        reset_at,
        "actual",
        "codex-app-server",
    )


def unavailable_snapshot() -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "updatedAt": iso(now_local()),
        "status": "unavailable",
        "notes": [
            "Codex App Server is unavailable or no ChatGPT account is signed in.",
            "No session files, credential files, or private endpoints were used.",
        ],
    }


def build_snapshot() -> dict[str, Any]:
    """Return only App Server data; never fall back to inferred or private sources."""
    for attempt in range(2):
        try:
            return app_server_rate_limit_snapshot() or unavailable_snapshot()
        except AppServerError as error:
            if error.retryable and attempt == 0:
                time.sleep(0.5)
                continue
            snapshot = unavailable_snapshot()
            snapshot["lastError"] = {"code": error.code, "stage": error.stage}
            return snapshot
    raise AssertionError("unreachable")


def cmd_snapshot(args: argparse.Namespace) -> None:
    snapshot = build_snapshot()
    atomic_write_json(Path(args.snapshot), snapshot)
    print(json.dumps(snapshot, indent=2, sort_keys=True))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Maintain a local Codex usage snapshot.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    snapshot_parser = subparsers.add_parser("snapshot", help="Refresh and print the snapshot.")
    snapshot_parser.add_argument("--snapshot", default=os.environ.get("CODEX_USAGE_SNAPSHOT_PATH", str(DEFAULT_SNAPSHOT_PATH)))
    snapshot_parser.set_defaults(func=cmd_snapshot)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

import unittest
import io
import os
import json
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch, Mock

from scripts import codex_usage


@contextmanager
def rpc_pipe(data):
    reader, writer = os.pipe()
    with os.fdopen(reader, "rb", buffering=0) as stdout, os.fdopen(writer, "wb", buffering=0) as output:
        output.write(data)
        yield codex_usage.AppServerRPC(Mock(stdin=io.BytesIO(), stdout=stdout))


class CodexUsageTests(unittest.TestCase):
    def test_snapshot_writers_are_atomic_and_owner_readable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "usage.json"
            with ThreadPoolExecutor(max_workers=4) as executor:
                list(executor.map(lambda value: codex_usage.atomic_write_json(path, {"value": value}), range(16)))
            self.assertIn(json.loads(path.read_text())["value"], range(16))
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(list(Path(directory).iterdir()), [path])

    def test_failed_snapshot_write_preserves_previous_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "usage.json"
            codex_usage.atomic_write_json(path, {"status": "ok"})
            with self.assertRaises(ValueError):
                codex_usage.atomic_write_json(path, {"value": float("nan")})
            self.assertEqual(json.loads(path.read_text()), {"status": "ok"})
            self.assertEqual(list(Path(directory).iterdir()), [path])

    def test_invalid_usage_values_do_not_turn_into_full_allowance(self) -> None:
        for field in ("usedPercent", "resetsAt"):
            for value in ("invalid", "NaN", float("inf"), None, True):
                window = {"usedPercent": 20, "resetsAt": 1780000000, field: value}
                with self.subTest(field=field, value=value):
                    self.assertIsNone(codex_usage.app_server_window(window))

    def test_duration_selects_correct_windows_from_codex_bucket(self) -> None:
        snapshot = codex_usage.normalize_app_server_rate_limits({
            "rateLimits": {"primary": {"usedPercent": 99, "resetsAt": 1780000000}},
            "rateLimitsByLimitId": {"codex": {
                "primary": {"usedPercent": 30, "resetsAt": 1780000000, "windowDurationMins": 10080},
                "secondary": {"usedPercent": 10, "resetsAt": 1780000000, "windowDurationMins": 300},
            }},
        })
        self.assertEqual(snapshot["rolling5h"]["remainingPercent"], 90)
        self.assertEqual(snapshot["weekly"]["remainingPercent"], 70)

    def test_unrecognized_window_duration_is_unavailable(self) -> None:
        self.assertIsNone(codex_usage.normalize_app_server_rate_limits({"rateLimits": {
            "primary": {"usedPercent": 20, "resetsAt": 1780000000, "windowDurationMins": 15},
            "secondary": {"usedPercent": 10, "resetsAt": 1780000000, "windowDurationMins": 10080},
        }}))

    def test_invalid_credit_count_does_not_crash(self) -> None:
        for count in ("NaN", float("inf"), "invalid", True):
            with self.subTest(count=count):
                grant = codex_usage.normalize_app_server_reset_credits({"availableCount": count})
                self.assertEqual(grant["availableCount"], 0)

    def test_credit_expiry_sorts_by_instant_across_timezones(self) -> None:
        grant = codex_usage.normalize_app_server_reset_credits({"credits": [
            {"expiresAt": "2026-10-17T00:30:00+08:00"},
            {"expiresAt": "2026-10-16T20:00:00+00:00"},
        ]})
        self.assertLess(codex_usage.parse_iso(grant["credits"][0]["expiresAt"]),
                        codex_usage.parse_iso(grant["credits"][1]["expiresAt"]))

    def test_notifications_and_responses_in_one_pipe_read(self) -> None:
        with rpc_pipe(
            b'{"method":"account/updated"}\n'
            b'{"id":1,"result":{"ok":true}}\n'
            b'{"method":"remoteControl/status/changed"}\n'
            b'{"id":2,"result":{"next":true}}\n'
        ) as rpc:
            self.assertEqual(rpc.request(1, "first", timeout=0.2), {"ok": True})
            self.assertEqual(rpc.request(2, "second", timeout=0.2), {"next": True})

    def test_incomplete_line_obeys_timeout(self) -> None:
        with rpc_pipe(b'{"id":1,"result":') as rpc:
            started = time.monotonic()
            with self.assertRaises(codex_usage.AppServerError) as error:
                rpc.request(1, "partial", timeout=0.03)
            self.assertEqual(error.exception.code, "timeout")
            self.assertLess(time.monotonic() - started, 0.5)

    def test_rpc_error_keeps_only_safe_code(self) -> None:
        with rpc_pipe(b'{"id":1,"error":{"code":-32601,"message":"private details"}}\n') as rpc:
            with self.assertRaises(codex_usage.AppServerError) as error:
                rpc.request(1, "unsupported")
            self.assertEqual(error.exception.code, "rpc_error_-32601")
            self.assertFalse(error.exception.retryable)
            self.assertNotIn("private details", str(error.exception))

    def test_transient_failure_retries_then_recovers(self) -> None:
        expected = {"status": "ok"}
        with patch("scripts.codex_usage.app_server_rate_limit_snapshot", side_effect=[
            codex_usage.AppServerError("timeout", "account/read"), expected
        ]) as provider, patch("scripts.codex_usage.time.sleep"):
            self.assertIs(codex_usage.build_snapshot(), expected)
        self.assertEqual(provider.call_count, 2)

    def test_failed_retry_records_reason_without_stale_data(self) -> None:
        with patch("scripts.codex_usage.app_server_rate_limit_snapshot", side_effect=
                   codex_usage.AppServerError("timeout", "account/rateLimits/read")) as provider, patch(
                       "scripts.codex_usage.time.sleep"):
            snapshot = codex_usage.build_snapshot()
        self.assertEqual(provider.call_count, 2)
        self.assertEqual(snapshot["status"], "unavailable")
        self.assertEqual(snapshot["lastError"], {"code": "timeout", "stage": "account/rateLimits/read"})
        self.assertNotIn("rolling5h", snapshot)

    def test_signed_out_does_not_retry(self) -> None:
        with patch("scripts.codex_usage.app_server_rate_limit_snapshot", side_effect=
                   codex_usage.AppServerError("signed_out", "account/read", retryable=False)) as provider:
            snapshot = codex_usage.build_snapshot()
        provider.assert_called_once_with()
        self.assertEqual(snapshot["lastError"]["code"], "signed_out")

    def test_finder_launch_finds_nested_bundled_codex(self) -> None:
        bundled = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        with patch.dict("os.environ", {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin"}), patch(
            "pathlib.Path.is_file", autospec=True, side_effect=lambda path: str(path) == bundled
        ), patch("os.access", return_value=True):
            self.assertEqual(codex_usage.find_codex_executable(), bundled)

    def test_app_server_account_keeps_only_display_fields(self) -> None:
        account = codex_usage.normalize_app_server_account(
            {
                "account": {
                    "email": "hello@example.com",
                    "planType": "pro",
                    "type": "chatgpt",
                    "accountId": "must-not-be-exposed",
                }
            }
        )

        self.assertEqual(
            account,
            {
                "email": "hello@example.com",
                "planType": "pro",
                "accountType": "chatgpt",
            },
        )

    def test_app_server_snapshot_includes_reset_credit_details(self) -> None:
        primary_reset = int(datetime(2026, 9, 9, 12, 0, tzinfo=timezone.utc).timestamp())
        weekly_reset = int(datetime(2026, 9, 15, 10, 6, tzinfo=timezone.utc).timestamp())
        first_grant = int(datetime(2026, 8, 22, 0, 0, tzinfo=timezone.utc).timestamp())
        first_expiry = int(datetime(2026, 9, 21, 0, 0, tzinfo=timezone.utc).timestamp())
        second_expiry = int(datetime(2026, 10, 4, 0, 0, tzinfo=timezone.utc).timestamp())
        snapshot = codex_usage.normalize_app_server_rate_limits(
            {
                "rateLimits": {
                    "primary": {"usedPercent": 18, "resetsAt": primary_reset},
                    "secondary": {"usedPercent": 24, "resetsAt": weekly_reset},
                },
                "rateLimitResetCredits": {
                    "availableCount": 2,
                    "credits": [
                        {
                            "status": "available",
                            "grantedAt": first_grant,
                            "expiresAt": second_expiry,
                            "title": "Reset credit 2",
                        },
                        {
                            "status": "available",
                            "grantedAt": first_grant,
                            "expiresAt": first_expiry,
                            "title": "Reset credit 1",
                        },
                        {"status": "redeemed", "expiresAt": second_expiry},
                    ],
                },
            }
        )

        self.assertIsNotNone(snapshot)
        assert snapshot is not None
        self.assertEqual(snapshot["rolling5h"]["remainingPercent"], 82.0)
        self.assertEqual(snapshot["weekly"]["remainingPercent"], 76.0)
        grant = snapshot["resetGrant"]
        self.assertEqual(grant["availableCount"], 2)
        self.assertEqual(len(grant["credits"]), 2)
        self.assertLess(grant["credits"][0]["expiresAt"], grant["credits"][1]["expiresAt"])
        self.assertIn("grantedAt", grant["credits"][0])
        self.assertEqual(grant["source"], "codex-app-server")

    def test_app_server_reset_count_remains_authoritative_without_details(self) -> None:
        grant = codex_usage.normalize_app_server_reset_credits({"availableCount": 3})

        self.assertEqual(
            grant,
            {
                "availableCount": 3,
                "credits": [],
                "expirationDates": [],
                "source": "codex-app-server",
            },
        )

    def test_build_snapshot_uses_app_server_result(self) -> None:
        expected = {"schemaVersion": 1, "status": "ok"}
        with patch("scripts.codex_usage.app_server_rate_limit_snapshot", return_value=expected) as app_server:
            snapshot = codex_usage.build_snapshot()

        self.assertIs(snapshot, expected)
        app_server.assert_called_once_with()

    def test_build_snapshot_has_no_estimated_fallback(self) -> None:
        with patch("scripts.codex_usage.app_server_rate_limit_snapshot", return_value=None):
            snapshot = codex_usage.build_snapshot()

        self.assertEqual(snapshot["status"], "unavailable")
        self.assertNotIn("rolling5h", snapshot)
        self.assertNotIn("weekly", snapshot)
        self.assertIn("No session files", snapshot["notes"][1])


if __name__ == "__main__":
    unittest.main()

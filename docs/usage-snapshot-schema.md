# Usage Snapshot Schema

The menu bar app consumes one stable JSON snapshot. Providers can change later,
but the snapshot contract should stay stable.

Default path:

```text
~/.codex/usage-menu/usage.json
```

Override path:

```text
CODEX_USAGE_SNAPSHOT_PATH=/path/to/usage.json
```

Example:

```json
{
  "schemaVersion": 1,
  "updatedAt": "2026-07-10T11:58:11+08:00",
  "status": "ok",
  "account": {
    "email": "hello@example.com",
    "planType": "pro",
    "accountType": "chatgpt"
  },
  "rolling5h": {
    "limit": 100,
    "used": 38,
    "remaining": 62,
    "remainingPercent": 62,
    "resetAt": "2026-07-10T16:10:50+08:00",
    "confidence": "actual",
    "source": "codex-app-server"
  },
  "weekly": {
    "limit": 100,
    "used": 6,
    "remaining": 94,
    "remainingPercent": 94,
    "resetAt": "2026-07-17T11:10:50+08:00",
    "confidence": "actual",
    "source": "codex-app-server"
  },
  "resetSummary": {
    "expiresAt": "2026-07-17T11:10:50+08:00",
    "rolling5hResetAt": "2026-07-10T16:10:50+08:00",
    "weeklyResetAt": "2026-07-17T11:10:50+08:00"
  },
  "resetGrant": {
    "availableCount": 2,
    "expiresAt": "2026-08-01T00:00:00+08:00",
    "expirationDates": [
      "2026-08-01T00:00:00+08:00",
      "2026-08-15T00:00:00+08:00"
    ],
    "credits": [
      {
        "status": "available",
        "grantedAt": "2026-07-01T00:00:00+08:00",
        "expiresAt": "2026-08-01T00:00:00+08:00"
      },
      {
        "status": "available",
        "expiresAt": "2026-08-15T00:00:00+08:00"
      }
    ],
    "source": "codex-app-server"
  },
  "notes": [
    "Actual rate-limit values read from Codex app-server."
  ]
}
```

`resetSummary` intentionally carries reset timestamps, not a reset count. The
5-hour window is rolling, so the local record does not contain a reliable
number of remaining reset cycles.

`resetGrant` is optional. It represents the separate full-reset entitlement
shown in Codex's usage UI. `credits` contains one card-ready entry per available
reset, ordered by expiry; `grantedAt` is optional because not every provider
returns it. `expirationDates` remains as a compact compatibility representation,
and `expiresAt` is the earliest expiry. When a provider supplies only
`availableCount`, the app still shows the individual entries but labels their
expiry as unavailable rather than inventing a date.

`account` is optional and contains display-only account fields returned by the
active provider. Internal account IDs and credentials are never copied into the
snapshot.

The only supported live source is `codex-app-server`. If App Server cannot
return an authenticated account and both rate-limit windows, the helper writes
`status: "unavailable"` without `rolling5h` or `weekly`; the native UI renders
that state as `--`.

Failures include an optional `lastError` object with `code` (for example
`timeout`, `signed_out`, or `executable_missing`) and `stage` (the failing RPC
method or `startup`). Raw server error text is never stored. Transient errors
are retried once before publishing an unavailable snapshot.

The helper does not depend on private Codex caches, session files, credential
files, private backend endpoints, or inferred local estimates.

## Validation and storage

`usedPercent` and `resetsAt` must be finite numbers, not booleans or malformed
strings. A window is unavailable if either field fails validation. When window
durations are supplied, 300 and 10080 minutes select the five-hour and weekly
windows regardless of their primary/secondary order; other durations are not
relabeled. Older responses without durations retain the legacy order.

The helper prefers `rateLimitsByLimitId.codex` over `rateLimits`. Both supported
windows are required by the current UI. Reset credits remain optional.

Writes use unique temporary files and atomic replacement with mode `0600`.
There is no HTTP endpoint; use the `snapshot` command to refresh the file.
The native reader rejects unknown schema versions, missing/invalid timestamps,
snapshots older than 180 seconds or more than 60 seconds in the future. A helper
launch or exit failure overrides cached values in memory instead of showing them
as live data. Native-only diagnostic codes include `helper_missing`,
`helper_failed`, `python_missing`, and `stale_snapshot`.

Source: [Official App Server documentation](https://learn.chatgpt.com/docs/app-server).

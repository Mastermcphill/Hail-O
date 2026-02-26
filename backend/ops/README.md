# Backend Ops Runbook

## Redis Optional Mode

`REDIS_ENABLED` controls whether Redis is required at runtime.

| Mode | REDIS_ENABLED | REDIS_URL | Expected behavior |
| --- | --- | --- | --- |
| Case A (bypass) | unset or `false` | unset/any | App starts without Redis connection attempt. `/ready` can be `ok=true` with `redis_enabled=false`. |
| Case B (misconfigured) | `true` | missing/empty | Startup fails fast with `REDIS_ENABLED=true requires REDIS_URL`. |
| Case C (enabled) | `true` | valid URL | App attempts Redis connect. `/ready` requires `redis_ready=true` or returns non-ready (`503`). |

Readiness fields:

- `redis_enabled`: Redis requirement gate from config.
- `redis_configured`: whether `REDIS_URL` is present.
- `redis_ready`: runtime health result for Redis ping when enabled.

When `redis_enabled=false`, Redis is bypassed and `redis_ready` does not block readiness.

## Redis Matrix Proof Script

Run local truth-table validation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./backend/ops/redis_matrix.ps1
```

Optional flags:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./backend/ops/redis_matrix.ps1 -RedisUrl redis://127.0.0.1:6379/0
powershell -NoProfile -ExecutionPolicy Bypass -File ./backend/ops/redis_matrix.ps1 -SkipCaseC
```

Artifacts are written to:

- `backend/ops/test_artifacts/redis/<timestamp>/case_a_bypass.json`
- `backend/ops/test_artifacts/redis/<timestamp>/case_b_enabled_missing_url.json`
- `backend/ops/test_artifacts/redis/<timestamp>/case_c_enabled_with_url.json`
- `backend/ops/test_artifacts/redis/<timestamp>/summary.json`

Case C will print `SKIP` if Redis is not reachable locally. Start Redis and rerun:

```bash
docker run --rm -p 6379:6379 redis
```

# Deploy Runbook

## Staging first
1. Push to `main`.
2. Wait for `hail-o-api-staging` deploy success on Render.
3. Verify `GET /health`, `GET /healthz`, and `GET /api/healthz` return `200`.
4. Run smoke:
   - `powershell -ExecutionPolicy Bypass -File tool/smoke_backend.ps1` with `HAILO_API_BASE_URL=https://hail-o-api-staging.onrender.com`

## Promote to production
1. Confirm staging smoke is green.
2. Trigger production deploy (`hail-o-api`) from the same commit.
3. Verify:
   - `GET https://hail-o-api.onrender.com/health`
   - `GET https://hail-o-api.onrender.com/healthz`
   - `GET https://hail-o-api.onrender.com/api/healthz`
4. Run non-destructive smoke (`/health`, auth/login/read).

## Backend local compile/boot gate
Run from repo root:
```bash
bash backend/ops/compile_gate.sh
```
Expected checks:
- `dart pub get`, `dart analyze`, `dart test`
- startup log emitted exactly once:
  - `{"event":"server_listen","host":"0.0.0.0","port":<resolved>}`
- `GET /api/healthz` and `GET /healthz` return `200`
- marketplace smoke requests:
  - `GET /marketplace/offers`
  - `GET /marketplace/offers/{offerId}/paywall`

## Render UI settings
- Runtime: `Docker`
- Root Directory: `.`
- API Dockerfile path: `backend/Dockerfile`
- CI Dockerfile path: `Dockerfile.ci`
- `Start Command` and `Docker Command` overrides must stay empty (use Dockerfile `CMD`).
- If `Root Directory` is anything other than `.`, deploys will fail (missing Dockerfile/app paths).

## Required env vars
- `BACKEND_DB_MODE=postgres`
- `DATABASE_URL` (Render Postgres connection string)
- `DB_SCHEMA` (`hailo_prod` for prod, `hailo_staging` for staging)
- `JWT_SECRET`

## Security + policy env vars
- `ALLOWED_ORIGINS`:
  - Comma-separated allowlist.
  - Default empty (deny cross-origin requests unless explicitly allowed).
- `RATE_LIMIT_ENABLED`:
  - Default `true`.
- `RATE_LIMIT_WINDOW_SECONDS`:
  - Default `60`.
- `RATE_LIMIT_WINDOW_SEC`:
  - Short alias of `RATE_LIMIT_WINDOW_SECONDS`.
- `RATE_LIMIT_PER_IP_PER_MIN`:
  - Default `60` (preferred key, aliases to `RATE_LIMIT_MAX_REQUESTS_PER_IP`).
- `RATE_LIMIT_PER_USER_PER_MIN`:
  - Default `120` (preferred key, aliases to `RATE_LIMIT_MAX_REQUESTS_PER_USER`).
- `RATE_LIMIT_MAX_REQUESTS_PER_IP`:
  - Legacy alias of `RATE_LIMIT_PER_IP_PER_MIN`.
- `RATE_LIMIT_MAX_REQUESTS_PER_USER`:
  - Legacy alias of `RATE_LIMIT_PER_USER_PER_MIN`.
- `RATE_LIMIT_AUTH_PER_IP_PER_MIN`:
  - Default `20` for `/auth/*`.
- `RATE_LIMIT_BURST`:
  - Alias for `RATE_LIMIT_AUTH_PER_IP_PER_MIN`.
- `RATE_LIMIT_AUTH_PER_USER_PER_MIN`:
  - Default `40` for `/auth/*`.
- `TRUST_PROXY_HEADERS`:
  - Default `true`. Uses `X-Forwarded-For` first-hop, then `X-Real-IP`, then remote socket.
- `METRICS_PUBLIC`:
  - Default `false` (metrics endpoint requires admin auth).
- `DB_POOL_SIZE`:
  - Default `4`.
- `DB_QUERY_TIMEOUT_MS`:
  - Default `10000`.
- `REQUEST_IDLE_TIMEOUT_SECONDS`:
  - Default `30`.
- `REQUEST_MAX_BODY_BYTES`:
  - Default `262144` (256 KiB).

## Render log markers
- Startup contract:
  - exactly one `server_listen` line with `host=0.0.0.0` and resolved `PORT`
- Optional startup self-check:
  - `{"event":"bind_check_ok","path":"/api/healthz","port":...}`
- Noise control:
  - repeated `/healthz` and `/api/healthz` probes are intentionally suppressed from request logs

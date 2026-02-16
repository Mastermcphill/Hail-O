# Deploy Runbook

## Staging first
1. Push to `main`.
2. Wait for `hail-o-api-staging` deploy success on Render.
3. Verify `GET /health` returns `ok: true`.
4. Run smoke:
   - `powershell -ExecutionPolicy Bypass -File tool/smoke_backend.ps1` with `HAILO_API_BASE_URL=https://hail-o-api-staging.onrender.com`

## Promote to production
1. Confirm staging smoke is green.
2. Trigger production deploy (`hail-o-api`) from the same commit.
3. Verify `GET https://hail-o-api.onrender.com/health`.
4. Run non-destructive smoke (`/health`, auth/login/read).

## Render UI settings
- Runtime: `Docker`
- Root Directory: `.`
- API Dockerfile path: `backend/Dockerfile`
- CI Dockerfile path: `Dockerfile.ci`
- `Start Command` and `Docker Command` overrides must stay empty (use Dockerfile `CMD`).

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
- `RATE_LIMIT_AUTH_PER_USER_PER_MIN`:
  - Default `40` for `/auth/*`.
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

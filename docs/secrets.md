# Secrets Runbook

## JWT secret rotation
1. Generate a new random secret.
2. Set `JWT_SECRET` on staging first.
3. Deploy staging and validate auth smoke.
4. Set `JWT_SECRET` on production.
5. Deploy production and re-run smoke.

## Operational guidance
- Do not log secrets (`JWT_SECRET`, `DATABASE_URL`, bearer tokens).
- Use separate secrets per environment (staging/prod).
- Rotate secrets on suspected leakage or scheduled cadence.

## Required runtime env vars
- `JWT_SECRET`
- `DATABASE_URL` (Render-managed Postgres URL)
- `BACKEND_DB_MODE` (`postgres` in staging/prod)
- `DB_SCHEMA` (`hailo_staging` or `hailo_prod`)

## Security and policy env vars
- `ALLOWED_ORIGINS` (default deny-all when unset)
- `RATE_LIMIT_ENABLED` (default `true`)
- `RATE_LIMIT_PER_IP_PER_MIN` (preferred) or `RATE_LIMIT_MAX_REQUESTS_PER_IP`
- `RATE_LIMIT_PER_USER_PER_MIN` (preferred) or `RATE_LIMIT_MAX_REQUESTS_PER_USER`
- `RATE_LIMIT_AUTH_PER_IP_PER_MIN` (default `20`)
- `RATE_LIMIT_AUTH_PER_USER_PER_MIN` (default `40`)
- `METRICS_PUBLIC` (default `false`)

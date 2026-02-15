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

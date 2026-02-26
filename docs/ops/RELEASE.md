# Release Flow (Staging -> Production)

This document defines the minimum safe release flow for backend + app loop features.

## Goals
- Deploy only verified artifacts.
- Require staging pass before production release.
- Keep rollback path explicit.

## Prerequisites
- Render services healthy for staging and production.
- Required env vars set for target environment (see `docs/ops/ENV_KEYS.md`).
- Database credentials/migration access available.
- Admin emergency token stored in secure vault (not in repo).

## High-Level Sequence
1. Merge to `main`.
2. Deploy to staging.
3. Run release gate against staging:
   - readiness check (`/ready` once available),
   - migration safety checks,
   - end-to-end smoke (`backend/ops/smoke_e2e.*`).
4. If staging gate passes, promote/deploy same commit to production.
5. Run production smoke subset (safe, non-destructive).
6. Monitor metrics/logs/errors during soak window.

## Commands (Planned)
- Staging gate:
  - `bash backend/ops/release_gate.sh --env=staging --base=https://<staging>`
  - `powershell -ExecutionPolicy Bypass -File backend/ops/release_gate.ps1 -Env staging -BaseUrl https://<staging>`
- Production gate:
  - `bash backend/ops/release_gate.sh --env=prod --base=https://<prod>`
  - `powershell -ExecutionPolicy Bypass -File backend/ops/release_gate.ps1 -Env prod -BaseUrl https://<prod>`

## Required Checks Per Release
- Contract/fixture checks pass.
- Backend test suite passes.
- Migration index assertions pass.
- Smoke artifacts generated and stored under `backend/ops/test_artifacts/`.
- No secret exposure in logs/artifacts.

## Rollback
- Revert traffic to previous Render deploy.
- If a migration is non-reversible, apply forward-fix migration.
- Re-run smoke on rolled-back version.

## Secrets Rotation
- Rotate `PAYSTACK_SECRET_KEY` and webhook secrets on schedule and after incidents.
- Rotate `JWT_SECRET` and `ADMIN_TOKEN` under incident response policy.
- Verify rotated secrets via staging smoke before prod rollout.

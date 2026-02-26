# Release Flow (Staging -> Production)

This document defines the enforced release-gate flow for backend shipping.

## Gate Scripts
- Bash: `backend/ops/release_gate.sh`
- PowerShell: `backend/ops/release_gate.ps1`
- Smoke (Bash): `backend/ops/smoke_e2e.sh`
- Smoke (PowerShell): `backend/ops/smoke_e2e.ps1`

Both scripts perform:
1. Required env key checks (production is stricter).
2. `/ready` readiness checks on target (and staging for prod gates).
3. Migration-head consistency checks from readiness payload.
4. End-to-end smoke execution via `backend/ops/smoke_e2e.*`.

Successful run ends with:
- `RELEASE GATE: PASS`

## Staging Gate
Use this before any production promotion:

- Bash
  - `bash backend/ops/release_gate.sh --env=staging --base=https://<staging>`
- PowerShell
  - `powershell -ExecutionPolicy Bypass -File backend/ops/release_gate.ps1 -EnvName staging -BaseUrl https://<staging>`

## Production Gate
Production gate validates prod readiness and runs smoke against staging:

- Bash
  - `bash backend/ops/release_gate.sh --env=prod --base=https://<prod> --base-staging=https://<staging>`
- PowerShell
  - `powershell -ExecutionPolicy Bypass -File backend/ops/release_gate.ps1 -EnvName prod -BaseUrl https://<prod> -BaseStaging https://<staging>`

Optional strict commit parity:
- Bash: `--require-parity=true`
- PowerShell: `-RequireParity`

Optional migration-head assertion:
- Bash: `--required-migration-head=<number>`
- PowerShell: `-RequiredMigrationHead <number>`

## Smoke Artifacts
- Smoke writes artifacts to:
  - `backend/ops/test_artifacts/e2e/<timestamp>/`
- Gate consumes smoke exit code and keeps generated artifact files for debugging.
- Artifact contract:
  - `01_health.json`
  - `02_ready.json`
  - `03_auth.json` (or `03_auth_skipped.json` when OTP input is required)
  - `04_offers.json`
  - `05_purchase_create.json`
  - `06_intent_create.json`
  - `07_webhook_sim.json` (staging/test mode only, otherwise skipped)
  - `08_purchase_poll.json`
  - `09_quote.json`
  - `10_trip_create.json`
  - `11_trip_status_flow.json`
  - `12_admin_metrics.json`
  - `summary.json`

## Run Smoke Locally
- Bash:
  - `bash backend/ops/smoke_e2e.sh --env=staging --smoke-access-token=<jwt>`
  - `bash backend/ops/smoke_e2e.sh --env=staging --admin-token-enabled=true --admin-token=<token> --smoke-mint-path=/admin/smoke/mint_token`
  - `bash backend/ops/smoke_e2e.sh --env=staging --smoke-phone=<e164> --smoke-otp=<code>`
- PowerShell:
  - `powershell -ExecutionPolicy Bypass -File backend/ops/smoke_e2e.ps1 -EnvName staging -SmokeAccessToken <jwt>`
  - `powershell -ExecutionPolicy Bypass -File backend/ops/smoke_e2e.ps1 -EnvName staging -AdminTokenEnabled true -AdminToken <token> -SmokeMintPath /admin/smoke/mint_token`
  - `powershell -ExecutionPolicy Bypass -File backend/ops/smoke_e2e.ps1 -EnvName staging -SmokePhoneE164 <e164> -SmokeOtpCode <code>`
- Base URL defaults to `https://hail-o-api-staging.onrender.com` when `BASE_URL` / `-BaseUrl` is not set.
- If OTP code is omitted after request, smoke exits with code `2` and writes `03_auth_skipped.json`.
- Dry-run mode (CI helper):
  - Bash: `bash backend/ops/smoke_e2e.sh --base=https://example.invalid --dry-run`
  - PowerShell: `powershell -ExecutionPolicy Bypass -File backend/ops/smoke_e2e.ps1 -BaseUrl https://example.invalid -DryRun`

## Render Usage
- Configure release command or deploy hook to run:
  - staging: `bash backend/ops/release_gate.sh --env=staging --base=https://<staging>`
  - production: `bash backend/ops/release_gate.sh --env=prod --base=https://<prod> --base-staging=https://<staging>`
- Ensure one auth path is configured for smoke:
  - `SMOKE_ACCESS_TOKEN` (preferred), or
  - `ADMIN_TOKEN_ENABLED=true` + `ADMIN_TOKEN` + `SMOKE_MINT_PATH=/admin/smoke/mint_token`, or
  - `SMOKE_PHONE_E164` + `SMOKE_OTP_CODE` (staging/dev OTP path)
- Mint endpoint guidance:
  - `POST /admin/smoke/mint_token` is staging/non-production only.
  - It requires `ADMIN_TOKEN_ENABLED=true` and a valid `ADMIN_TOKEN`.
  - It is rejected in production by design.
- Optional:
  - `SMOKE_WEBHOOK_SIM=true` enables simulated webhook step in non-production smoke.

## Required Runtime Env
See `docs/ops/ENV_KEYS.md` for full inventory. At minimum, release gate expects:
- Staging:
  - `JWT_SECRET`
  - `PAYMENTS_PROVIDER` or `PAYMENT_PROVIDER`
  - For smoke auth: `SMOKE_ACCESS_TOKEN`, or (`SMOKE_PHONE_E164` + `SMOKE_OTP_CODE`), or admin mint flow (`ADMIN_TOKEN_ENABLED=true`, `ADMIN_TOKEN`, optional `SMOKE_MINT_PATH`)
- Production (stricter):
  - staging requirements, plus
  - `OTP_PROVIDER`
  - `PAYSTACK_SECRET_KEY`
  - `PAYSTACK_WEBHOOK_SECRET`
  - `PAYMENTS_WEBHOOK_SECRET`
  - `BASE_STAGING` (or pass `--base-staging`)

## Recommended Sequence
1. Merge and deploy candidate commit to staging.
2. Run staging release gate.
3. Promote the same commit to production.
4. Run production release gate.
5. Monitor logs, metrics, webhook backlog, and audit trails during soak.

## Flutter Build Isolation
Use `ENV` to isolate app runtime targets:

- Staging run:
  - `flutter run --dart-define=ENV=staging`
- Production build:
  - `flutter build apk --dart-define=ENV=production --obfuscate --split-debug-info=build/debug-info`

Notes:
- Do not ship production builds with staging base URLs.
- Keep test/smoke toggles disabled in production builds.

## Rollback
1. Route traffic to previous stable deploy.
2. If schema changes are irreversible, apply a forward-fix migration.
3. Re-run staging gate before re-promoting.

## Secret Rotation
Rotate and validate via staging gate before production:
- `PAYSTACK_SECRET_KEY`
- `PAYSTACK_WEBHOOK_SECRET`
- `PAYMENTS_WEBHOOK_SECRET`
- `JWT_SECRET`
- `ADMIN_TOKEN`

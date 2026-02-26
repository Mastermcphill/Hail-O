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
  - `bash backend/ops/release_gate.sh --env=prod --base=https://<prod> --staging-base=https://<staging>`
- PowerShell
  - `powershell -ExecutionPolicy Bypass -File backend/ops/release_gate.ps1 -EnvName prod -BaseUrl https://<prod> -StagingBaseUrl https://<staging>`

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
  - `step_01_health.json`
  - `step_02_ready.json`
  - `step_03_auth.json`
  - `step_04_offers.json`
  - `step_05_purchase_create.json`
  - `step_06_intent_create.json`
  - `step_07_webhook_sim.json` (staging/test mode only, otherwise skipped)
  - `step_08_purchase_get.json`
  - `step_09_quote.json`
  - `step_10_trip_create.json`
  - `step_11_trip_status.json`
  - `step_12_admin_metrics.json`
  - `summary.json`

## Run Smoke Locally
- Bash:
  - `bash backend/ops/smoke_e2e.sh --base=https://<staging> --env=staging --admin-token=<token> --admin-token-enabled=true --test-phone=<e164> --test-otp=<code> --payments-test-mode=true`
- PowerShell:
  - `powershell -ExecutionPolicy Bypass -File backend/ops/smoke_e2e.ps1 -BaseUrl https://<staging> -EnvName staging -AdminToken <token> -AdminTokenEnabled true -TestPhoneE164 <e164> -TestOtp <code> -PaymentsTestMode true`
- Dry-run mode (CI helper):
  - Bash: `bash backend/ops/smoke_e2e.sh --base=https://example.invalid --dry-run`
  - PowerShell: `powershell -ExecutionPolicy Bypass -File backend/ops/smoke_e2e.ps1 -BaseUrl https://example.invalid -DryRun`

## Render Usage
- Configure release command or deploy hook to run:
  - staging: `bash backend/ops/release_gate.sh --env=staging --base=https://<staging>`
  - production: `bash backend/ops/release_gate.sh --env=prod --base=https://<prod> --staging-base=https://<staging>`
- Ensure one auth path is configured for smoke:
  - `TEST_ACCESS_TOKEN` (preferred), or
  - `TEST_PHONE_E164` + `TEST_OTP` (staging/dev OTP path)
- Optional:
  - `PAYMENTS_TEST_MODE=true` enables simulated webhook step in non-production smoke.

## Required Runtime Env
See `docs/ops/ENV_KEYS.md` for full inventory. At minimum, release gate expects:
- Staging:
  - `JWT_SECRET`
  - `PAYMENTS_PROVIDER` or `PAYMENT_PROVIDER`
  - `ADMIN_TOKEN_ENABLED=true` (when using admin-token smoke path)
  - `E2E_ADMIN_TOKEN` or `ADMIN_TOKEN`
  - `E2E_ACCESS_TOKEN` OR (`E2E_PHONE_E164` + `E2E_OTP_CODE`)
- Production (stricter):
  - staging requirements, plus
  - `OTP_PROVIDER`
  - `PAYSTACK_SECRET_KEY`
  - `PAYSTACK_WEBHOOK_SECRET`
  - `PAYMENTS_WEBHOOK_SECRET`
  - `STAGING_BASE_URL` (or pass `--staging-base`)

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

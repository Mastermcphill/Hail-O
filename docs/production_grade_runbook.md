# Production Grade Runbook

## Purpose
This runbook is the operational source of truth for running, validating, and releasing HAIL-O across local, staging, and production.

## Local Dev Boot
### Flutter app
```powershell
flutter pub get
flutter run --flavor dev
```

### Backend API (local)
```powershell
Set-Location backend
dart pub get
dart run main.dart
```

### Full stack (from repo root)
1. Start backend (`backend/main.dart`) on `:8080`.
2. Start Flutter app with one of the runtime defines documented below.

### Single-command local boot
```powershell
powershell -ExecutionPolicy Bypass -File tool/dev_boot.ps1
```
Optional backend-only:
```powershell
powershell -ExecutionPolicy Bypass -File tool/dev_boot.ps1 -BackendOnly
```

## Base URL Rules
### Emulator/simulator
- Android emulator: `http://10.0.2.2:8080`
- iOS simulator: `http://localhost:8080`

### Physical device
Use LAN IP override:
```powershell
flutter run --dart-define=HAILO_BASE_URL=http://192.168.x.x:8080
```

## Runtime Flags
### Flutter runtime flags
- `HAILO_ENV=dev|staging|prod`
- `HAILO_BASE_URL=<absolute_url>`
- `HAILO_USE_PROD=true|false` (legacy override)
- `HAILO_MOCK_MODE=true|false`
- `HAILO_RELEASE=<semantic_or_ci_release>`
- `HAILO_COMMIT_SHA=<git_sha>`
- `SENTRY_DSN=<dsn>`
- `HAILO_ENABLE_SENTRY_SMOKE=true|false` (show Sentry smoke controls in About for non-prod)
- `HAILO_ALLOW_RELEASE_DEV=true|false` (release guard override; keep `false` for real launch)
- `HAILO_ALLOW_INSECURE_RELEASE_BASE_URL=true|false` (release guard override; keep `false` for real launch)

### Flavor defaults
- `flutter run --flavor dev` -> development base URL strategy.
- `flutter run --flavor staging` -> staging base URL strategy.
- `flutter run --flavor prod` -> production base URL strategy.

### Backend runtime flags
- `ENV=development|staging|production`
- `BACKEND_DB_MODE=sqlite|postgres`
- `DATABASE_URL=<postgres_url>` (required in postgres mode)
- `DB_SCHEMA=<schema>`
- `JWT_SECRET=<secret>`
- `ALLOWED_ORIGINS=<comma-separated-origins>`
- `SENTRY_DSN=<dsn>`
- `ADMIN_ENABLE_SENTRY_SMOKE_ENDPOINT=true|false` (staging-only admin Sentry smoke endpoint)

## Admin Seeding
Enable admin bootstrap for local/staging and register an admin user once:

```powershell
# Terminal 1 (backend)
$env:HAILO_ALLOW_ADMIN_BOOTSTRAP='true'
Set-Location backend
dart run main.dart
```

```powershell
# Terminal 2 (request)
$body = @{
  email = 'admin@hailo.local'
  password = 'ChangeMe123!'
  role = 'admin'
} | ConvertTo-Json

Invoke-RestMethod `
  -Method POST `
  -Uri 'http://localhost:8080/auth/register' `
  -Headers @{ 'Content-Type'='application/json'; 'Idempotency-Key'='seed-admin-1' } `
  -Body $body
```

## Common Troubleshooting
### Render cold start
- Symptom: first request times out after deploy/sleep.
- Action:
1. Hit `GET /healthz` once.
2. Check app banner for `Waking server...`.
3. Retry the user action after warmup.

### Request timeouts
- Confirm `HAILO_BASE_URL` is reachable from device.
- Validate backend responds on `/health` and `/api/healthz`.
- Check request-id in logs and diagnostics screen.

### Auth issues
- Confirm token exists in secure storage and role is normalized.
- Check redirect path and `next` query in URL.
- Clear session and retry (`logout` from app bar).

## Release Build Commands
### Android
```powershell
flutter run --flavor dev
flutter run --flavor staging
flutter build apk --flavor prod --dart-define=HAILO_ENV=prod --dart-define=HAILO_USE_PROD=true
flutter build appbundle --flavor prod --dart-define=HAILO_ENV=prod --dart-define=HAILO_USE_PROD=true
flutter build appbundle --flavor prod --dart-define=HAILO_ENV=prod --split-debug-info=build/symbols/android
```

### iOS
```powershell
flutter run --flavor dev
flutter run --flavor staging
flutter build ios --flavor prod --dart-define=HAILO_ENV=prod --dart-define=HAILO_USE_PROD=true
flutter build ipa --flavor prod --dart-define=HAILO_ENV=prod --split-debug-info=build/symbols/ios
```

## Verification Commands (Windows)
```powershell
dart format lib test backend
flutter analyze
flutter test
Set-Location backend; dart analyze; dart test; Set-Location ..
```

## Go-Live Gate (Windows)
Run a single readiness gate against staging:
```powershell
$env:ENV='staging'
$env:HAILO_ENV='staging'
$env:HAILO_API_BASE_URL='https://hail-o-api-staging.onrender.com'
$env:HAILO_STAGING_DATABASE_URL='<staging-postgres-url>'
$env:JWT_SECRET='<staging-jwt-secret>'
$env:ALLOWED_ORIGINS='https://app.hailo.dev,https://admin.hailo.dev'
$env:SENTRY_DSN='<staging-sentry-dsn>'
powershell -ExecutionPolicy Bypass -File tool/go_live_check.ps1 -Environment staging
```

Run production smoke gate (explicit opt-in):
```powershell
$env:ENV='production'
$env:HAILO_ENV='prod'
$env:HAILO_API_BASE_URL='https://hail-o-api.onrender.com'
$env:JWT_SECRET='<prod-jwt-secret>'
$env:ALLOWED_ORIGINS='https://app.hailo.dev,https://admin.hailo.dev'
$env:SENTRY_DSN='<prod-sentry-dsn>'
$env:HAILO_ALLOW_PROD_SMOKE='1'
powershell -ExecutionPolicy Bypass -File tool/go_live_check.ps1 -Environment production -SkipReleaseGate
```

To enforce backend Sentry drill during smoke:
```powershell
$env:ADMIN_ENABLE_SENTRY_SMOKE_ENDPOINT='true'
$env:HAILO_ADMIN_EMAIL='<admin-email>'
$env:HAILO_ADMIN_PASSWORD='<admin-password>'
$env:HAILO_RUN_SENTRY_SMOKE='1'
```

## Phase Notes
- Phase 0 complete: Added production runbook/checklist/docs hygiene and contribution standards.
- Phase 1 complete: Added Provider-based `AuthSession`, sync GoRouter redirect gating, `/boot` startup route, and `next` post-login return handling.
- Phase 2 complete: Added API policy-driven retry/timeouts, unified API error envelope mapping, redacted request logging, and non-blocking server warmup banner.
- Phase 3 complete: Added a shared brand theme, reusable loading/empty/error UI states, accessibility labels on auth entry points, and a new About/Diagnostics settings screen.
- Phase 4 complete: Added flavor-aware API environment resolution, Android product flavors, iOS shared flavor schemes, and branded launcher/splash asset generation.
- Phase 5 complete: Added Sentry initialization in Flutter and backend, request-id breadcrumbs/tags, JSON request-id log enrichment, and PII scrubbing for outgoing client events.
- Phase 6 complete: Added fast timeout-bounded `/health`, new `/version` and `/api/version` endpoints, strict staging/prod config validation, and tighter auth rate-limit defaults.
- Phase 7 complete: Added PR CI gates (`flutter analyze`, Flutter tests with coverage threshold, backend analyze/tests) and expanded auth/routing/error/validation test coverage.
- Phase 8 complete: Added formal threat model documentation, one-page production readiness summary, and final checklist pass updates for launch review.
- Phase 0 refresh complete: Added environment matrix docs, single-command local boot script, and explicit admin seeding + symbolicated release instructions.
- Phase 3 refresh complete: Added app-wide offline connectivity banner and Flutter localization scaffolding (`en`) to harden production UX behavior.
- Phase 5 refresh complete: Stabilized widget bootstrap tests by allowing startup warmup tasks to be disabled in test mode.
- Audit hardening complete: Commission settlement now enforces escrow-distribution bounds and ride booking normalizes fare fields from pricing output to resist client-side fare tampering.
- Audit extension complete: Added authenticated `/me` and `/routes` API coverage, persisted `/rides` offers/paywall/seats flows, rider cross-border document gating UI, and backend+widget tests for the new production paths.
- Go-live hardening complete: Added release startup guardrails (env/base-url/release/sentry checks), optional admin Sentry smoke endpoint + smoke-script drill support, and a consolidated `tool/go_live_check.ps1` release-readiness gate.

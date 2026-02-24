# Production Grade Runbook

## Purpose
This runbook is the operational source of truth for running, validating, and releasing HAIL-O across local, staging, and production.

## Local Dev Boot
### Flutter app
```powershell
flutter pub get
flutter run
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

### Backend runtime flags
- `ENV=development|staging|production`
- `BACKEND_DB_MODE=sqlite|postgres`
- `DATABASE_URL=<postgres_url>` (required in postgres mode)
- `DB_SCHEMA=<schema>`
- `JWT_SECRET=<secret>`
- `ALLOWED_ORIGINS=<comma-separated-origins>`
- `SENTRY_DSN=<dsn>`

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
flutter build apk --flavor prod --dart-define=HAILO_ENV=prod --dart-define=HAILO_USE_PROD=true
flutter build appbundle --flavor prod --dart-define=HAILO_ENV=prod --dart-define=HAILO_USE_PROD=true
```

### iOS
```powershell
flutter build ios --flavor prod --dart-define=HAILO_ENV=prod --dart-define=HAILO_USE_PROD=true
```

## Verification Commands (Windows)
```powershell
dart format lib test backend
flutter analyze
flutter test
Set-Location backend; dart analyze; dart test; Set-Location ..
```

## Phase Notes
- Phase 0 complete: Added production runbook/checklist/docs hygiene and contribution standards.
- Phase 1 complete: Added Provider-based `AuthSession`, sync GoRouter redirect gating, `/boot` startup route, and `next` post-login return handling.
- Phase 2 complete: Added API policy-driven retry/timeouts, unified API error envelope mapping, redacted request logging, and non-blocking server warmup banner.

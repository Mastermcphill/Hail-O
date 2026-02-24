# Environment Matrix

## Overview
This matrix is the source of truth for runtime environments and endpoint behavior.

| Environment | App Flavor | Expected Backend | Base URL Strategy | Notes |
| --- | --- | --- | --- | --- |
| `dev` | `dev` | Local backend (`dart run backend/main.dart`) | Android emulator: `http://10.0.2.2:8080`, iOS simulator: `http://localhost:8080`, physical device: `HAILO_BASE_URL` override | Default local development workflow |
| `staging` | `staging` | Render staging service | Auto from `HAILO_ENV=staging` unless `HAILO_BASE_URL` override is provided | Use staging secrets and Sentry project |
| `prod` | `prod` | Render production service | Auto from `HAILO_ENV=prod` unless `HAILO_BASE_URL` override is provided | Production-only credentials and strict CORS |

## Required Defines / Environment Variables
- Flutter: `HAILO_ENV`, `HAILO_BASE_URL` (optional override), `SENTRY_DSN`, `HAILO_RELEASE`, `HAILO_COMMIT_SHA`
- Backend: `ENV`, `BACKEND_DB_MODE`, `DATABASE_URL` (postgres), `JWT_SECRET`, `ALLOWED_ORIGINS`, `SENTRY_DSN`

## Typical Commands
```powershell
# Dev
flutter run --flavor dev

# Staging
flutter run --flavor staging --dart-define=HAILO_ENV=staging

# Prod smoke
flutter run --flavor prod --dart-define=HAILO_ENV=prod --dart-define=HAILO_USE_PROD=true
```

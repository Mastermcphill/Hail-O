# Smoke Guide

## Backend smoke scripts
- PowerShell: `tool/smoke_backend.ps1`
- Bash: `tool/smoke_backend.sh`

## Defaults and safeguards
- Default target is staging.
- Production smoke requires `HAILO_ALLOW_PROD_SMOKE=1`.
- Admin flow is optional and enabled only when `HAILO_ADMIN_EMAIL` and `HAILO_ADMIN_PASSWORD` are set.
- Backend Sentry drill is optional and enforced when `HAILO_RUN_SENTRY_SMOKE=1`.
  - Requires `ADMIN_ENABLE_SENTRY_SMOKE_ENDPOINT=true` on backend.
  - Requires admin credentials (`HAILO_ADMIN_EMAIL`, `HAILO_ADMIN_PASSWORD`).
- Route policy: `/api/*` is canonical; root `/marketplace/*` remains compatibility-only and may be deprecated.

## Typical commands
- Staging (PowerShell):
  - `$env:HAILO_API_BASE_URL='https://hail-o-api-staging.onrender.com'; powershell -ExecutionPolicy Bypass -File tool/smoke_backend.ps1`
- Staging load smoke (PowerShell):
  - `$env:HAILO_API_BASE_URL='https://hail-o-api-staging.onrender.com'; powershell -ExecutionPolicy Bypass -File tool/load_smoke.ps1`
- Staging smoke with Sentry drill (PowerShell):
  - `$env:HAILO_API_BASE_URL='https://hail-o-api-staging.onrender.com'; $env:HAILO_ADMIN_EMAIL='<admin-email>'; $env:HAILO_ADMIN_PASSWORD='<admin-password>'; $env:HAILO_RUN_SENTRY_SMOKE='1'; powershell -ExecutionPolicy Bypass -File tool/smoke_backend.ps1`

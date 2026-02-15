# Smoke Guide

## Backend smoke scripts
- PowerShell: `tool/smoke_backend.ps1`
- Bash: `tool/smoke_backend.sh`

## Defaults and safeguards
- Default target is staging.
- Production smoke requires `HAILO_ALLOW_PROD_SMOKE=1`.
- Admin flow is optional and enabled only when `HAILO_ADMIN_EMAIL` and `HAILO_ADMIN_PASSWORD` are set.

## Typical commands
- Staging (PowerShell):
  - `$env:HAILO_API_BASE_URL='https://hail-o-api-staging.onrender.com'; powershell -ExecutionPolicy Bypass -File tool/smoke_backend.ps1`
- Staging load smoke (PowerShell):
  - `$env:HAILO_API_BASE_URL='https://hail-o-api-staging.onrender.com'; powershell -ExecutionPolicy Bypass -File tool/load_smoke.ps1`

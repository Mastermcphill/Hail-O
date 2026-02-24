# Production Launch Checklist

## Pre-merge
- [x] `flutter analyze` passes
- [x] `flutter test` passes
- [x] `backend` analyzer/tests pass
- [ ] CI checks are green on PR
- [ ] `tool/go_live_check.ps1 -Environment staging` passes
- [x] No hardcoded secrets or tokens in app/backend

## Config and Environment
- [ ] `HAILO_ENV` set correctly per environment
- [ ] `HAILO_BASE_URL` set for physical-device testing
- [ ] `JWT_SECRET` configured in staging/prod
- [ ] `DATABASE_URL` configured in staging/prod
- [ ] `ALLOWED_ORIGINS` restricted to expected client origins
- [ ] Sentry DSN configured for Flutter + backend
- [ ] `ADMIN_ENABLE_SENTRY_SMOKE_ENDPOINT=true` set in staging only

## Auth and Routing
- [x] Cold start does not flicker between public/private screens
- [x] Unauthenticated private route redirects to login with `next=...`
- [x] Admin-only routes are blocked for non-admin users
- [x] Login returns to safe `next` destination when allowed

## API and Reliability
- [x] `/health`, `/healthz`, `/api/healthz` return fast and stable
- [x] `/version` returns commit/build metadata
- [x] API retries only idempotent or explicitly idempotent-key requests
- [x] Request-id is present in logs and diagnostics

## UX and Accessibility
- [x] Landing/login/signup screens have semantics labels
- [x] Touch targets are large enough on mobile
- [x] Large text mode remains usable
- [x] Error states use user-friendly messages
- [x] Settings/About screen shows version/build/env/base URL

## Release Assets
- [x] App icon generated from branded asset
- [x] Native splash uses branded configuration
- [x] Dev/staging/prod flavor mappings resolve correct endpoints

## Post-deploy
- [ ] Forced crash test reaches Sentry (staging)
- [ ] Health and smoke checks pass
- [ ] Observability dashboards show expected breadcrumbs/tags
- [ ] Rollback instructions are verified and current

## Quick Commands
```powershell
# Staging readiness
powershell -ExecutionPolicy Bypass -File tool/go_live_check.ps1 -Environment staging

# Production readiness (explicit production smoke opt-in)
$env:HAILO_ALLOW_PROD_SMOKE='1'
powershell -ExecutionPolicy Bypass -File tool/go_live_check.ps1 -Environment production -SkipReleaseGate
```

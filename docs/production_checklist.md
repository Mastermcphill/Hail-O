# Production Launch Checklist

## Pre-merge
- [ ] `flutter analyze` passes
- [ ] `flutter test` passes
- [ ] `backend` analyzer/tests pass
- [ ] CI checks are green on PR
- [ ] No hardcoded secrets or tokens in app/backend

## Config and Environment
- [ ] `HAILO_ENV` set correctly per environment
- [ ] `HAILO_BASE_URL` set for physical-device testing
- [ ] `JWT_SECRET` configured in staging/prod
- [ ] `DATABASE_URL` configured in staging/prod
- [ ] `ALLOWED_ORIGINS` restricted to expected client origins
- [ ] Sentry DSN configured for Flutter + backend

## Auth and Routing
- [ ] Cold start does not flicker between public/private screens
- [ ] Unauthenticated private route redirects to login with `next=...`
- [ ] Admin-only routes are blocked for non-admin users
- [ ] Login returns to safe `next` destination when allowed

## API and Reliability
- [ ] `/health`, `/healthz`, `/api/healthz` return fast and stable
- [ ] `/version` returns commit/build metadata
- [ ] API retries only idempotent or explicitly idempotent-key requests
- [ ] Request-id is present in logs and diagnostics

## UX and Accessibility
- [ ] Landing/login/signup screens have semantics labels
- [ ] Touch targets are large enough on mobile
- [ ] Large text mode remains usable
- [ ] Error states use user-friendly messages
- [ ] Settings/About screen shows version/build/env/base URL

## Release Assets
- [ ] App icon generated from branded asset
- [ ] Native splash uses branded configuration
- [ ] Dev/staging/prod flavor mappings resolve correct endpoints

## Post-deploy
- [ ] Forced crash test reaches Sentry (staging)
- [ ] Health and smoke checks pass
- [ ] Observability dashboards show expected breadcrumbs/tags
- [ ] Rollback instructions are verified and current

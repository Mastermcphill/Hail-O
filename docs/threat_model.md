# HAIL-O Threat Model

## Scope
- Flutter client (`lib/`)
- Backend API (`backend/`)
- Auth/session, routing, network transport, and operational controls

## Top Threats And Mitigations
| Threat | Risk | Mitigations Implemented | Residual Risk |
| --- | --- | --- | --- |
| Token theft from client device | Account takeover | Token stored via secure storage abstraction, logout/invalidation flow, no token logging, auth gate checks session at boot | Compromised/rooted devices remain high risk |
| MITM/intercepted traffic | Credential/session exposure | HTTPS production endpoints, no plaintext production base URL defaults, Sentry PII scrubbing | Users can still misconfigure dev URLs |
| Brute-force login attempts | Unauthorized access | Rate limiting middleware with stricter auth defaults, admin registration disabled by default | Additional CAPTCHA/device reputation can further reduce abuse |
| Credential stuffing | Reused credentials exploited | Auth error envelope does not leak internals, rate limits and consistent 401 handling | No built-in credential breach/password reuse checks yet |
| Role escalation | Access to admin/fleet routes | Provider-backed session role normalization, sync role-aware GoRouter redirect, admin-login role enforcement | Server-side authorization must remain strict for every protected endpoint |
| Replay and duplicate writes | Double charges/state corruption | Idempotency middleware and keys on write endpoints, API retry policy avoids unsafe POST retries | Any endpoint bypassing idempotency rules can regress safety |
| Sensitive data leakage in logs/crash reports | PII disclosure | Sentry `beforeSend` scrubs emails/phones, redacted request headers, backend JSON logs keyed by request-id | New fields may introduce unsanitized data if not reviewed |
| Backend cold start/slow dependencies | Timeouts/user-facing failures | Warmup banner in app, fast timeout-bounded `/health`, readiness `/healthz` and `/api/healthz` | Infra-level scaling/cold starts still affect first-request latency |
| Webhook spoofing/tampering | Fraudulent payment events | Existing webhook route controls + idempotency and observability breadcrumbs | Provider signature validation must remain enabled and tested |
| DoS/resource exhaustion | Service degradation | Request size limits, rate limiting, health/version endpoints, graceful shutdown on signals | Sustained volumetric attacks require upstream WAF/rate controls |

## Security Notes
- Strict env config guard added for `staging`/`production`:
  - `JWT_SECRET` required and must not be insecure default
  - `ALLOWED_ORIGINS` required and wildcard disallowed
  - `DATABASE_URL` required when postgres mode is enabled
- Observability is request-id correlated across client and backend for incident triage.

## Recommended Next Security Steps
1. Add automated secret scanning in CI.
2. Add credential hardening controls (lockout/backoff policy per account).
3. Enforce provider signature verification tests for all webhook providers.
4. Add periodic dependency vulnerability scanning and patch cadence policy.

# ENV Keys Inventory

This file is the operational inventory of environment variables used by backend runtime, payment/webhook handling, auth, and release scripts.

## Conventions
- `Required` means startup or core flow depends on it.
- `Optional` means feature flag or non-blocking integration.
- Environment column:
  - `dev`: local development
  - `staging`: pre-production verification
  - `prod`: production

## Core Runtime

| Key | Required | Environments | Purpose |
| --- | --- | --- | --- |
| `ENV` | Yes | dev, staging, prod | Primary environment selector (`development`/`staging`/`production`). |
| `FLIPTRYBE_ENV` | Optional | dev, staging, prod | Legacy/alternate environment source for routing metadata. |
| `PORT` | Yes | dev, staging, prod | HTTP listen port. |
| `BACKEND_DB_MODE` | Yes | dev, staging, prod | Backend DB mode (`sqlite`/`postgres`). |
| `DATABASE_URL` | Required for postgres mode | staging, prod (or dev postgres) | Postgres connection string. |
| `DB_SCHEMA` | Optional (recommended for postgres) | staging, prod | Postgres schema/search path isolation. |
| `DB_PATH` | Optional | dev | SQLite file path override. |
| `DB_POOL_SIZE` | Optional | staging, prod | Postgres connection pool size. |
| `DB_QUERY_TIMEOUT_MS` | Optional | staging, prod | Postgres statement timeout. |
| `REQUEST_IDLE_TIMEOUT_SECONDS` | Optional | dev, staging, prod | HTTP idle timeout. |
| `REQUEST_MAX_BODY_BYTES` | Optional | dev, staging, prod | Request body size limit. |
| `ALLOWED_ORIGINS` | Yes | staging, prod | CORS origin allow-list. |

## Auth / Tokens

| Key | Required | Environments | Purpose |
| --- | --- | --- | --- |
| `JWT_SECRET` | Yes | dev, staging, prod | JWT signing/verification secret. |
| `OTP_PROVIDER` | Required in prod unless approved bypass strategy | staging, prod | OTP provider selector (`termii`, etc). |
| `OTP_DEV_BYPASS` | Optional (must be false in prod) | dev, staging | Enables deterministic OTP bypass. |
| `OTP_DEV_BYPASS_CODE` | Optional | dev, staging | Dev bypass OTP code. |
| `OTP_CODE_LENGTH` | Optional | dev, staging, prod | OTP code length. |
| `OTP_TTL_SECONDS` | Optional | dev, staging, prod | OTP challenge TTL. |
| `OTP_MAX_ATTEMPTS` | Optional | dev, staging, prod | OTP verify attempt cap before lock. |
| `OTP_LOCKOUT_SECONDS` | Optional | dev, staging, prod | OTP lock duration. |
| `OTP_RATE_LIMIT_WINDOW_SECONDS` | Optional | dev, staging, prod | Sliding window for OTP endpoint throttles. |
| `OTP_REQUEST_LIMIT_PER_IP` | Optional | dev, staging, prod | OTP request throttle per IP in the configured window. |
| `OTP_REQUEST_LIMIT_PER_PHONE` | Optional | dev, staging, prod | OTP request throttle per phone in the configured window. |
| `OTP_VERIFY_LIMIT_PER_IP` | Optional | dev, staging, prod | OTP verify throttle per IP in the configured window. |
| `OTP_VERIFY_LIMIT_PER_PHONE` | Optional | dev, staging, prod | OTP verify throttle per phone in the configured window. |
| `REFRESH_TOKEN_TTL_SECONDS` | Optional | dev, staging, prod | Phone-auth refresh token TTL. |
| `TERMII_API_KEY` | Required if `OTP_PROVIDER=termii` | staging, prod | Termii API credential. |
| `TERMII_SENDER_ID` | Required if `OTP_PROVIDER=termii` | staging, prod | Termii sender identifier. |
| `TERMII_CHANNEL` | Optional | staging, prod | Termii channel override. |
| `TERMII_API_BASE_URL` | Optional | staging, prod | Termii base URL override. |

## Payments / Webhooks

| Key | Required | Environments | Purpose |
| --- | --- | --- | --- |
| `PAYMENTS_PROVIDER` / `PAYMENT_PROVIDER` | Yes | dev, staging, prod | Payment provider switch (`paystack`, `stripe`, `manual`). |
| `PAYSTACK_SECRET_KEY` | Required when provider is `paystack` | staging, prod | Server-to-Paystack API key. |
| `PAYSTACK_WEBHOOK_SECRET` | Required when provider is `paystack` (strictly required in prod) | staging, prod | Paystack webhook signature secret. |
| `STRIPE_WEBHOOK_SECRET` | Required when provider is `stripe` | staging, prod | Stripe webhook secret. |
| `PAYMENTS_WEBHOOK_SECRET` | Required in prod | prod (recommended staging) | Incoming `/webhooks/payments` HMAC secret. |
| `PAYSTACK_API_BASE_URL` | Optional | staging, prod | Paystack API base URL override. |
| `PAYSTACK_CALLBACK_URL` | Optional | staging, prod | Redirect/callback URL for initialized transactions. |

## Dispatch Pricing

| Key | Required | Environments | Purpose |
| --- | --- | --- | --- |
| `DISPATCH_BASE_FARE_MINOR` | Optional | dev, staging, prod | Base fare in minor units. |
| `DISPATCH_PER_KM_MINOR` | Optional | dev, staging, prod | Per-km charge in minor units. |
| `DISPATCH_MIN_FARE_MINOR` | Optional | dev, staging, prod | Minimum fare in minor units. |
| `DISPATCH_SURGE_MULTIPLIER` | Optional | dev, staging, prod | Surge multiplier. |
| `DISPATCH_AVG_SPEED_KMH` | Optional | dev, staging, prod | ETA speed constant. |
| `DISPATCH_CURRENCY` | Optional | dev, staging, prod | Quote currency code. |

## Rate Limiting / Traffic Controls

| Key | Required | Environments | Purpose |
| --- | --- | --- | --- |
| `RATE_LIMIT_ENABLED` | Optional | dev, staging, prod | Global rate-limit toggle. |
| `RATE_LIMIT_WINDOW_SEC` / `RATE_LIMIT_WINDOW_SECONDS` | Optional | dev, staging, prod | Window size. |
| `RATE_LIMIT_PER_IP_PER_MIN` / `RATE_LIMIT_MAX_REQUESTS_PER_IP` | Optional | dev, staging, prod | General IP limit. |
| `RATE_LIMIT_PER_USER_PER_MIN` / `RATE_LIMIT_MAX_REQUESTS_PER_USER` | Optional | dev, staging, prod | General user limit. |
| `RATE_LIMIT_AUTH_PER_IP_PER_MIN` | Optional | dev, staging, prod | Auth IP limit. |
| `RATE_LIMIT_AUTH_PER_USER_PER_MIN` | Optional | dev, staging, prod | Auth user limit. |
| `RATE_LIMIT_MARKETPLACE_READ_PER_IP` | Optional | dev, staging, prod | Marketplace read IP limit. |
| `RATE_LIMIT_MARKETPLACE_READ_PER_USER` | Optional | dev, staging, prod | Marketplace read user limit. |
| `RATE_LIMIT_MARKETPLACE_WRITE_PER_IP` | Optional | dev, staging, prod | Marketplace write IP limit. |
| `RATE_LIMIT_MARKETPLACE_WRITE_PER_USER` | Optional | dev, staging, prod | Marketplace write user limit. |
| `RATE_LIMIT_WEBHOOK_PER_IP` | Optional | dev, staging, prod | Webhook IP limit. |
| `RATE_LIMIT_WEBHOOK_PER_USER` / `RATE_LIMIT_WEBHOOK_MAX_REQUESTS_PER_USER` | Optional | dev, staging, prod | Webhook user/system limit. |
| `TRUST_PROXY_HEADERS` | Optional | staging, prod | Trust `x-forwarded-for` / `x-real-ip`. |

## Admin / Operations / Observability

| Key | Required | Environments | Purpose |
| --- | --- | --- | --- |
| `ADMIN_TOKEN_ENABLED` | Optional (default false) | staging, prod | Explicitly enables `ADMIN_TOKEN` emergency bypass. |
| `ADMIN_TOKEN` | Optional (high sensitivity) | staging, prod | Emergency admin bypass token (effective only when `ADMIN_TOKEN_ENABLED=true`). |
| `METRICS_PUBLIC` | Optional (default false) | dev, staging, prod | Expose metrics without admin auth. |
| `ADMIN_ENABLE_SENTRY_SMOKE_ENDPOINT` | Optional | dev, staging | Enable admin Sentry smoke route. |
| `SENTRY_ENABLED` | Optional | staging, prod | Sentry integration toggle. |
| `SENTRY_DSN` | Required if Sentry enabled | staging, prod | Sentry DSN. |
| `RENDER_GIT_COMMIT` | Optional (injected by Render) | staging, prod | Build metadata. |
| `RENDER_GIT_TAG` | Optional (injected by Render) | staging, prod | Build metadata. |
| `BUILD_VERSION` | Optional | dev, staging, prod | Build/version metadata. |
| `STARTUP_RUNTIME_MARKER` | Optional | dev, staging, prod | Runtime marker for diagnostics. |
| `DART_SDK_VERSION` | Optional | dev, staging, prod | Runtime metadata. |

## Release Gate / E2E Smoke

| Key | Required | Environments | Purpose |
| --- | --- | --- | --- |
| `BASE_URL` | Yes for gate execution | staging, prod | Target base URL for `release_gate.*` / `smoke_e2e.*`. |
| `STAGING_BASE_URL` | Required for prod gate | prod | Staging URL used when prod gate runs staging smoke. |
| `ADMIN_TOKEN_ENABLED` | Required for admin-token smoke | staging, prod | Must be `true` when smoke/admin checks depend on `ADMIN_TOKEN`. |
| `E2E_ADMIN_TOKEN` / `ADMIN_TOKEN` | Required for full smoke | staging, prod | Admin access token used for admin flow checks. |
| `E2E_ACCESS_TOKEN` | Optional | staging, prod | Pre-provisioned bearer token for smoke auth flow. |
| `E2E_PHONE_E164` | Required when `E2E_ACCESS_TOKEN` is unset | staging | Phone used for OTP auth path in smoke. |
| `E2E_OTP_CODE` | Required when `E2E_ACCESS_TOKEN` is unset | staging | OTP code used for smoke OTP verification. |
| `E2E_WEBHOOK_SECRET` | Optional | staging | Override webhook HMAC secret for smoke simulation. |
| `E2E_PAYSTACK_SECRET` | Optional | staging | Override Paystack HMAC secret for smoke simulation. |
| `REQUIRED_MIGRATION_HEAD` | Optional | staging, prod | Hard assertion for migration head in release gate. |
| `RELEASE_GATE_REQUIRE_PARITY` | Optional | prod | If true, fail when staging/target commits differ. |

## Security Notes
- Never print secrets (`JWT_SECRET`, provider keys, webhook secrets, `ADMIN_TOKEN`) in logs, artifacts, or API responses.
- In production, webhook signature verification must be enforced strictly.
- `OTP_DEV_BYPASS` must remain disabled in production.

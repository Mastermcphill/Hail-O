CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY,
  phone_e164 TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone_e164
ON users(phone_e164);

CREATE TABLE IF NOT EXISTS otp_challenges (
  id UUID PRIMARY KEY,
  phone_e164 TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  locked_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_otp_challenges_phone_created_desc
ON otp_challenges(phone_e164, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_otp_challenges_expires_at
ON otp_challenges(expires_at);

CREATE TABLE IF NOT EXISTS refresh_tokens (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_refresh_tokens_token_hash
ON refresh_tokens(token_hash);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_created_desc
ON refresh_tokens(user_id, created_at DESC);

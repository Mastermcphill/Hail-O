CREATE TABLE IF NOT EXISTS autosave_plans (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL UNIQUE REFERENCES users(id),
  tier INTEGER NOT NULL CHECK(tier BETWEEN 1 AND 4),
  lock_days INTEGER NOT NULL CHECK(lock_days IN (30, 120, 210, 330)),
  autosave_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  autosave_percent INTEGER NOT NULL DEFAULT 5 CHECK(autosave_percent BETWEEN 1 AND 30),
  status TEXT NOT NULL CHECK(status IN ('ACTIVE', 'PAUSED', 'MATURED', 'CLOSED')),
  started_at TIMESTAMPTZ NOT NULL,
  maturity_at TIMESTAMPTZ NOT NULL,
  bonus_rate NUMERIC(5, 4) NOT NULL DEFAULT 0,
  bonus_eligible BOOLEAN NOT NULL DEFAULT TRUE,
  bonus_paid_at TIMESTAMPTZ,
  total_autosaved_minor BIGINT NOT NULL DEFAULT 0,
  total_bonus_minor BIGINT NOT NULL DEFAULT 0,
  total_exit_fees_minor BIGINT NOT NULL DEFAULT 0,
  main_recipient_code TEXT,
  savings_recipient_code TEXT,
  last_applied_payout_ledger_id BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS autosave_ledger (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  plan_id BIGINT NOT NULL REFERENCES autosave_plans(id),
  payout_ledger_id BIGINT,
  entry_type TEXT NOT NULL CHECK(
    entry_type IN (
      'PLAN_OPEN',
      'PLAN_CHANGE',
      'AUTOSAVE_SPLIT',
      'BONUS',
      'EXIT_FEE',
      'EXIT_FEE_COLLECTED',
      'PLAN_PAUSE',
      'PLAN_RESUME',
      'PLAN_CLOSE'
    )
  ),
  amount_minor BIGINT NOT NULL,
  reference TEXT NOT NULL UNIQUE,
  meta_json JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS payout_transfers (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  trip_id UUID,
  payout_ledger_id BIGINT,
  kind TEXT NOT NULL CHECK(kind IN ('MAIN', 'SAVINGS', 'BONUS', 'EXIT_FEE')),
  amount_minor BIGINT NOT NULL,
  recipient_code TEXT NOT NULL,
  provider_transfer_code TEXT,
  provider_reference TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL CHECK(status IN ('PENDING', 'SUCCESS', 'FAILED', 'REVERSED')),
  meta_json JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_autosave_plans_status_maturity
ON autosave_plans(status, maturity_at ASC);

CREATE INDEX IF NOT EXISTS idx_autosave_ledger_user_created_desc
ON autosave_ledger(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_autosave_ledger_plan_created_desc
ON autosave_ledger(plan_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_payout_transfers_user_created_desc
ON payout_transfers(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_payout_transfers_payout_kind
ON payout_transfers(payout_ledger_id, kind, created_at DESC);

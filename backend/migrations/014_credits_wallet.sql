CREATE TABLE IF NOT EXISTS org_credits (
  org_id TEXT PRIMARY KEY,
  currency TEXT NOT NULL,
  balance_minor BIGINT NOT NULL DEFAULT 0 CHECK (balance_minor >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS credit_ledger (
  id UUID PRIMARY KEY,
  org_id TEXT NOT NULL,
  entry_type TEXT NOT NULL CHECK (
    entry_type IN (
      'referral_reward',
      'coupon_bonus',
      'manual_grant',
      'refund',
      'usage_deduction',
      'chargeback_adjustment',
      'credits_applied'
    )
  ),
  amount_minor BIGINT NOT NULL,
  currency TEXT NOT NULL,
  related_type TEXT,
  related_id TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_credit_ledger_org_created_desc
ON credit_ledger(org_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_credit_ledger_related
ON credit_ledger(related_type, related_id, created_at DESC);

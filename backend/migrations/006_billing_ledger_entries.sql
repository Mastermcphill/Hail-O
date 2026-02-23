CREATE TABLE IF NOT EXISTS billing_ledger_entries (
  id UUID PRIMARY KEY,
  purchase_id UUID REFERENCES marketplace_purchases(id) ON DELETE SET NULL,
  user_id TEXT NOT NULL,
  entry_type TEXT NOT NULL,
  provider TEXT NOT NULL,
  provider_ref TEXT NOT NULL DEFAULT '',
  amount_minor BIGINT NOT NULL,
  currency TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  occurred_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_billing_ledger_provider_ref_type
ON billing_ledger_entries(provider, provider_ref, entry_type);

CREATE INDEX IF NOT EXISTS idx_billing_ledger_purchase_occurred
ON billing_ledger_entries(purchase_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_billing_ledger_user_occurred
ON billing_ledger_entries(user_id, occurred_at DESC);

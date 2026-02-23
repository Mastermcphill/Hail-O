CREATE TABLE IF NOT EXISTS billing_ledger_entries (
  id UUID PRIMARY KEY,
  purchase_id UUID REFERENCES marketplace_purchases(id) ON DELETE SET NULL,
  user_id TEXT NOT NULL,
  entry_type TEXT NOT NULL CHECK (
    entry_type IN (
      'charge_authorized',
      'charge_captured',
      'charge_failed',
      'refund_initiated',
      'refund_succeeded',
      'chargeback',
      'invoice_created',
      'invoice_paid'
    )
  ),
  provider TEXT NOT NULL,
  provider_ref TEXT NOT NULL,
  amount_minor BIGINT NOT NULL,
  currency TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  occurred_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(provider, provider_ref, entry_type)
);

CREATE INDEX IF NOT EXISTS idx_billing_ledger_purchase_occurred_desc
ON billing_ledger_entries(purchase_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_billing_ledger_user_occurred_desc
ON billing_ledger_entries(user_id, occurred_at DESC);

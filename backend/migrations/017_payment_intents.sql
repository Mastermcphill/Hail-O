CREATE TABLE IF NOT EXISTS payment_intents (
  id UUID PRIMARY KEY,
  purchase_id UUID NOT NULL REFERENCES marketplace_purchases(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  status TEXT NOT NULL CHECK (
    status IN (
      'pending',
      'requires_action',
      'processing',
      'succeeded',
      'failed',
      'canceled',
      'cancelled',
      'expired',
      'captured'
    )
  ),
  amount_minor BIGINT NOT NULL CHECK (amount_minor >= 0),
  currency TEXT NOT NULL,
  provider_ref TEXT NOT NULL,
  client_secret TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE payment_intents
ADD COLUMN IF NOT EXISTS provider_ref TEXT;

ALTER TABLE payment_intents
ADD COLUMN IF NOT EXISTS client_secret TEXT;

ALTER TABLE payment_intents
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_payment_intents_purchase_created_desc
ON payment_intents(purchase_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_intents_purchase_active_unique
ON payment_intents(purchase_id)
WHERE status IN ('pending', 'requires_action', 'processing');


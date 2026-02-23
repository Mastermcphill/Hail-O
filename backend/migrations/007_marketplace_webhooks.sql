CREATE TABLE IF NOT EXISTS marketplace_webhook_events (
  id UUID PRIMARY KEY,
  provider TEXT NOT NULL,
  provider_event_id TEXT NOT NULL,
  purchase_id UUID REFERENCES marketplace_purchases(id) ON DELETE SET NULL,
  event_type TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  signature_valid BOOLEAN NOT NULL DEFAULT FALSE,
  processed BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at TIMESTAMPTZ,
  UNIQUE(provider, provider_event_id)
);

CREATE INDEX IF NOT EXISTS idx_marketplace_webhooks_provider_created
ON marketplace_webhook_events(provider, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_marketplace_webhooks_purchase_created
ON marketplace_webhook_events(purchase_id, created_at DESC);

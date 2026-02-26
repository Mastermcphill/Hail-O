CREATE TABLE IF NOT EXISTS webhook_events (
  id UUID PRIMARY KEY,
  provider TEXT NOT NULL,
  event_id TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(provider, event_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_webhook_events_provider_event
ON webhook_events(provider, event_id);

CREATE INDEX IF NOT EXISTS idx_webhook_events_received_desc
ON webhook_events(received_at DESC);


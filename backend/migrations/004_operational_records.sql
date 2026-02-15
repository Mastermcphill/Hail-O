CREATE TABLE IF NOT EXISTS operational_records (
  id BIGSERIAL PRIMARY KEY,
  operation_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  actor_user_id TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  payload_json TEXT NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(operation_type, entity_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_operational_records_entity_created
ON operational_records(entity_id, created_at DESC);

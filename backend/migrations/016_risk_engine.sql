CREATE TABLE IF NOT EXISTS risk_scores (
  subject_type TEXT NOT NULL CHECK (
    subject_type IN ('user', 'org', 'purchase', 'ip', 'device')
  ),
  subject_id TEXT NOT NULL,
  score_total INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL CHECK (state IN ('ok', 'flagged', 'restricted', 'suspended')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(subject_type, subject_id)
);

CREATE TABLE IF NOT EXISTS risk_events (
  id UUID PRIMARY KEY,
  subject_type TEXT NOT NULL CHECK (
    subject_type IN ('user', 'org', 'purchase', 'ip', 'device')
  ),
  subject_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  score_delta INTEGER NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_risk_events_subject_created
ON risk_events(subject_type, subject_id, created_at DESC);

CREATE TABLE IF NOT EXISTS risk_rules (
  id UUID PRIMARY KEY,
  event_type TEXT NOT NULL,
  delta INTEGER NOT NULL,
  window_seconds INTEGER,
  thresholds_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_risk_rules_event_active
ON risk_rules(event_type, is_active);

INSERT INTO risk_rules(id, event_type, delta, window_seconds, thresholds_json, is_active)
VALUES
  (
    '65afc5ee-1dc5-43ca-9643-972b7340e15d',
    'failed_payment',
    20,
    3600,
    '{"flagged":50,"restricted":70,"suspended":100}'::jsonb,
    TRUE
  ),
  (
    'b98a8d5c-312e-4b3a-9881-408ba384dc0a',
    'coupon_abuse',
    15,
    1800,
    '{"flagged":50,"restricted":70,"suspended":100}'::jsonb,
    TRUE
  ),
  (
    'a5c4ad65-e7b8-4673-b1a7-aeaf1922fbc4',
    'referral_self_loop',
    35,
    3600,
    '{"flagged":50,"restricted":70,"suspended":100}'::jsonb,
    TRUE
  ),
  (
    '6fcf61b5-f68b-4c74-bf90-d7d8b7ac2b5a',
    'seat_churn',
    10,
    900,
    '{"flagged":50,"restricted":70,"suspended":100}'::jsonb,
    TRUE
  ),
  (
    'c2da8f7d-7b3f-447e-86f7-c9a48274f194',
    'chargeback',
    60,
    86400,
    '{"flagged":50,"restricted":70,"suspended":100}'::jsonb,
    TRUE
  ),
  (
    '8bdf9ac3-8f5f-4ef6-93eb-9980f4e2cbf4',
    'purchase_burst',
    12,
    600,
    '{"flagged":50,"restricted":70,"suspended":100}'::jsonb,
    TRUE
  )
ON CONFLICT (id) DO UPDATE
SET
  event_type = EXCLUDED.event_type,
  delta = EXCLUDED.delta,
  window_seconds = EXCLUDED.window_seconds,
  thresholds_json = EXCLUDED.thresholds_json,
  is_active = EXCLUDED.is_active;

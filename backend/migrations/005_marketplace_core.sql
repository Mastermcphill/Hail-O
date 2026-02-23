CREATE TABLE IF NOT EXISTS marketplace_offers (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  currency TEXT NOT NULL DEFAULT 'NGN',
  price_minor BIGINT NOT NULL CHECK (price_minor >= 0),
  interval TEXT NOT NULL,
  features_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  seat_policy_json JSONB NOT NULL DEFAULT '{"min":1,"max":50,"included":1}'::jsonb,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_rank INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_marketplace_offers_active_rank
ON marketplace_offers(is_active, sort_rank, created_at DESC);

CREATE TABLE IF NOT EXISTS marketplace_purchases (
  id UUID PRIMARY KEY,
  user_id TEXT NOT NULL,
  offer_id TEXT NOT NULL REFERENCES marketplace_offers(id),
  status TEXT NOT NULL,
  currency TEXT NOT NULL,
  price_minor BIGINT NOT NULL,
  seats_total INTEGER NOT NULL CHECK (seats_total >= 1),
  provider TEXT NOT NULL DEFAULT 'manual',
  provider_customer_id TEXT,
  provider_subscription_id TEXT,
  provider_payment_intent_id TEXT,
  idempotency_key TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_marketplace_purchases_user_created
ON marketplace_purchases(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_marketplace_purchases_status_created
ON marketplace_purchases(status, created_at DESC);

CREATE TABLE IF NOT EXISTS marketplace_seat_assignments (
  id UUID PRIMARY KEY,
  purchase_id UUID NOT NULL REFERENCES marketplace_purchases(id) ON DELETE CASCADE,
  seat_index INTEGER NOT NULL CHECK (seat_index >= 1),
  assignee_user_id TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(purchase_id, assignee_user_id)
);

CREATE INDEX IF NOT EXISTS idx_marketplace_seat_assignments_purchase_seat
ON marketplace_seat_assignments(purchase_id, seat_index);

CREATE TABLE IF NOT EXISTS marketplace_timeline_events (
  id UUID PRIMARY KEY,
  purchase_id UUID NOT NULL REFERENCES marketplace_purchases(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  event_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_marketplace_timeline_purchase_created
ON marketplace_timeline_events(purchase_id, created_at DESC);

CREATE TABLE IF NOT EXISTS marketplace_webhook_events (
  id UUID PRIMARY KEY,
  provider TEXT NOT NULL,
  provider_event_id TEXT NOT NULL,
  purchase_id UUID REFERENCES marketplace_purchases(id) ON DELETE SET NULL,
  event_type TEXT NOT NULL,
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  processed BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_marketplace_webhook_provider_event
ON marketplace_webhook_events(provider, provider_event_id);

CREATE INDEX IF NOT EXISTS idx_marketplace_webhook_purchase_created
ON marketplace_webhook_events(purchase_id, created_at DESC);

INSERT INTO marketplace_offers(
  id,
  title,
  description,
  currency,
  price_minor,
  interval,
  features_json,
  seat_policy_json,
  is_active,
  sort_rank
)
VALUES
  (
    'starter_monthly',
    'Starter Monthly',
    'Core marketplace access for solo operators',
    'NGN',
    150000,
    'month',
    '["Basic analytics","Email support","Up to 5 bookings/day"]'::jsonb,
    '{"min":1,"max":5,"included":1}'::jsonb,
    TRUE,
    10
  ),
  (
    'pro_monthly',
    'Pro Monthly',
    'Advanced operations and seat management',
    'NGN',
    350000,
    'month',
    '["Priority matching","Seat management","Fraud checks"]'::jsonb,
    '{"min":1,"max":20,"included":5}'::jsonb,
    TRUE,
    20
  ),
  (
    'business_yearly',
    'Business Yearly',
    'High volume automation for marketplace operators',
    'NGN',
    3600000,
    'year',
    '["Dedicated support","Webhook automation","Advanced reporting"]'::jsonb,
    '{"min":5,"max":50,"included":20}'::jsonb,
    TRUE,
    30
  )
ON CONFLICT (id)
DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  currency = EXCLUDED.currency,
  price_minor = EXCLUDED.price_minor,
  interval = EXCLUDED.interval,
  features_json = EXCLUDED.features_json,
  seat_policy_json = EXCLUDED.seat_policy_json,
  is_active = EXCLUDED.is_active,
  sort_rank = EXCLUDED.sort_rank,
  updated_at = NOW();

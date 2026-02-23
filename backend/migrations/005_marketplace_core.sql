CREATE TABLE IF NOT EXISTS marketplace_offers (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'NGN',
  price_minor BIGINT NOT NULL CHECK (price_minor >= 0),
  interval TEXT NOT NULL,
  features_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  seat_policy_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_rank INTEGER NOT NULL DEFAULT 100,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_marketplace_offers_active_rank
ON marketplace_offers(is_active, sort_rank ASC, created_at DESC);

CREATE TABLE IF NOT EXISTS marketplace_purchases (
  id UUID PRIMARY KEY,
  user_id TEXT NOT NULL,
  offer_id TEXT NOT NULL REFERENCES marketplace_offers(id),
  status TEXT NOT NULL,
  currency TEXT NOT NULL,
  price_minor BIGINT NOT NULL CHECK (price_minor >= 0),
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

CREATE INDEX IF NOT EXISTS idx_marketplace_purchases_offer
ON marketplace_purchases(offer_id, created_at DESC);

CREATE TABLE IF NOT EXISTS marketplace_seat_assignments (
  id UUID PRIMARY KEY,
  purchase_id UUID NOT NULL REFERENCES marketplace_purchases(id) ON DELETE CASCADE,
  seat_index INTEGER NOT NULL CHECK (seat_index >= 1),
  assignee_user_id TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member',
  name TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(purchase_id, assignee_user_id)
);

CREATE INDEX IF NOT EXISTS idx_marketplace_assignments_purchase
ON marketplace_seat_assignments(purchase_id, created_at DESC);

CREATE TABLE IF NOT EXISTS marketplace_timeline_events (
  id UUID PRIMARY KEY,
  purchase_id UUID NOT NULL REFERENCES marketplace_purchases(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  event_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_marketplace_timeline_purchase_created_desc
ON marketplace_timeline_events(purchase_id, created_at DESC);

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
  'offer_sedan_01',
  'Budget Sedan',
  'Sedan Essentials',
  'NGN',
  4200,
  'per_trip',
  '["Air conditioning","Verified driver","Cashless payment"]'::jsonb,
  '{"min_seats":1,"max_seats":4,"included_seats":1}'::jsonb,
  TRUE,
  10
),
(
  'offer_suv_02',
  'Comfort SUV',
  'SUV Plus',
  'NGN',
  5900,
  'per_trip',
  '["Large luggage space","Premium interior","Priority support"]'::jsonb,
  '{"min_seats":1,"max_seats":6,"included_seats":1}'::jsonb,
  TRUE,
  20
),
(
  'offer_van_03',
  'Family Van',
  'Van Group',
  'NGN',
  7100,
  'per_trip',
  '["Group-friendly","Accessible boarding","Child seat options"]'::jsonb,
  '{"min_seats":1,"max_seats":8,"included_seats":1}'::jsonb,
  TRUE,
  30
)
ON CONFLICT (id)
DO UPDATE
SET
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

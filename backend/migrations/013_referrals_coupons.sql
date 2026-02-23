CREATE TABLE IF NOT EXISTS referral_codes (
  id UUID PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  owner_type TEXT NOT NULL CHECK (owner_type IN ('user', 'org')),
  owner_id TEXT NOT NULL,
  reward_kind TEXT NOT NULL CHECK (
    reward_kind IN ('credit', 'discount_percent', 'discount_fixed', 'trial_days')
  ),
  reward_value_minor BIGINT,
  reward_percent INTEGER,
  reward_trial_days INTEGER,
  max_uses INTEGER,
  uses_count INTEGER NOT NULL DEFAULT 0 CHECK (uses_count >= 0),
  expires_at TIMESTAMPTZ,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_referral_codes_owner
ON referral_codes(owner_type, owner_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_referral_codes_active
ON referral_codes(is_active, expires_at, created_at DESC);

CREATE TABLE IF NOT EXISTS referral_uses (
  id UUID PRIMARY KEY,
  code_id UUID NOT NULL REFERENCES referral_codes(id) ON DELETE CASCADE,
  referred_user_id TEXT NOT NULL,
  referred_org_id TEXT,
  purchase_id UUID REFERENCES marketplace_purchases(id) ON DELETE SET NULL,
  status TEXT NOT NULL CHECK (status IN ('applied', 'rewarded', 'reversed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(code_id, referred_user_id)
);

CREATE INDEX IF NOT EXISTS idx_referral_uses_code_created
ON referral_uses(code_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_referral_uses_purchase_created
ON referral_uses(purchase_id, created_at DESC);

CREATE TABLE IF NOT EXISTS coupons (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL CHECK (type IN ('percent', 'fixed', 'trial_days')),
  percent_value INTEGER,
  value_minor BIGINT,
  trial_days INTEGER,
  applies_to_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  stack_policy JSONB NOT NULL DEFAULT '{}'::jsonb,
  max_redemptions INTEGER,
  redemptions_count INTEGER NOT NULL DEFAULT 0 CHECK (redemptions_count >= 0),
  valid_from TIMESTAMPTZ NOT NULL,
  valid_until TIMESTAMPTZ NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_coupons_active_window
ON coupons(is_active, valid_from, valid_until, created_at DESC);

CREATE TABLE IF NOT EXISTS coupon_redemptions (
  id UUID PRIMARY KEY,
  coupon_id TEXT NOT NULL REFERENCES coupons(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  org_id TEXT,
  purchase_id UUID REFERENCES marketplace_purchases(id) ON DELETE SET NULL,
  discount_applied_minor BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(coupon_id, user_id, purchase_id)
);

CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_org_created
ON coupon_redemptions(org_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_purchase_created
ON coupon_redemptions(purchase_id, created_at DESC);

CREATE TABLE IF NOT EXISTS marketplace_pricing_contexts (
  org_id TEXT PRIMARY KEY,
  coupon_id TEXT REFERENCES coupons(id) ON DELETE SET NULL,
  referral_code_id UUID REFERENCES referral_codes(id) ON DELETE SET NULL,
  updated_by_user_id TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

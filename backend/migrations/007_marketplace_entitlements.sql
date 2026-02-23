CREATE TABLE IF NOT EXISTS marketplace_entitlements (
  id UUID PRIMARY KEY,
  purchase_id UUID NOT NULL REFERENCES marketplace_purchases(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  entitlement_type TEXT NOT NULL,
  value_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'pending',
  effective_from TIMESTAMPTZ NOT NULL,
  effective_to TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_marketplace_entitlements_purchase_effective
ON marketplace_entitlements(purchase_id, effective_from DESC);

CREATE INDEX IF NOT EXISTS idx_marketplace_entitlements_user_effective
ON marketplace_entitlements(user_id, effective_from DESC);

CREATE UNIQUE INDEX IF NOT EXISTS ux_marketplace_entitlements_active_type
ON marketplace_entitlements(purchase_id, entitlement_type)
WHERE effective_to IS NULL;

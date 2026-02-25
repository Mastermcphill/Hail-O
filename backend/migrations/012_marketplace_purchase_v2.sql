ALTER TABLE marketplace_purchases
ADD COLUMN IF NOT EXISTS quantity INTEGER;

UPDATE marketplace_purchases
SET quantity = seats_total
WHERE quantity IS NULL;

ALTER TABLE marketplace_purchases
ADD COLUMN IF NOT EXISTS amount_minor BIGINT;

UPDATE marketplace_purchases
SET amount_minor = price_minor
WHERE amount_minor IS NULL;

ALTER TABLE marketplace_purchases
ADD COLUMN IF NOT EXISTS client_reference TEXT;

ALTER TABLE marketplace_purchases
ALTER COLUMN idempotency_key DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_marketplace_purchases_user_idempotency
ON marketplace_purchases(user_id, idempotency_key);

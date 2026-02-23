ALTER TABLE marketplace_purchases
ADD COLUMN IF NOT EXISTS row_version BIGINT NOT NULL DEFAULT 1;

CREATE INDEX IF NOT EXISTS idx_marketplace_purchases_id_row_version
ON marketplace_purchases(id, row_version DESC);

ALTER TABLE marketplace_seat_assignments
ADD COLUMN IF NOT EXISTS row_version BIGINT NOT NULL DEFAULT 1;

CREATE INDEX IF NOT EXISTS idx_marketplace_assignments_purchase_row_version
ON marketplace_seat_assignments(purchase_id, row_version DESC);

CREATE SEQUENCE IF NOT EXISTS marketplace_timeline_event_seq_seq;

ALTER TABLE marketplace_timeline_events
ADD COLUMN IF NOT EXISTS event_seq BIGINT;

ALTER TABLE marketplace_timeline_events
ALTER COLUMN event_seq SET DEFAULT nextval('marketplace_timeline_event_seq_seq');

UPDATE marketplace_timeline_events
SET event_seq = nextval('marketplace_timeline_event_seq_seq')
WHERE event_seq IS NULL;

ALTER TABLE marketplace_timeline_events
ALTER COLUMN event_seq SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_marketplace_timeline_purchase_event_seq
ON marketplace_timeline_events(purchase_id, event_seq DESC);

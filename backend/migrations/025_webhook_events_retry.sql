ALTER TABLE webhook_events
ADD COLUMN IF NOT EXISTS processing_state TEXT NOT NULL DEFAULT 'received';

ALTER TABLE webhook_events
ADD COLUMN IF NOT EXISTS attempt_count INTEGER NOT NULL DEFAULT 0;

ALTER TABLE webhook_events
ADD COLUMN IF NOT EXISTS next_retry_at TIMESTAMPTZ;

ALTER TABLE webhook_events
ADD COLUMN IF NOT EXISTS last_error TEXT;

ALTER TABLE webhook_events
ADD COLUMN IF NOT EXISTS processed_at TIMESTAMPTZ;

ALTER TABLE webhook_events
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

UPDATE webhook_events
SET processing_state = CASE
  WHEN processing_state IN ('received', 'pending_processing', 'processed', 'failed')
    THEN processing_state
  ELSE 'received'
END
WHERE processing_state IS NULL
   OR processing_state NOT IN ('received', 'pending_processing', 'processed', 'failed');

ALTER TABLE webhook_events
DROP CONSTRAINT IF EXISTS webhook_events_processing_state_check;

ALTER TABLE webhook_events
ADD CONSTRAINT webhook_events_processing_state_check
CHECK (processing_state IN ('received', 'pending_processing', 'processed', 'failed'));

CREATE INDEX IF NOT EXISTS idx_webhook_events_processing_retry
ON webhook_events(processing_state, next_retry_at, received_at DESC);

CREATE INDEX IF NOT EXISTS idx_webhook_events_updated_desc
ON webhook_events(updated_at DESC);

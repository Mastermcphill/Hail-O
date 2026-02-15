CREATE TABLE IF NOT EXISTS ride_request_metadata (
  ride_id TEXT PRIMARY KEY,
  scheduled_departure_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ride_request_metadata_departure
ON ride_request_metadata(scheduled_departure_at);

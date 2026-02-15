CREATE TABLE IF NOT EXISTS ride_request_metadata (
  ride_id TEXT PRIMARY KEY,
  rider_id TEXT NOT NULL DEFAULT '',
  scheduled_departure_at TIMESTAMPTZ,
  quote_json TEXT NOT NULL DEFAULT '{}',
  request_json TEXT NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ride_request_metadata_rider_id
ON ride_request_metadata(rider_id);

CREATE INDEX IF NOT EXISTS idx_ride_request_metadata_created_at
ON ride_request_metadata(created_at DESC);

CREATE TABLE IF NOT EXISTS trips (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  status TEXT NOT NULL CHECK(
    status IN (
      'created',
      'searching',
      'assigned',
      'enroute_pickup',
      'picked_up',
      'enroute_dropoff',
      'delivered',
      'canceled'
    )
  ),
  pickup_lat DOUBLE PRECISION NOT NULL,
  pickup_lng DOUBLE PRECISION NOT NULL,
  pickup_address TEXT,
  dropoff_lat DOUBLE PRECISION NOT NULL,
  dropoff_lng DOUBLE PRECISION NOT NULL,
  dropoff_address TEXT,
  notes TEXT,
  scheduled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trips_user_created_desc
ON trips(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_trips_status_created_desc
ON trips(status, created_at DESC);

CREATE TABLE IF NOT EXISTS trip_events (
  id UUID PRIMARY KEY,
  trip_id UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  actor_user_id UUID NOT NULL REFERENCES users(id),
  from_status TEXT,
  to_status TEXT NOT NULL CHECK(
    to_status IN (
      'created',
      'searching',
      'assigned',
      'enroute_pickup',
      'picked_up',
      'enroute_dropoff',
      'delivered',
      'canceled'
    )
  ),
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trip_events_trip_created
ON trip_events(trip_id, created_at);

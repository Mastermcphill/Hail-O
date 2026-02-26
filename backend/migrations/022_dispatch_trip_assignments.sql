CREATE TABLE IF NOT EXISTS trip_assignments (
  id UUID PRIMARY KEY,
  trip_id UUID NOT NULL UNIQUE REFERENCES trips(id) ON DELETE CASCADE,
  driver_id UUID NOT NULL REFERENCES users(id),
  status TEXT NOT NULL CHECK(status IN ('assigned', 'accepted', 'rejected', 'canceled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trip_assignments_driver_status_created_desc
ON trip_assignments(driver_id, status, created_at DESC);

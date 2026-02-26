CREATE TABLE IF NOT EXISTS analytics_events (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  session_id TEXT,
  properties JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_analytics_events_name_created_desc
ON analytics_events(name, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_analytics_events_user_created_desc
ON analytics_events(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS user_profiles (
  user_id UUID PRIMARY KEY REFERENCES users(id),
  display_name TEXT,
  email TEXT,
  avatar_url TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_roles (
  user_id UUID NOT NULL REFERENCES users(id),
  role TEXT NOT NULL CHECK(role IN ('user', 'admin', 'merchant', 'driver', 'inspector')),
  UNIQUE(user_id, role)
);

CREATE INDEX IF NOT EXISTS idx_user_roles_user_id
ON user_roles(user_id);

INSERT INTO user_profiles(user_id, display_name, email, avatar_url, updated_at)
SELECT id, NULL, NULL, NULL, NOW()
FROM users
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO user_roles(user_id, role)
SELECT id, 'user'
FROM users
ON CONFLICT (user_id, role) DO NOTHING;

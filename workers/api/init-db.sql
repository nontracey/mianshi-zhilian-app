CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  nickname TEXT,
  role TEXT DEFAULT 'user',
  is_disabled INTEGER DEFAULT 0,
  disabled_at TEXT DEFAULT NULL,
  updated_at TEXT DEFAULT NULL,
  created_at TEXT DEFAULT (datetime('now')),
  last_login_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);

CREATE TABLE IF NOT EXISTS refresh_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  token_hash TEXT UNIQUE NOT NULL,
  expires_at TEXT NOT NULL,
  revoked_at TEXT,
  rotated_to TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  last_used_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_hash ON refresh_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens(user_id);

CREATE TABLE IF NOT EXISTS tickets (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  account_username TEXT,
  contact TEXT,
  type TEXT NOT NULL,
  subject TEXT NOT NULL,
  description TEXT NOT NULL,
  image_urls TEXT DEFAULT '[]',
  status TEXT DEFAULT 'pending',
  admin_reply TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  resolved_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_tickets_user ON tickets(user_id);
CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status);
CREATE INDEX IF NOT EXISTS idx_tickets_created ON tickets(created_at);
CREATE INDEX IF NOT EXISTS idx_tickets_account_username ON tickets(account_username);

CREATE TABLE IF NOT EXISTS user_devices (
  device_id TEXT PRIMARY KEY,
  user_id TEXT,
  platform TEXT,
  app_version TEXT,
  os_version TEXT,
  device_model TEXT,
  first_seen_at TEXT DEFAULT (datetime('now')),
  last_seen_at TEXT DEFAULT (datetime('now')),
  last_login_at TEXT,
  visit_count INTEGER DEFAULT 0,
  total_duration_seconds INTEGER DEFAULT 0,
  FOREIGN KEY (user_id) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_user_devices_user ON user_devices(user_id);
CREATE INDEX IF NOT EXISTS idx_user_devices_last_seen ON user_devices(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_user_devices_platform ON user_devices(platform);

CREATE TABLE IF NOT EXISTS daily_visit_stats (
  date TEXT NOT NULL,
  device_id TEXT NOT NULL,
  user_id TEXT,
  platform TEXT,
  app_version TEXT,
  open_count INTEGER DEFAULT 0,
  heartbeat_count INTEGER DEFAULT 0,
  duration_seconds INTEGER DEFAULT 0,
  last_seen_at TEXT DEFAULT (datetime('now')),
  PRIMARY KEY (date, device_id)
);
CREATE INDEX IF NOT EXISTS idx_daily_visit_stats_date ON daily_visit_stats(date);
CREATE INDEX IF NOT EXISTS idx_daily_visit_stats_user ON daily_visit_stats(user_id);
CREATE INDEX IF NOT EXISTS idx_daily_visit_stats_platform ON daily_visit_stats(platform);

CREATE TABLE IF NOT EXISTS daily_section_stats (
  date TEXT NOT NULL,
  device_id TEXT NOT NULL,
  user_id TEXT,
  section TEXT NOT NULL,
  count INTEGER DEFAULT 0,
  PRIMARY KEY (date, device_id, section)
);
CREATE INDEX IF NOT EXISTS idx_daily_section_stats_date ON daily_section_stats(date);
CREATE INDEX IF NOT EXISTS idx_daily_section_stats_section ON daily_section_stats(section);

CREATE TABLE IF NOT EXISTS daily_feature_stats (
  date TEXT NOT NULL,
  device_id TEXT NOT NULL,
  user_id TEXT,
  feature TEXT NOT NULL,
  count INTEGER DEFAULT 0,
  PRIMARY KEY (date, device_id, feature)
);
CREATE INDEX IF NOT EXISTS idx_daily_feature_stats_date ON daily_feature_stats(date);
CREATE INDEX IF NOT EXISTS idx_daily_feature_stats_feature ON daily_feature_stats(feature);

CREATE TABLE IF NOT EXISTS analytics_batches (
  batch_id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  user_id TEXT,
  received_at TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_analytics_batches_device ON analytics_batches(device_id);

CREATE TABLE IF NOT EXISTS app_visit_events (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  user_id TEXT,
  event_type TEXT NOT NULL,
  occurred_at TEXT DEFAULT (datetime('now')),
  duration_seconds INTEGER DEFAULT 0,
  platform TEXT,
  app_version TEXT,
  route TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_visit_events_user ON app_visit_events(user_id);
CREATE INDEX IF NOT EXISTS idx_visit_events_device ON app_visit_events(device_id);
CREATE INDEX IF NOT EXISTS idx_visit_events_occurred ON app_visit_events(occurred_at);

CREATE TABLE IF NOT EXISTS security_block_rules (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  value TEXT NOT NULL,
  reason TEXT,
  is_active INTEGER DEFAULT 1,
  created_by TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  expires_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_security_block_rules_lookup ON security_block_rules(type, value, is_active);
CREATE INDEX IF NOT EXISTS idx_security_block_rules_created ON security_block_rules(created_at);

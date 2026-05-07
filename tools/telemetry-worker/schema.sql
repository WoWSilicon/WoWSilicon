CREATE TABLE IF NOT EXISTS daily_event_installs (
  day TEXT NOT NULL,
  event TEXT NOT NULL,
  install_id TEXT NOT NULL,
  PRIMARY KEY (day, event, install_id)
);

CREATE TABLE IF NOT EXISTS daily_dimension_installs (
  day TEXT NOT NULL,
  dimension TEXT NOT NULL,
  value TEXT NOT NULL,
  install_id TEXT NOT NULL,
  PRIMARY KEY (day, dimension, value, install_id)
);

CREATE TABLE IF NOT EXISTS installs (
  install_id TEXT PRIMARY KEY,
  first_seen_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS active_sessions (
  session_id TEXT PRIMARY KEY,
  install_id TEXT NOT NULL,
  last_seen_at INTEGER NOT NULL,
  app_version TEXT,
  wow_version TEXT,
  renderer TEXT,
  macos_version TEXT,
  realmlist TEXT
);

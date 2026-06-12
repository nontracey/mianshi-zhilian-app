// 初始化数据库表
async function execSafely(
  db: D1Database,
  sql: string,
  label: string,
): Promise<void> {
  try {
    // D1 的 db.exec 对某些 DDL 有限制，改用 prepare + run
    await db.prepare(sql).run();
  } catch (e) {
    console.error(`initDatabase [${label}] error:`, e);
    // 单条语句失败不中断整体初始化
  }
}

export async function initDatabase(db: D1Database): Promise<void> {
  if (dbInitialized) return;
  // 逐条执行 D1 DDL，避免多语句 exec 兼容性问题
  await execSafely(
    db,
    `CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      nickname TEXT,
      role TEXT DEFAULT 'user',
      created_at TEXT DEFAULT (datetime('now')),
      last_login_at TEXT
    )`,
    "create users",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_users_username ON users(username)`,
    "idx users username",
  );

  // 迁移：已有表缺少列时自动补充
  try {
    const cols = (await db.prepare(`PRAGMA table_info(users)`).all()) as any;
    const userColumns = new Set(
      (cols.results as any[]).map((c: any) => c.name),
    );
    const userMigrations: Record<string, string> = {
      role: `ALTER TABLE users ADD COLUMN role TEXT DEFAULT 'user'`,
      is_disabled: `ALTER TABLE users ADD COLUMN is_disabled INTEGER DEFAULT 0`,
      disabled_at: `ALTER TABLE users ADD COLUMN disabled_at TEXT DEFAULT NULL`,
      updated_at: `ALTER TABLE users ADD COLUMN updated_at TEXT DEFAULT NULL`,
    };
    for (const [column, sql] of Object.entries(userMigrations)) {
      if (!userColumns.has(column)) {
        await execSafely(db, sql, `migrate users.${column}`);
      }
    }
  } catch (e) {
    console.error("initDatabase user migration error:", e);
  }

  await execSafely(
    db,
    `CREATE TABLE IF NOT EXISTS refresh_tokens (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      token_hash TEXT UNIQUE NOT NULL,
      expires_at TEXT NOT NULL,
      revoked_at TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      last_used_at TEXT,
      FOREIGN KEY (user_id) REFERENCES users(id)
    )`,
    "create refresh_tokens",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_refresh_tokens_hash ON refresh_tokens(token_hash)`,
    "idx refresh_tokens hash",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens(user_id)`,
    "idx refresh_tokens user",
  );
  // 宽限期轮换：记录旋转出的新 token ID，允许旧 token 在 ~60s 内重试。
  // 先查列是否存在再 ALTER，避免每次冷启动都执行必失败的 DDL（与 users 迁移一致）。
  try {
    const cols = (await db
      .prepare(`PRAGMA table_info(refresh_tokens)`)
      .all()) as any;
    const columns = new Set((cols.results as any[]).map((c: any) => c.name));
    if (!columns.has("rotated_to")) {
      await execSafely(
        db,
        `ALTER TABLE refresh_tokens ADD COLUMN rotated_to TEXT`,
        "migrate refresh_tokens rotated_to",
      );
    }
  } catch (e) {
    console.error("initDatabase refresh_tokens migration error:", e);
  }

  await execSafely(
    db,
    `CREATE TABLE IF NOT EXISTS tickets (
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
    )`,
    "create tickets",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_tickets_user ON tickets(user_id)`,
    "idx tickets user",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status)`,
    "idx tickets status",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_tickets_created ON tickets(created_at)`,
    "idx tickets created",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_tickets_account_username ON tickets(account_username)`,
    "idx tickets account_username",
  );

  await execSafely(
    db,
    `CREATE TABLE IF NOT EXISTS user_devices (
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
    )`,
    "create user_devices",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_user_devices_user ON user_devices(user_id)`,
    "idx user_devices user",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_user_devices_last_seen ON user_devices(last_seen_at)`,
    "idx user_devices last_seen",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_user_devices_platform ON user_devices(platform)`,
    "idx user_devices platform",
  );

  await execSafely(
    db,
    `CREATE TABLE IF NOT EXISTS daily_visit_stats (
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
    )`,
    "create daily_visit_stats",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_daily_visit_stats_date ON daily_visit_stats(date)`,
    "idx daily_visit_stats date",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_daily_visit_stats_user ON daily_visit_stats(user_id)`,
    "idx daily_visit_stats user",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_daily_visit_stats_platform ON daily_visit_stats(platform)`,
    "idx daily_visit_stats platform",
  );

  await execSafely(
    db,
    `CREATE TABLE IF NOT EXISTS daily_section_stats (
      date TEXT NOT NULL,
      device_id TEXT NOT NULL,
      user_id TEXT,
      section TEXT NOT NULL,
      count INTEGER DEFAULT 0,
      PRIMARY KEY (date, device_id, section)
    )`,
    "create daily_section_stats",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_daily_section_stats_date ON daily_section_stats(date)`,
    "idx daily_section_stats date",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_daily_section_stats_section ON daily_section_stats(section)`,
    "idx daily_section_stats section",
  );

  await execSafely(
    db,
    `CREATE TABLE IF NOT EXISTS daily_feature_stats (
      date TEXT NOT NULL,
      device_id TEXT NOT NULL,
      user_id TEXT,
      feature TEXT NOT NULL,
      count INTEGER DEFAULT 0,
      PRIMARY KEY (date, device_id, feature)
    )`,
    "create daily_feature_stats",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_daily_feature_stats_date ON daily_feature_stats(date)`,
    "idx daily_feature_stats date",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_daily_feature_stats_feature ON daily_feature_stats(feature)`,
    "idx daily_feature_stats feature",
  );

  await execSafely(
    db,
    `CREATE TABLE IF NOT EXISTS analytics_batches (
      batch_id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL,
      user_id TEXT,
      received_at TEXT DEFAULT (datetime('now'))
    )`,
    "create analytics_batches",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_analytics_batches_device ON analytics_batches(device_id)`,
    "idx analytics_batches device",
  );

  await execSafely(
    db,
    `CREATE TABLE IF NOT EXISTS app_visit_events (
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
    )`,
    "create app_visit_events",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_visit_events_user ON app_visit_events(user_id)`,
    "idx visit_events user",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_visit_events_device ON app_visit_events(device_id)`,
    "idx visit_events device",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_visit_events_occurred ON app_visit_events(occurred_at)`,
    "idx visit_events occurred",
  );
  await execSafely(
    db,
    `UPDATE analytics_batches SET user_id = NULL WHERE user_id IS NOT NULL`,
    "privacy analytics_batches user_id",
  );
  await execSafely(
    db,
    `UPDATE daily_visit_stats SET user_id = NULL WHERE user_id IS NOT NULL`,
    "privacy daily_visit_stats user_id",
  );
  await execSafely(
    db,
    `UPDATE daily_section_stats SET user_id = NULL WHERE user_id IS NOT NULL`,
    "privacy daily_section_stats user_id",
  );
  await execSafely(
    db,
    `UPDATE daily_feature_stats SET user_id = NULL WHERE user_id IS NOT NULL`,
    "privacy daily_feature_stats user_id",
  );
  await execSafely(
    db,
    `DELETE FROM analytics_batches WHERE received_at < datetime('now', '-30 days')`,
    "privacy analytics_batches retention",
  );

  await execSafely(
    db,
    `CREATE TABLE IF NOT EXISTS security_block_rules (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      value TEXT NOT NULL,
      reason TEXT,
      is_active INTEGER DEFAULT 1,
      created_by TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      expires_at TEXT
    )`,
    "create security_block_rules",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_security_block_rules_lookup ON security_block_rules(type, value, is_active)`,
    "idx security_block_rules lookup",
  );
  await execSafely(
    db,
    `CREATE INDEX IF NOT EXISTS idx_security_block_rules_created ON security_block_rules(created_at)`,
    "idx security_block_rules created",
  );

  dbInitialized = true;
}

// 模块级标志，避免每次请求重复执行 DDL
let dbInitialized = false;

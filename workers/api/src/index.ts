import pkg from "../package.json";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // 处理 CORS 预检请求
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
          "Access-Control-Allow-Headers":
            "Content-Type, Authorization, X-Device-Id, X-Platform, X-App-Version, X-OS-Version, X-Device-Model",
        },
      });
    }

    if (url.pathname === "/health") {
      return json({
        ok: true,
        service: "mianshi-zhilian-api",
        version: pkg.version,
      });
    }

    if (url.pathname === "/config") {
      return json({
        contentManifestUrls: [
          `${contentPrimaryBaseUrl(env)}/manifest.json`,
          `${contentBackupBaseUrl(env)}/manifest.json`,
        ],
        contentPrimaryBaseUrl: contentPrimaryBaseUrl(env),
        contentBackupBaseUrl: contentBackupBaseUrl(env),
        updateManifestUrl:
          "https://github.com/nontracey/mianshi-zhilian-app/releases/latest",
        aiProxyEnabled: true,
      });
    }

    if (url.pathname === "/update.json") {
      return proxyUpdateManifest();
    }

    const blocked = await checkSecurityBlock(request, env);
    if (blocked) return blocked;

    // 用户注册
    if (url.pathname === "/auth/register" && request.method === "POST") {
      return handleRegister(request, env);
    }

    // 用户登录
    if (url.pathname === "/auth/login" && request.method === "POST") {
      return handleLogin(request, env);
    }

    // 刷新登录态
    if (url.pathname === "/auth/refresh" && request.method === "POST") {
      return handleRefreshToken(request, env);
    }

    // 退出登录
    if (url.pathname === "/auth/logout" && request.method === "POST") {
      return handleLogout(request, env);
    }

    // 获取用户信息（需要认证）
    if (url.pathname === "/auth/me" && request.method === "GET") {
      return handleGetMe(request, env);
    }

    // 修改密码（需要认证）
    if (url.pathname === "/auth/change-password" && request.method === "POST") {
      return handleChangePassword(request, env);
    }

    if (url.pathname === "/tickets" && request.method === "POST") {
      return handleCreateTicket(request, env);
    }

    if (url.pathname === "/tickets" && request.method === "GET") {
      return handleGetMyTickets(request, env);
    }

    if (
      url.pathname === "/tickets/password-reset" &&
      request.method === "POST"
    ) {
      return handleCreatePasswordResetTicket(request, env);
    }

    if (url.pathname === "/analytics/batch" && request.method === "POST") {
      return handleAnalyticsBatch(request, env);
    }

    if (
      url.pathname === "/analytics/bind-device" &&
      request.method === "POST"
    ) {
      return handleBindDevice(request, env);
    }

    // 管理员接口（需 admin 权限；studio 共享同 D1）
    if (
      url.pathname.startsWith("/admin/users/") &&
      url.pathname.endsWith("/reset-password") &&
      request.method === "POST"
    ) {
      return handleAdminResetPassword(request, env);
    }
    if (
      url.pathname.startsWith("/admin/tickets/") &&
      request.method === "DELETE"
    ) {
      return handleAdminDeleteTicket(request, env);
    }

    // 代理测试环境内容: /content/test/* → staging-manifest / topics 等静态内容
    if (url.pathname.startsWith("/content/test/")) {
      const subPath = contentStageSubPath(
        "test",
        url.pathname.slice("/content/test/".length),
      );
      return proxyFetchWithFallback(contentTargetUrls(env, subPath), request);
    }

    // 代理草稿环境内容: /content/draft/* → CONTENT_*_BASE_URL/*
    if (url.pathname.startsWith("/content/draft/")) {
      const subPath = contentStageSubPath(
        "draft",
        url.pathname.slice("/content/draft/".length),
      );
      return proxyFetchWithFallback(contentTargetUrls(env, subPath), request);
    }

    // 代理发布环境内容: /content/production/* → production manifest / topics 等静态内容
    if (url.pathname.startsWith("/content/production/")) {
      const subPath = url.pathname.slice("/content/production/".length);
      return proxyFetchWithFallback(contentTargetUrls(env, subPath), request);
    }

    return json({ error: "Not found" }, 404);
  },
};

function contentPrimaryBaseUrl(env: Env): string {
  return (
    env.CONTENT_PRIMARY_BASE_URL ||
    "https://mianshi-zhilian-content.pages.dev"
  );
}

function contentBackupBaseUrl(env: Env): string {
  return (
    env.CONTENT_BACKUP_BASE_URL ||
    "https://mianshizhilian-content.nontracey.de5.net"
  );
}

function contentTargetUrls(env: Env, subPath: string): string[] {
  const path = subPath.replace(/^\/+/, "");
  const urls = [
    `${contentPrimaryBaseUrl(env).replace(/\/+$/, "")}/${path}`,
    `${contentBackupBaseUrl(env).replace(/\/+$/, "")}/${path}`,
  ];
  return Array.from(new Set(urls));
}

function contentStageSubPath(stage: "test" | "draft", subPath: string): string {
  const normalized = subPath.replace(/^\/+/, "");
  if (normalized === "manifest.json") {
    return stage === "draft" ? "draft-manifest.json" : "staging-manifest.json";
  }
  return normalized;
}

async function proxyFetchWithFallback(
  targetUrls: string[],
  originalRequest: Request,
): Promise<Response> {
  let lastError: unknown;
  for (let i = 0; i < targetUrls.length; i++) {
    const targetUrl = targetUrls[i];
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 8000);
    try {
      const response = await fetch(targetUrl, {
        method: originalRequest.method,
        headers: {
          Accept: originalRequest.headers.get("Accept") || "application/json",
        },
        redirect: "follow",
        signal: controller.signal,
      });
      clearTimeout(timeoutId);
      if (i < targetUrls.length - 1 && response.status >= 500) {
        lastError = `HTTP ${response.status} from ${targetUrl}`;
        continue;
      }
      const body = await response.text();
      return new Response(body, {
        status: response.status,
        headers: {
          "content-type":
            response.headers.get("content-type") ||
            "application/json; charset=utf-8",
          "access-control-allow-origin": "*",
          "cache-control": "public, max-age=300",
        },
      });
    } catch (e) {
      clearTimeout(timeoutId);
      lastError = e;
      if (i < targetUrls.length - 1) continue;
    }
  }
  console.error("ProxyFetch error:", lastError);
  return json({ error: "上游请求失败" }, 502);
}

async function proxyUpdateManifest(): Promise<Response> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 8000);
  try {
    const res = await fetch(
      "https://github.com/nontracey/mianshi-zhilian-app/releases/latest/download/update.json",
      { redirect: "follow", signal: controller.signal },
    );
    if (!res.ok) {
      return json({ error: "update manifest not found" }, 404);
    }
    const data = await res.json();
    normalizeUpdateManifest(data);
    return new Response(JSON.stringify(data), {
      headers: {
        "content-type": "application/json; charset=utf-8",
        "access-control-allow-origin": "*",
        "cache-control": "public, max-age=300",
      },
    });
  } catch (e) {
    console.error("proxyUpdateManifest error:", e);
    return json({ error: "上游请求失败" }, 502);
  } finally {
    clearTimeout(timeoutId);
  }
}

function normalizeUpdateManifest(data: any): void {
  const platforms = data?.platforms;
  if (!platforms || typeof platforms !== "object") return;
  for (const platform of Object.values(platforms) as any[]) {
    if (!platform || typeof platform !== "object" || platform.assetPath)
      continue;
    const rawUrl = typeof platform.url === "string" ? platform.url : "";
    try {
      const url = new URL(rawUrl);
      const latestMarker = "/releases/latest/download/";
      const latestIndex = url.pathname.indexOf(latestMarker);
      if (latestIndex >= 0) {
        platform.assetPath = url.pathname.slice(latestIndex);
        continue;
      }
      const versionedMatch = url.pathname.match(
        /^\/[^/]+\/[^/]+\/releases\/download\/[^/]+\/(.+)$/,
      );
      if (versionedMatch?.[1]) {
        platform.assetPath = `${latestMarker}${versionedMatch[1]}`;
      }
    } catch {
      // Ignore non-URL asset values; clients will keep using url/mirrors.
    }
  }
}

// PBKDF2 密码哈希（100K 迭代 + 16 字节随机 salt）
const PBKDF2_ITERATIONS = 100_000;
const SALT_BYTES = 16;
const HASH_BYTES = 32;

function toHex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function fromHex(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }
  return bytes;
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

async function hashPassword(
  password: string,
  existingSalt?: string,
): Promise<string> {
  const encoder = new TextEncoder();
  const salt = existingSalt
    ? fromHex(existingSalt)
    : crypto.getRandomValues(new Uint8Array(SALT_BYTES));
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(password),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const derivedBits = await crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      salt: toArrayBuffer(salt),
      iterations: PBKDF2_ITERATIONS,
      hash: "SHA-256",
    },
    key,
    HASH_BYTES * 8,
  );
  const saltHex = toHex(toArrayBuffer(salt));
  const hashHex = toHex(derivedBits);
  return `${saltHex}:${hashHex}`;
}

// 兼容旧格式（无 salt 的纯 SHA-256）和新格式（salt:hash）
async function verifyPassword(
  password: string,
  storedHash: string,
): Promise<boolean> {
  if (storedHash.includes(":")) {
    // 新格式: salt:pbkdf2hash
    const [salt] = storedHash.split(":");
    const recomputed = await hashPassword(password, salt);
    return recomputed === storedHash;
  }
  // 旧格式: 纯 SHA-256（无 salt），验证后会自动升级
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hash = await crypto.subtle.digest("SHA-256", data);
  const legacyHash = toHex(hash);
  return legacyHash === storedHash;
}

// 旧版 SHA-256 哈希（仅用于识别旧格式，不用于新密码）
async function legacyHash(password: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return toHex(hash);
}

const ACCESS_TOKEN_TTL_SECONDS = 24 * 60 * 60; // 24 小时
const REFRESH_TOKEN_TTL_SECONDS = 90 * 24 * 60 * 60; // 90 天未使用需重新登录
const REFRESH_TOKEN_BYTES = 32;

function getJwtSecret(env: Env): string {
  const secret = env.JWT_SECRET;
  if (
    !secret ||
    secret === "undefined" ||
    secret === "null" ||
    secret.trim() === ""
  ) {
    throw new Error("JWT_SECRET is not configured");
  }
  return secret;
}

// 生成简单的 JWT token
async function generateToken(userId: string, secret: string): Promise<string> {
  const header = { alg: "HS256", typ: "JWT" };
  const payload = {
    userId,
    exp: Math.floor(Date.now() / 1000) + ACCESS_TOKEN_TTL_SECONDS,
  };

  const headerBase64 = btoa(JSON.stringify(header)).replace(/=/g, "");
  const payloadBase64 = btoa(JSON.stringify(payload)).replace(/=/g, "");
  const message = `${headerBase64}.${payloadBase64}`;

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(message),
  );
  const signatureBase64 = btoa(
    String.fromCharCode(...new Uint8Array(signature)),
  )
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");

  return `${message}.${signatureBase64}`;
}

function generateOpaqueToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(REFRESH_TOKEN_BYTES));
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

async function hashRefreshToken(token: string): Promise<string> {
  const encoder = new TextEncoder();
  const hash = await crypto.subtle.digest("SHA-256", encoder.encode(token));
  return toHex(hash);
}

function refreshTokenExpiresAt(): string {
  return new Date(Date.now() + REFRESH_TOKEN_TTL_SECONDS * 1000).toISOString();
}

async function issueRefreshToken(
  db: D1Database,
  userId: string,
): Promise<{ token: string; id: string }> {
  const refreshToken = generateOpaqueToken();
  const tokenHash = await hashRefreshToken(refreshToken);
  const expiresAt = refreshTokenExpiresAt();
  const id = crypto.randomUUID();

  await db
    .prepare(
      `
    INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at)
    VALUES (?, ?, ?, ?)
  `,
    )
    .bind(id, userId, tokenHash, expiresAt)
    .run();

  return { token: refreshToken, id };
}

async function issueAuthTokens(
  db: D1Database,
  userId: string,
  secret: string,
): Promise<{ token: string; refreshToken: string; refreshTokenId: string }> {
  const token = await generateToken(userId, secret);
  const { token: refreshToken, id: refreshTokenId } = await issueRefreshToken(db, userId);
  return { token, refreshToken, refreshTokenId };
}

// 验证 JWT token
async function verifyToken(token: string, secret: string): Promise<any> {
  const parts = token.split(".");
  if (parts.length !== 3) return null;

  const [headerBase64, payloadBase64, signatureBase64] = parts;
  const message = `${headerBase64}.${payloadBase64}`;

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );

  // 还原 base64url 到 base64
  const signaturePadded = signatureBase64.replace(/-/g, "+").replace(/_/g, "/");
  const signatureBytes = Uint8Array.from(atob(signaturePadded), (c) =>
    c.charCodeAt(0),
  );

  const valid = await crypto.subtle.verify(
    "HMAC",
    key,
    signatureBytes,
    encoder.encode(message),
  );
  if (!valid) return null;

  const payload = JSON.parse(
    atob(payloadBase64.replace(/-/g, "+").replace(/_/g, "/")),
  );
  if (payload.exp < Math.floor(Date.now() / 1000)) return null;

  return payload;
}

// 从请求中获取用户 ID
async function getUserIdFromRequest(
  request: Request,
  env: Env,
): Promise<string | null> {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return null;

  const token = authHeader.slice(7);
  const payload = await verifyToken(token, getJwtSecret(env));
  return payload?.userId || null;
}

async function getOptionalUserIdFromRequest(
  request: Request,
  env: Env,
): Promise<string | null> {
  try {
    return await getUserIdFromRequest(request, env);
  } catch {
    return null;
  }
}

async function getActiveUserFromRequest(
  request: Request,
  env: Env,
): Promise<any | null> {
  const userId = await getUserIdFromRequest(request, env);
  if (!userId) return null;
  await initDatabase(env.DB);
  const user = (await env.DB.prepare(
    "SELECT id, username, nickname, COALESCE(role, 'user') as role, COALESCE(is_disabled, 0) as is_disabled FROM users WHERE id = ?",
  )
    .bind(userId)
    .first()) as any;
  if (!user || user.is_disabled === 1) return null;
  return user;
}

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

async function initDatabase(db: D1Database): Promise<void> {
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
  // 宽限期轮换：记录旋转出的新 token ID，允许旧 token 在 ~60s 内重试
  await execSafely(
    db,
    `ALTER TABLE refresh_tokens ADD COLUMN rotated_to TEXT`,
    "migrate refresh_tokens rotated_to",
  );

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

const SECURITY_RULES_KV_KEY = "security_block_rules:v1";
const SECURITY_RULES_CACHE_TTL = 300; // 5 分钟

function getClientIp(request: Request): string {
  return (
    request.headers.get("CF-Connecting-IP") ||
    request.headers.get("X-Forwarded-For")?.split(",")[0]?.trim() ||
    ""
  );
}

// 从 KV 或 D1 获取活跃封禁规则，结果不含过期或已停用规则
async function getActiveSecurityRules(env: Env): Promise<any[]> {
  // 优先 KV
  try {
    const cached = await env.KV.get(SECURITY_RULES_KV_KEY, "json");
    if (Array.isArray(cached) && cached.length > 0) {
      return cached;
    }
  } catch {
    // KV 不可用，回源 D1
  }
  // D1 回源并回填 KV
  const allRules = await env.DB.prepare(
    `
    SELECT id, type, value, reason
    FROM security_block_rules
    WHERE is_active = 1
      AND (expires_at IS NULL OR expires_at > datetime('now'))
  `,
  ).all();
  const rules = (allRules.results || []) as any[];
  try {
    await env.KV.put(SECURITY_RULES_KV_KEY, JSON.stringify(rules), {
      expirationTtl: SECURITY_RULES_CACHE_TTL,
    });
  } catch {
    // 写缓存失败不阻塞请求
  }
  return rules;
}

async function checkSecurityBlock(
  request: Request,
  env: Env,
): Promise<Response | null> {
  try {
    await initDatabase(env.DB);
    const checks: [string, string][] = [
      ["device_id", request.headers.get("X-Device-Id") || ""],
      ["ip", getClientIp(request)],
      ["platform", request.headers.get("X-Platform") || ""],
      ["app_version", request.headers.get("X-App-Version") || ""],
      ["os_version", request.headers.get("X-OS-Version") || ""],
      ["device_model", request.headers.get("X-Device-Model") || ""],
    ].filter(([, value]) => value.length > 0) as [string, string][];
    if (checks.length === 0) return null;
    const rules = await getActiveSecurityRules(env);
    for (const rule of rules) {
      for (const [type, value] of checks) {
        if (rule.type === type && rule.value === value) {
          return json(
            {
              error: "当前设备或访问环境已被限制，请联系管理员",
              blocked: true,
              type: rule.type,
              reason: rule.reason || undefined,
            },
            403,
          );
        }
      }
    }
    return null;
  } catch (e) {
    console.error("SecurityBlock check error:", e);
    return null;
  }
}

// 用户注册
async function handleRegister(request: Request, env: Env): Promise<Response> {
  try {
    getJwtSecret(env);
    const body = (await request.json()) as any;
    const { username, password_hash, nickname } = body;

    if (!username || !password_hash) {
      return json({ error: "用户名和密码不能为空" }, 400);
    }

    if (username.length < 3 || username.length > 20) {
      return json({ error: "用户名长度需要 3-20 个字符" }, 400);
    }

    // 初始化数据库表
    await initDatabase(env.DB);

    // 检查用户名是否已存在（大小写不敏感）
    const existing = await env.DB.prepare(
      "SELECT id FROM users WHERE LOWER(username) = LOWER(?)",
    )
      .bind(username)
      .first();

    if (existing) {
      return json({ error: "用户名已存在" }, 409);
    }

    // 创建用户（统一转小写存储，PBKDF2 哈希密码，默认 role=user）
    const userId = crypto.randomUUID();
    // 新注册用户统一使用 SHA-256(password) 作为 PBKDF2 输入
    const passwordHash = await hashPassword(password_hash);
    const finalNickname = nickname || username;
    const normalizedUsername = username.toLowerCase();

    await env.DB.prepare(
      "INSERT INTO users (id, username, password_hash, nickname, role) VALUES (?, ?, ?, ?, 'user')",
    )
      .bind(userId, normalizedUsername, passwordHash, finalNickname)
      .run();

    // 生成 token
    const { token, refreshToken } = await issueAuthTokens(
      env.DB,
      userId,
      getJwtSecret(env),
    );

    return json({
      success: true,
      user: { id: userId, username, nickname: finalNickname, role: "user" },
      token,
      refreshToken,
    });
  } catch (e) {
    console.error("Register error:", e);
    const message = e instanceof Error ? e.message : "注册失败";
    return json({ error: message }, 500);
  }
}

// 用户登录
async function handleLogin(request: Request, env: Env): Promise<Response> {
  try {
    getJwtSecret(env);
    const body = (await request.json()) as any;
    const { username, password_hash, require_role } = body;

    if (!username || !password_hash) {
      return json({ error: "用户名和密码不能为空" }, 400);
    }

    // 初始化数据库表
    await initDatabase(env.DB);

    // 查找用户（大小写不敏感）
    const user = (await env.DB.prepare(
      "SELECT id, username, password_hash, nickname, COALESCE(role, 'user') as role, COALESCE(is_disabled, 0) as is_disabled FROM users WHERE LOWER(username) = LOWER(?)",
    )
      .bind(username)
      .first()) as any;

    if (!user) {
      return json({ error: "账号或密码错误" }, 401);
    }
    if (user.is_disabled === 1) {
      return json({ error: "账号已被禁用，请联系管理员" }, 403);
    }

    // 可选角色门控：studio 等共享 D1 的端点复用本接口，传 require_role='admin'
    // 让 app 在 hash 链与角色检查中一站式完成；非 admin 直接 403。
    const requireRole =
      typeof require_role === "string" ? require_role.toLowerCase() : "";
    if (requireRole === "admin" && user.role !== "admin") {
      return json({ error: "账号或密码错误" }, 401);
    }

    // 验证密码：PBKDF2 双层方案
    // client 发送 PBKDF2(password, static_salt, 10000)，服务端存储 PBKDF2(clientKey, random_salt)
    const clientKey = password_hash;
    const passwordValid = await verifyPassword(clientKey, user.password_hash);

    if (!passwordValid) {
      return json({ error: "账号或密码错误" }, 401);
    }

    // 旧格式升级到最新 PBKDF2 格式
    if (!user.password_hash.includes(":")) {
      const newHash = await hashPassword(clientKey);
      await env.DB.prepare("UPDATE users SET password_hash = ? WHERE id = ?")
        .bind(newHash, user.id)
        .run();
    }

    // 更新最后登录时间
    await env.DB.prepare(
      "UPDATE users SET last_login_at = datetime('now') WHERE id = ?",
    )
      .bind(user.id)
      .run();

    // 生成 token
    const { token, refreshToken } = await issueAuthTokens(
      env.DB,
      user.id,
      getJwtSecret(env),
    );

    return json({
      success: true,
      user: {
        id: user.id,
        username: user.username,
        nickname: user.nickname,
        role: user.role,
      },
      token,
      refreshToken,
    });
  } catch (e) {
    console.error("Login error:", e);
    const message = e instanceof Error ? e.message : "登录失败";
    return json({ error: message }, 500);
  }
}

// 刷新登录态，成功后轮换 refresh token
async function handleRefreshToken(
  request: Request,
  env: Env,
): Promise<Response> {
  try {
    getJwtSecret(env);
    const body = (await request.json()) as any;
    const { refreshToken } = body;

    if (!refreshToken || typeof refreshToken !== "string") {
      return json({ error: "缺少 refresh token" }, 400);
    }

    await initDatabase(env.DB);

    const tokenHash = await hashRefreshToken(refreshToken);
    const tokenRow = (await env.DB.prepare(
      `
      SELECT id, user_id, expires_at, revoked_at, rotated_to
      FROM refresh_tokens
      WHERE token_hash = ?
    `,
    )
      .bind(tokenHash)
      .first()) as any;

    if (!tokenRow) {
      return json({ error: "登录已过期，请重新登录" }, 401);
    }

    // 宽限期轮换：已吊销但在 60s 内的 token，沿 rotated_to 找到后继 token 再旋转
    if (tokenRow.revoked_at) {
      const revokedMs = Date.parse(tokenRow.revoked_at);
      const graceOk = Date.now() - revokedMs < 60_000 && tokenRow.rotated_to;
      if (!graceOk) {
        return json({ error: "登录已过期，请重新登录" }, 401);
      }
      // 找后继 token
      const successor = (await env.DB.prepare(
        `SELECT id, user_id, expires_at, revoked_at FROM refresh_tokens WHERE id = ?`,
      )
        .bind(tokenRow.rotated_to)
        .first()) as any;
      if (
        !successor ||
        successor.revoked_at ||
        Date.parse(successor.expires_at) <= Date.now()
      ) {
        return json({ error: "登录已过期，请重新登录" }, 401);
      }
      // 从后继 token 正常旋转
      tokenRow.id = successor.id;
      tokenRow.user_id = successor.user_id;
      tokenRow.revoked_at = null;
    }

    if (Date.parse(tokenRow.expires_at) <= Date.now()) {
      return json({ error: "登录已过期，请重新登录" }, 401);
    }

    const user = (await env.DB.prepare(
      "SELECT id, username, nickname, COALESCE(role, 'user') as role, COALESCE(is_disabled, 0) as is_disabled FROM users WHERE id = ?",
    )
      .bind(tokenRow.user_id)
      .first()) as any;

    if (!user) {
      return json({ error: "用户不存在" }, 404);
    }
    if (user.is_disabled === 1) {
      await env.DB.prepare(
        `
        UPDATE refresh_tokens
        SET revoked_at = COALESCE(revoked_at, datetime('now')), last_used_at = datetime('now')
        WHERE id = ?
      `,
      )
        .bind(tokenRow.id)
        .run();
      return json({ error: "账号已被禁用，请联系管理员" }, 403);
    }

    const { token, refreshToken: nextRefreshToken, refreshTokenId } = await issueAuthTokens(
      env.DB,
      user.id,
      getJwtSecret(env),
    );

    // 吊销当前 token，并记录宽限期链接
    await env.DB.prepare(
      `
      UPDATE refresh_tokens
      SET revoked_at = datetime('now'), last_used_at = datetime('now'), rotated_to = ?
      WHERE id = ?
    `,
    )
      .bind(refreshTokenId, tokenRow.id)
      .run();

    return json({
      success: true,
      user: {
        id: user.id,
        username: user.username,
        nickname: user.nickname,
        role: user.role,
      },
      token,
      refreshToken: nextRefreshToken,
    });
  } catch (e) {
    console.error("RefreshToken error:", e);
    return json({ error: "刷新登录状态失败" }, 500);
  }
}

// 退出登录，撤销当前 refresh token
async function handleLogout(request: Request, env: Env): Promise<Response> {
  try {
    const body = (await request.json().catch(() => ({}))) as any;
    const { refreshToken } = body;

    if (refreshToken && typeof refreshToken === "string") {
      await initDatabase(env.DB);
      const tokenHash = await hashRefreshToken(refreshToken);
      await env.DB.prepare(
        `
        UPDATE refresh_tokens
        SET revoked_at = COALESCE(revoked_at, datetime('now'))
        WHERE token_hash = ?
      `,
      )
        .bind(tokenHash)
        .run();
    }

    return json({ success: true });
  } catch (e) {
    console.error("Logout error:", e);
    return json({ error: "退出登录失败" }, 500);
  }
}

// 获取当前用户信息
async function handleGetMe(request: Request, env: Env): Promise<Response> {
  try {
    const userId = await getUserIdFromRequest(request, env);
    if (!userId) {
      return json({ error: "未登录或 token 已过期" }, 401);
    }

    // 初始化数据库表
    await initDatabase(env.DB);

    const user = await env.DB.prepare(
      "SELECT id, username, nickname, COALESCE(role, 'user') as role, COALESCE(is_disabled, 0) as is_disabled, created_at, last_login_at FROM users WHERE id = ?",
    )
      .bind(userId)
      .first();

    if (!user) {
      return json({ error: "用户不存在" }, 404);
    }
    if ((user as any).is_disabled === 1) {
      return json({ error: "账号已被禁用，请联系管理员" }, 403);
    }

    return json({ success: true, user });
  } catch (e) {
    console.error("GetMe error:", e);
    return json({ error: "获取用户信息失败" }, 500);
  }
}

// 修改密码
async function handleChangePassword(
  request: Request,
  env: Env,
): Promise<Response> {
  try {
    const activeUser = await getActiveUserFromRequest(request, env);
    if (!activeUser) {
      return json({ error: "未登录或 token 已过期" }, 401);
    }
    const userId = activeUser.id;

    const body = (await request.json()) as any;
    const { old_password_hash, new_password_hash } = body;

    if (!old_password_hash || !new_password_hash) {
      return json({ error: "请输入原密码和新密码" }, 400);
    }

    if (!new_password_hash || new_password_hash.length < 10) {
      return json({ error: "新密码哈希格式无效" }, 400);
    }

    await initDatabase(env.DB);

    const user = (await env.DB.prepare(
      "SELECT id, password_hash FROM users WHERE id = ?",
    )
      .bind(userId)
      .first()) as any;

    if (!user) {
      return json({ error: "用户不存在" }, 404);
    }

    const passwordValid = await verifyPassword(
      old_password_hash,
      user.password_hash,
    );
    if (!passwordValid) {
      return json({ error: "原密码错误" }, 401);
    }

    const newHash = await hashPassword(new_password_hash);
    await env.DB.prepare("UPDATE users SET password_hash = ? WHERE id = ?")
      .bind(newHash, userId)
      .run();

    await env.DB.prepare(
      `
      UPDATE refresh_tokens
      SET revoked_at = COALESCE(revoked_at, datetime('now'))
      WHERE user_id = ?
    `,
    )
      .bind(userId)
      .run();

    return json({ success: true, message: "密码修改成功" });
  } catch (e) {
    console.error("ChangePassword error:", e);
    return json({ error: "修改密码失败" }, 500);
  }
}

const TICKET_TYPES = new Set(["password_reset", "feedback", "question"]);
const TICKET_STATUSES = new Set([
  "pending",
  "processing",
  "needs_info",
  "rejected",
  "resolved",
  "closed",
]);
const ANALYTICS_SECTIONS = new Set([
  "dashboard",
  "catalog",
  "practice",
  "prep",
  "mastery",
  "profile",
]);
const ANALYTICS_FEATURES = new Set([
  "ai_eval",
  "manual_sync",
  "ticket_submit",
  "login",
]);

function asString(value: unknown, max = 200): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function parseJsonArray(value: unknown): string[] {
  if (Array.isArray(value)) return value.map((v) => String(v)).slice(0, 5);
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value);
      return Array.isArray(parsed)
        ? parsed.map((v) => String(v)).slice(0, 5)
        : [];
    } catch {
      return [];
    }
  }
  return [];
}

const TICKET_IMAGE_MAX = 3; // 最多 3 张
const TICKET_IMAGE_MAX_BYTES = 150 * 1024; // 单图 ≤ 150KB（解 base64 后）
const TICKET_IMAGE_B64_HEAD = /^data:image\/(jpeg|png|webp|gif);base64,/i;

/**
 * 工单图片 URL 解析：限 3 张、限 150KB，仅接受 http(s):// 或 data:image/{jpeg,png,webp,gif};base64,
 * 直接存 D1（不依赖 R2 之类的对象存储）。
 */
function parseImageUrls(value: unknown): string[] {
  const raw: string[] = [];
  if (Array.isArray(value)) {
    for (const v of value) if (typeof v === "string") raw.push(v);
  } else if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value);
      if (Array.isArray(parsed))
        for (const v of parsed) if (typeof v === "string") raw.push(v);
    } catch {
      // 非 JSON 字符串，忽略
    }
  }
  const out: string[] = [];
  for (const item of raw) {
    if (out.length >= TICKET_IMAGE_MAX) break;
    if (item.length > 256 * 1024) continue; // 整体超长直接丢
    if (item.startsWith("http://") || item.startsWith("https://")) {
      out.push(item.slice(0, 2048));
      continue;
    }
    if (TICKET_IMAGE_B64_HEAD.test(item)) {
      const headLen = item.match(TICKET_IMAGE_B64_HEAD)![0].length;
      const b64 = item.slice(headLen);
      // base64 长度 ≈ 4/3 倍字节数
      if (b64.length > Math.ceil((TICKET_IMAGE_MAX_BYTES * 4) / 3) + 32)
        continue;
      out.push(item);
    }
  }
  return out;
}

function normalizeTicket(row: any): any {
  return {
    ...row,
    image_urls: parseImageUrls(row.image_urls),
  };
}

function isUuidLike(value: string): boolean {
  return /^[a-zA-Z0-9_-]{8,80}$/.test(value);
}

// =====================================================================
// 管理员操作（共享给 app 后台和 studio）
// =====================================================================

async function requireAdmin(
  request: Request,
  env: Env,
): Promise<{ id: string; role: string } | Response> {
  const user = await getActiveUserFromRequest(request, env);
  if (!user) return json({ error: "未登录或 token 已过期" }, 401);
  if (user.role !== "admin") return json({ error: "需要管理员权限" }, 403);
  return user;
}

/**
 * Admin 重置用户密码（无原密码，仅管理员可调）。
 * POST /admin/users/:id/reset-password  body: { password_hash }
 * 哈希到新格式并撤销该用户所有 refresh token。
 */
async function handleAdminResetPassword(
  request: Request,
  env: Env,
): Promise<Response> {
  try {
    const admin = await requireAdmin(request, env);
    if (admin instanceof Response) return admin;
    const userId = request.url.split("/admin/users/")[1]?.split("/")[0];
    if (!userId) return json({ error: "userId 无效" }, 400);
    const body = (await request.json()) as any;
    // 只接受客户端预哈希的 password_hash（PBKDF2(password, static_salt)），
    // 不再接受明文密码，与 login 保持一致。
    const clientKey = asString(body.password_hash, 200);
    if (!clientKey || clientKey.length < 6)
      return json({ error: "请提供 password_hash，密码至少 6 个字符" }, 400);
    await initDatabase(env.DB);
    const target = (await env.DB.prepare(
      "SELECT id, username FROM users WHERE id = ?",
    )
      .bind(userId)
      .first()) as any;
    if (!target) return json({ error: "用户不存在" }, 404);
    // 与登录一致：PBKDF2(clientKey, random_salt) = 格式 3 存储
    const newHash = await hashPassword(clientKey);
    await env.DB.prepare(
      "UPDATE users SET password_hash = ?, updated_at = datetime('now') WHERE id = ?",
    )
      .bind(newHash, userId)
      .run();
    await env.DB.prepare(
      "UPDATE refresh_tokens SET revoked_at = COALESCE(revoked_at, datetime('now')) WHERE user_id = ?",
    )
      .bind(userId)
      .run();
    return json({ success: true, userId, username: target.username });
  } catch (e) {
    console.error("AdminResetPassword error:", e);
    return json({ error: "重置密码失败" }, 500);
  }
}

/**
 * Admin 删除工单。
 * DELETE /admin/tickets/:id
 * 工单图片目前是 base64 存 D1（无 R2），直接删 D1 行即可。
 */
async function handleAdminDeleteTicket(
  request: Request,
  env: Env,
): Promise<Response> {
  try {
    const admin = await requireAdmin(request, env);
    if (admin instanceof Response) return admin;
    const ticketId = request.url
      .split("/admin/tickets/")[1]
      ?.split("?")[0]
      ?.split("/")[0];
    if (!ticketId) return json({ error: "ticketId 无效" }, 400);
    await initDatabase(env.DB);
    const row = (await env.DB.prepare("SELECT id FROM tickets WHERE id = ?")
      .bind(ticketId)
      .first()) as any;
    if (!row) return json({ error: "工单不存在" }, 404);
    await env.DB.prepare("DELETE FROM tickets WHERE id = ?")
      .bind(ticketId)
      .run();
    return json({ success: true, ticketId });
  } catch (e) {
    console.error("AdminDeleteTicket error:", e);
    return json({ error: "删除工单失败" }, 500);
  }
}

async function handleCreateTicket(
  request: Request,
  env: Env,
): Promise<Response> {
  try {
    const user = await getActiveUserFromRequest(request, env);
    if (!user) return json({ error: "未登录或账号不可用" }, 401);
    const body = (await request.json()) as any;
    const type = asString(body.type, 40);
    const subject = asString(body.subject, 120);
    const description = asString(body.description, 4000);
    const imageUrls = parseImageUrls(body.image_urls);

    if (!TICKET_TYPES.has(type) || type === "password_reset") {
      return json({ error: "工单类型无效" }, 400);
    }
    if (!subject || !description) {
      return json({ error: "标题和描述不能为空" }, 400);
    }

    const id = crypto.randomUUID();
    await initDatabase(env.DB);
    await env.DB.prepare(
      `
      INSERT INTO tickets (id, user_id, type, subject, description, image_urls, status)
      VALUES (?, ?, ?, ?, ?, ?, 'pending')
    `,
    )
      .bind(id, user.id, type, subject, description, JSON.stringify(imageUrls))
      .run();

    const ticket = await env.DB.prepare("SELECT id, user_id, account_username, contact, type, subject, description, image_urls, status, admin_reply, created_at, resolved_at FROM tickets WHERE id = ?")
      .bind(id)
      .first();
    return json({ success: true, ticket: normalizeTicket(ticket) });
  } catch (e) {
    console.error("CreateTicket error:", e);
    return json({ error: "提交工单失败" }, 500);
  }
}

async function handleCreatePasswordResetTicket(
  request: Request,
  env: Env,
): Promise<Response> {
  try {
    await initDatabase(env.DB);
    const body = (await request.json()) as any;
    const accountUsername = asString(body.account_username, 80).toLowerCase();
    const contact = asString(body.contact, 160);
    const description = asString(body.description, 2000);
    if (!accountUsername || !contact || description.length < 10) {
      return json(
        { error: "请填写用户名、联系方式和至少 10 个字符的说明" },
        400,
      );
    }

    const id = crypto.randomUUID();
    await env.DB.prepare(
      `
      INSERT INTO tickets (id, account_username, contact, type, subject, description, image_urls, status)
      VALUES (?, ?, ?, 'password_reset', '密码重置申请', ?, '[]', 'pending')
    `,
    )
      .bind(id, accountUsername, contact, description)
      .run();

    return json({
      success: true,
      ticket: normalizeTicket(
        await env.DB.prepare("SELECT id, user_id, account_username, contact, type, subject, description, image_urls, status, admin_reply, created_at, resolved_at FROM tickets WHERE id = ?")
          .bind(id)
          .first(),
      ),
      message: {
        zh: "已提交密码重置申请，管理员会人工审核。请留意你填写的联系方式；如信息不足，管理员会联系你补充。",
        en: "Your password reset request has been submitted. An administrator will review it manually. Please watch the contact method you provided; if more information is needed, the administrator will contact you.",
      },
    });
  } catch (e) {
    console.error("CreatePasswordResetTicket error:", e);
    return json({ error: "提交密码重置申请失败" }, 500);
  }
}

async function handleGetMyTickets(
  request: Request,
  env: Env,
): Promise<Response> {
  try {
    const user = await getActiveUserFromRequest(request, env);
    if (!user) return json({ error: "未登录或账号不可用" }, 401);
    const rows = await env.DB.prepare(
      "SELECT id, user_id, account_username, contact, type, subject, description, image_urls, status, admin_reply, created_at, resolved_at FROM tickets WHERE user_id = ? ORDER BY created_at DESC LIMIT 100",
    )
      .bind(user.id)
      .all();
    return json({
      success: true,
      tickets: (rows.results || []).map(normalizeTicket),
    });
  } catch (e) {
    console.error("GetMyTickets error:", e);
    return json({ error: "获取工单失败" }, 500);
  }
}

async function handleBindDevice(request: Request, env: Env): Promise<Response> {
  try {
    const user = await getActiveUserFromRequest(request, env);
    if (!user) return json({ error: "未登录或账号不可用" }, 401);
    const body = (await request.json().catch(() => ({}))) as any;
    const deviceId = asString(body.device_id, 80);
    if (!isUuidLike(deviceId)) return json({ error: "设备 ID 无效" }, 400);
    await initDatabase(env.DB);
    await env.DB.prepare(
      `
      INSERT INTO user_devices (device_id, user_id, first_seen_at, last_seen_at, last_login_at)
      VALUES (?, ?, datetime('now'), datetime('now'), datetime('now'))
      ON CONFLICT(device_id) DO UPDATE SET
        user_id = excluded.user_id,
        last_seen_at = datetime('now'),
        last_login_at = datetime('now')
    `,
    )
      .bind(deviceId, user.id)
      .run();
    return json({ success: true });
  } catch (e) {
    console.error("BindDevice error:", e);
    return json({ error: "绑定设备失败" }, 500);
  }
}

async function handleAnalyticsBatch(
  request: Request,
  env: Env,
): Promise<Response> {
  try {
    await initDatabase(env.DB);
    const body = (await request.json()) as any;
    const batchId = asString(body.batch_id, 80);
    const deviceId = asString(body.device_id, 80);
    if (!isUuidLike(batchId) || !isUuidLike(deviceId)) {
      return json({ error: "统计批次或设备 ID 无效" }, 400);
    }

    const existing = await env.DB.prepare(
      "SELECT batch_id FROM analytics_batches WHERE batch_id = ?",
    )
      .bind(batchId)
      .first();
    if (existing) return json({ success: true, deduped: true });

    const userId = await getOptionalUserIdFromRequest(request, env);
    const platform = asString(body.platform, 40) || "unknown";
    const appVersion = asString(body.app_version, 40) || "unknown";
    const osVersion = asString(body.os_version, 80) || "unknown";
    const deviceModel = asString(body.device_model, 80) || "unknown";
    const days = Array.isArray(body.days) ? body.days.slice(0, 7) : [];
    let totalOpen = 0;
    let totalDuration = 0;

    await env.DB.prepare(
      `
      INSERT INTO analytics_batches (batch_id, device_id, user_id)
      VALUES (?, ?, ?)
    `,
    )
      .bind(batchId, deviceId, userId)
      .run();

    for (const day of days) {
      const date = asString(day.date, 10);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) continue;
      const openCount = Math.max(
        0,
        Math.min(Number(day.open_count) || 0, 1000),
      );
      const durationSeconds = Math.max(
        0,
        Math.min(Number(day.active_seconds) || 0, 24 * 60 * 60),
      );
      totalOpen += openCount;
      totalDuration += durationSeconds;
      await env.DB.prepare(
        `
        INSERT INTO daily_visit_stats (date, device_id, user_id, platform, app_version, open_count, duration_seconds, last_seen_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(date, device_id) DO UPDATE SET
          user_id = COALESCE(excluded.user_id, daily_visit_stats.user_id),
          platform = excluded.platform,
          app_version = excluded.app_version,
          open_count = daily_visit_stats.open_count + excluded.open_count,
          duration_seconds = MIN(86400, daily_visit_stats.duration_seconds + excluded.duration_seconds),
          last_seen_at = datetime('now')
      `,
      )
        .bind(
          date,
          deviceId,
          userId,
          platform,
          appVersion,
          openCount,
          durationSeconds,
        )
        .run();

      await upsertCountMap(
        env.DB,
        "daily_section_stats",
        "section",
        date,
        deviceId,
        userId,
        day.section_counts,
        ANALYTICS_SECTIONS,
      );
      await upsertCountMap(
        env.DB,
        "daily_feature_stats",
        "feature",
        date,
        deviceId,
        userId,
        day.feature_counts,
        ANALYTICS_FEATURES,
      );
    }

    await env.DB.prepare(
      `
      INSERT INTO user_devices (device_id, user_id, platform, app_version, os_version, device_model, first_seen_at, last_seen_at, visit_count, total_duration_seconds)
      VALUES (?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'), ?, ?)
      ON CONFLICT(device_id) DO UPDATE SET
        user_id = COALESCE(excluded.user_id, user_devices.user_id),
        platform = excluded.platform,
        app_version = excluded.app_version,
        os_version = excluded.os_version,
        device_model = excluded.device_model,
        last_seen_at = datetime('now'),
        visit_count = user_devices.visit_count + excluded.visit_count,
        total_duration_seconds = user_devices.total_duration_seconds + excluded.total_duration_seconds
    `,
    )
      .bind(
        deviceId,
        userId,
        platform,
        appVersion,
        osVersion,
        deviceModel,
        totalOpen,
        totalDuration,
      )
      .run();

    return json({ success: true });
  } catch (e) {
    console.error("AnalyticsBatch error:", e);
    return json({ error: "访问统计上报失败" }, 500);
  }
}

async function upsertCountMap(
  db: D1Database,
  table: string,
  column: string,
  date: string,
  deviceId: string,
  userId: string | null,
  value: any,
  allowed: Set<string>,
): Promise<void> {
  if (!value || typeof value !== "object") return;
  for (const [key, rawCount] of Object.entries(value).slice(0, 20)) {
    if (!allowed.has(key)) continue;
    const count = Math.max(0, Math.min(Number(rawCount) || 0, 1000));
    if (count === 0) continue;
    await db
      .prepare(
        `
      INSERT INTO ${table} (date, device_id, user_id, ${column}, count)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(date, device_id, ${column}) DO UPDATE SET
        user_id = COALESCE(excluded.user_id, ${table}.user_id),
        count = ${table}.count + excluded.count
    `,
      )
      .bind(date, deviceId, userId, key, count)
      .run();
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "access-control-allow-origin": "*",
    },
  });
}

interface Env {
  CONTENT_PRIMARY_BASE_URL?: string;
  CONTENT_BACKUP_BASE_URL?: string;
  DB: D1Database;
  JWT_SECRET: string;
  KV: KVNamespace;
}

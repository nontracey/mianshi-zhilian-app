export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // 处理 CORS 预检请求
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        },
      });
    }

    if (url.pathname === '/health') {
      return json({ ok: true, service: 'mianshi-zhilian-api', version: '0.2.0' });
    }

    if (url.pathname === '/config') {
      return json({
        contentManifestUrl: env.CONTENT_MANIFEST_URL,
        testContentBaseUrl: env.TEST_CONTENT_BASE_URL,
        prodContentBaseUrl: env.PROD_CONTENT_BASE_URL,
        updateManifestUrl: 'https://github.com/nontracey/mianshi-zhilian-app/releases/latest',
        aiProxyEnabled: true,
      });
    }

    // 用户注册
    if (url.pathname === '/auth/register' && request.method === 'POST') {
      return handleRegister(request, env);
    }

    // 用户登录
    if (url.pathname === '/auth/login' && request.method === 'POST') {
      return handleLogin(request, env);
    }

    // 刷新登录态
    if (url.pathname === '/auth/refresh' && request.method === 'POST') {
      return handleRefreshToken(request, env);
    }

    // 退出登录
    if (url.pathname === '/auth/logout' && request.method === 'POST') {
      return handleLogout(request, env);
    }

    // 获取用户信息（需要认证）
    if (url.pathname === '/auth/me' && request.method === 'GET') {
      return handleGetMe(request, env);
    }

    // 修改密码（需要认证）
    if (url.pathname === '/auth/change-password' && request.method === 'POST') {
      return handleChangePassword(request, env);
    }

    // 云端同步（需要认证）
    if (url.pathname === '/sync/progress' && request.method === 'POST') {
      return handleSyncProgress(request, env);
    }

    if (url.pathname === '/sync/progress' && request.method === 'GET') {
      return handleGetProgress(request, env);
    }

    // 代理测试环境内容: /content/test/* → TEST_CONTENT_BASE_URL/*
    if (url.pathname.startsWith('/content/test/')) {
      const subPath = url.pathname.slice('/content/test/'.length);
      const targetUrl = `${env.TEST_CONTENT_BASE_URL}/${subPath}`;
      return proxyFetch(targetUrl, request);
    }

    // 代理发布环境内容: /content/production/* → PROD_CONTENT_BASE_URL/*
    if (url.pathname.startsWith('/content/production/')) {
      const subPath = url.pathname.slice('/content/production/'.length);
      const targetUrl = `${env.PROD_CONTENT_BASE_URL}/${subPath}`;
      return proxyFetch(targetUrl, request);
    }

    if (url.pathname === '/ai/proxy' && request.method === 'POST') {
      return handleAiProxy(request, env);
    }

    if (url.pathname.startsWith('/sync/')) {
      return json({ ok: true, mode: 'local-first', queued: true });
    }

    return json({ error: 'Not found' }, 404);
  },
};

async function proxyFetch(targetUrl: string, originalRequest: Request): Promise<Response> {
  try {
    const response = await fetch(targetUrl, {
      method: originalRequest.method,
      headers: {
        'Accept': originalRequest.headers.get('Accept') || 'application/json',
      },
      redirect: 'follow',
    });
    const body = await response.text();
    return new Response(body, {
      status: response.status,
      headers: {
        'content-type': response.headers.get('content-type') || 'application/json; charset=utf-8',
        'access-control-allow-origin': '*',
        'cache-control': 'public, max-age=300',
      },
    });
  } catch (e) {
    console.error('ProxyFetch error:', e);
    return json({ error: '上游请求失败' }, 502);
  }
}

// PBKDF2 密码哈希（100K 迭代 + 16 字节随机 salt）
const PBKDF2_ITERATIONS = 100_000;
const SALT_BYTES = 16;
const HASH_BYTES = 32;

function toHex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function fromHex(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }
  return bytes;
}

async function hashPassword(password: string, existingSalt?: string): Promise<string> {
  const encoder = new TextEncoder();
  const salt = existingSalt ? fromHex(existingSalt) : crypto.getRandomValues(new Uint8Array(SALT_BYTES));
  const key = await crypto.subtle.importKey('raw', encoder.encode(password), 'PBKDF2', false, ['deriveBits']);
  const derivedBits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations: PBKDF2_ITERATIONS, hash: 'SHA-256' },
    key,
    HASH_BYTES * 8,
  );
  const saltHex = toHex(salt.buffer);
  const hashHex = toHex(derivedBits);
  return `${saltHex}:${hashHex}`;
}

// 兼容旧格式（无 salt 的纯 SHA-256）和新格式（salt:hash）
async function verifyPassword(password: string, storedHash: string): Promise<boolean> {
  if (storedHash.includes(':')) {
    // 新格式: salt:pbkdf2hash
    const [salt] = storedHash.split(':');
    const recomputed = await hashPassword(password, salt);
    return recomputed === storedHash;
  }
  // 旧格式: 纯 SHA-256（无 salt），验证后会自动升级
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hash = await crypto.subtle.digest('SHA-256', data);
  const legacyHash = toHex(hash);
  return legacyHash === storedHash;
}

// 旧版 SHA-256 哈希（仅用于识别旧格式，不用于新密码）
async function legacyHash(password: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return toHex(hash);
}

const ACCESS_TOKEN_TTL_SECONDS = 24 * 60 * 60; // 24 小时
const REFRESH_TOKEN_TTL_SECONDS = 90 * 24 * 60 * 60; // 90 天未使用需重新登录
const REFRESH_TOKEN_BYTES = 32;

// 生成简单的 JWT token
async function generateToken(userId: string, secret: string): Promise<string> {
  const header = { alg: 'HS256', typ: 'JWT' };
  const payload = {
    userId,
    exp: Math.floor(Date.now() / 1000) + ACCESS_TOKEN_TTL_SECONDS,
  };

  const headerBase64 = btoa(JSON.stringify(header)).replace(/=/g, '');
  const payloadBase64 = btoa(JSON.stringify(payload)).replace(/=/g, '');
  const message = `${headerBase64}.${payloadBase64}`;

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(message));
  const signatureBase64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');

  return `${message}.${signatureBase64}`;
}

function generateOpaqueToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(REFRESH_TOKEN_BYTES));
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

async function hashRefreshToken(token: string): Promise<string> {
  const encoder = new TextEncoder();
  const hash = await crypto.subtle.digest('SHA-256', encoder.encode(token));
  return toHex(hash);
}

function refreshTokenExpiresAt(): string {
  return new Date(Date.now() + REFRESH_TOKEN_TTL_SECONDS * 1000).toISOString();
}

async function issueRefreshToken(db: D1Database, userId: string): Promise<string> {
  const refreshToken = generateOpaqueToken();
  const tokenHash = await hashRefreshToken(refreshToken);
  const expiresAt = refreshTokenExpiresAt();

  await db.prepare(`
    INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at)
    VALUES (?, ?, ?, ?)
  `)
    .bind(crypto.randomUUID(), userId, tokenHash, expiresAt)
    .run();

  return refreshToken;
}

async function issueAuthTokens(db: D1Database, userId: string, secret: string): Promise<{ token: string; refreshToken: string }> {
  const token = await generateToken(userId, secret);
  const refreshToken = await issueRefreshToken(db, userId);
  return { token, refreshToken };
}

// 验证 JWT token
async function verifyToken(token: string, secret: string): Promise<any> {
  const parts = token.split('.');
  if (parts.length !== 3) return null;

  const [headerBase64, payloadBase64, signatureBase64] = parts;
  const message = `${headerBase64}.${payloadBase64}`;

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['verify']
  );

  // 还原 base64url 到 base64
  const signaturePadded = signatureBase64.replace(/-/g, '+').replace(/_/g, '/');
  const signatureBytes = Uint8Array.from(atob(signaturePadded), (c) => c.charCodeAt(0));

  const valid = await crypto.subtle.verify('HMAC', key, signatureBytes, encoder.encode(message));
  if (!valid) return null;

  const payload = JSON.parse(atob(payloadBase64.replace(/-/g, '+').replace(/_/g, '/')));
  if (payload.exp < Math.floor(Date.now() / 1000)) return null;

  return payload;
}

// 从请求中获取用户 ID
async function getUserIdFromRequest(request: Request, env: Env): Promise<string | null> {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return null;

  const token = authHeader.slice(7);
  const payload = await verifyToken(token, env.JWT_SECRET);
  return payload?.userId || null;
}

// 初始化数据库表
async function initDatabase(db: D1Database): Promise<void> {
  await db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      nickname TEXT,
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
      created_at TEXT DEFAULT (datetime('now')),
      last_used_at TEXT,
      FOREIGN KEY (user_id) REFERENCES users(id)
    );
    CREATE INDEX IF NOT EXISTS idx_refresh_tokens_hash ON refresh_tokens(token_hash);
    CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens(user_id);
  `);
}

// 用户注册
async function handleRegister(request: Request, env: Env): Promise<Response> {
  try {
    const body = await request.json() as any;
    const { username, password, nickname } = body;

    if (!username || !password) {
      return json({ error: '用户名和密码不能为空' }, 400);
    }

    if (username.length < 3 || username.length > 20) {
      return json({ error: '用户名长度需要 3-20 个字符' }, 400);
    }

    if (password.length < 6) {
      return json({ error: '密码长度至少 6 个字符' }, 400);
    }

    // 初始化数据库表
    await initDatabase(env.DB);

    // 检查用户名是否已存在（大小写不敏感）
    const existing = await env.DB.prepare('SELECT id FROM users WHERE LOWER(username) = LOWER(?)')
      .bind(username)
      .first();

    if (existing) {
      return json({ error: '用户名已存在' }, 409);
    }

    // 创建用户（统一转小写存储，PBKDF2 哈希密码）
    const userId = crypto.randomUUID();
    const passwordHash = await hashPassword(password);
    const finalNickname = nickname || username;
    const normalizedUsername = username.toLowerCase();

    await env.DB.prepare(
      'INSERT INTO users (id, username, password_hash, nickname) VALUES (?, ?, ?, ?)'
    )
      .bind(userId, normalizedUsername, passwordHash, finalNickname)
      .run();

    // 生成 token
    const { token, refreshToken } = await issueAuthTokens(env.DB, userId, env.JWT_SECRET);

    return json({
      success: true,
      user: { id: userId, username, nickname: finalNickname },
      token,
      refreshToken,
    });
  } catch (e) {
    console.error('Register error:', e);
    return json({ error: '注册失败' }, 500);
  }
}

// 用户登录
async function handleLogin(request: Request, env: Env): Promise<Response> {
  try {
    const body = await request.json() as any;
    const { username, password } = body;

    if (!username || !password) {
      return json({ error: '用户名和密码不能为空' }, 400);
    }

    // 初始化数据库表
    await initDatabase(env.DB);

    // 查找用户（大小写不敏感）
    const user = await env.DB.prepare(
      'SELECT id, username, password_hash, nickname FROM users WHERE LOWER(username) = LOWER(?)'
    )
      .bind(username)
      .first() as any;

    if (!user) {
      return json({ error: '用户名或密码错误' }, 401);
    }

    // 验证密码（兼容旧 SHA-256 和新 PBKDF2 格式）
    const passwordValid = await verifyPassword(password, user.password_hash);
    if (!passwordValid) {
      return json({ error: '用户名或密码错误' }, 401);
    }

    // 如果是旧格式哈希，自动升级为 PBKDF2
    if (!user.password_hash.includes(':')) {
      const newHash = await hashPassword(password);
      await env.DB.prepare('UPDATE users SET password_hash = ? WHERE id = ?')
        .bind(newHash, user.id)
        .run();
    }

    // 更新最后登录时间
    await env.DB.prepare('UPDATE users SET last_login_at = datetime(\'now\') WHERE id = ?')
      .bind(user.id)
      .run();

    // 生成 token
    const { token, refreshToken } = await issueAuthTokens(env.DB, user.id, env.JWT_SECRET);

    return json({
      success: true,
      user: { id: user.id, username: user.username, nickname: user.nickname },
      token,
      refreshToken,
    });
  } catch (e) {
    console.error('Login error:', e);
    return json({ error: '登录失败' }, 500);
  }
}

// 刷新登录态，成功后轮换 refresh token
async function handleRefreshToken(request: Request, env: Env): Promise<Response> {
  try {
    const body = await request.json() as any;
    const { refreshToken } = body;

    if (!refreshToken || typeof refreshToken !== 'string') {
      return json({ error: '缺少 refresh token' }, 400);
    }

    await initDatabase(env.DB);

    const tokenHash = await hashRefreshToken(refreshToken);
    const tokenRow = await env.DB.prepare(`
      SELECT id, user_id, expires_at, revoked_at
      FROM refresh_tokens
      WHERE token_hash = ?
    `)
      .bind(tokenHash)
      .first() as any;

    if (!tokenRow || tokenRow.revoked_at || Date.parse(tokenRow.expires_at) <= Date.now()) {
      return json({ error: '登录已过期，请重新登录' }, 401);
    }

    const user = await env.DB.prepare(
      'SELECT id, username, nickname FROM users WHERE id = ?'
    )
      .bind(tokenRow.user_id)
      .first() as any;

    if (!user) {
      return json({ error: '用户不存在' }, 404);
    }

    await env.DB.prepare(`
      UPDATE refresh_tokens
      SET revoked_at = datetime('now'), last_used_at = datetime('now')
      WHERE id = ?
    `)
      .bind(tokenRow.id)
      .run();

    const { token, refreshToken: nextRefreshToken } = await issueAuthTokens(env.DB, user.id, env.JWT_SECRET);

    return json({
      success: true,
      user: { id: user.id, username: user.username, nickname: user.nickname },
      token,
      refreshToken: nextRefreshToken,
    });
  } catch (e) {
    console.error('RefreshToken error:', e);
    return json({ error: '刷新登录状态失败' }, 500);
  }
}

// 退出登录，撤销当前 refresh token
async function handleLogout(request: Request, env: Env): Promise<Response> {
  try {
    const body = await request.json().catch(() => ({})) as any;
    const { refreshToken } = body;

    if (refreshToken && typeof refreshToken === 'string') {
      await initDatabase(env.DB);
      const tokenHash = await hashRefreshToken(refreshToken);
      await env.DB.prepare(`
        UPDATE refresh_tokens
        SET revoked_at = COALESCE(revoked_at, datetime('now'))
        WHERE token_hash = ?
      `)
        .bind(tokenHash)
        .run();
    }

    return json({ success: true });
  } catch (e) {
    console.error('Logout error:', e);
    return json({ error: '退出登录失败' }, 500);
  }
}

// 获取当前用户信息
async function handleGetMe(request: Request, env: Env): Promise<Response> {
  try {
    const userId = await getUserIdFromRequest(request, env);
    if (!userId) {
      return json({ error: '未登录或 token 已过期' }, 401);
    }

    // 初始化数据库表
    await initDatabase(env.DB);

    const user = await env.DB.prepare(
      'SELECT id, username, nickname, created_at, last_login_at FROM users WHERE id = ?'
    )
      .bind(userId)
      .first();

    if (!user) {
      return json({ error: '用户不存在' }, 404);
    }

    return json({ success: true, user });
  } catch (e) {
    console.error('GetMe error:', e);
    return json({ error: '获取用户信息失败' }, 500);
  }
}

// 修改密码
async function handleChangePassword(request: Request, env: Env): Promise<Response> {
  try {
    const userId = await getUserIdFromRequest(request, env);
    if (!userId) {
      return json({ error: '未登录或 token 已过期' }, 401);
    }

    const body = await request.json() as any;
    const { oldPassword, newPassword } = body;

    if (!oldPassword || !newPassword) {
      return json({ error: '请输入原密码和新密码' }, 400);
    }

    if (newPassword.length < 6) {
      return json({ error: '新密码长度至少 6 个字符' }, 400);
    }

    await initDatabase(env.DB);

    const user = await env.DB.prepare('SELECT id, password_hash FROM users WHERE id = ?')
      .bind(userId)
      .first() as any;

    if (!user) {
      return json({ error: '用户不存在' }, 404);
    }

    const passwordValid = await verifyPassword(oldPassword, user.password_hash);
    if (!passwordValid) {
      return json({ error: '原密码错误' }, 401);
    }

    const newHash = await hashPassword(newPassword);
    await env.DB.prepare('UPDATE users SET password_hash = ? WHERE id = ?')
      .bind(newHash, userId)
      .run();

    await env.DB.prepare(`
      UPDATE refresh_tokens
      SET revoked_at = COALESCE(revoked_at, datetime('now'))
      WHERE user_id = ?
    `)
      .bind(userId)
      .run();

    return json({ success: true, message: '密码修改成功' });
  } catch (e) {
    console.error('ChangePassword error:', e);
    return json({ error: '修改密码失败' }, 500);
  }
}

async function handleAiProxy(request: Request, env: Env): Promise<Response> {
  try {
    const body = await request.json() as any;

    // 从请求中获取用户的 AI 配置（不存储，只转发）
    const { apiKey, baseUrl, model, topicTitle, mustHave, commonMistakes, userAnswer, language } = body;

    if (!apiKey || !baseUrl || !model) {
      return json({ error: 'Missing required fields: apiKey, baseUrl, model' }, 400);
    }

    // 构建系统提示词
    const systemPrompt = `你是一个技术面试评估专家。请评估用户对知识点的回答。

评估维度：
1. 核心概念完整性 (40%)：是否覆盖标准要点
2. 表达准确性 (25%)：是否有明显错误或混淆
3. 面试表达质量 (20%)：是否像面试回答，结构是否清晰
4. 扩展深度 (15%)：是否能结合场景、优缺点、实践经验

标准要点：${(mustHave || []).join('、')}
常见错误：${(commonMistakes || []).join('、')}

请用${language || '中文'}回答，并以如下 JSON 格式输出：
{
  "score": 86,
  "level": "skilled",
  "summary": "整体理解正确，但可以补充...",
  "missedPoints": ["遗漏要点1"],
  "wrongPoints": ["错误点1"],
  "improvedAnswer": "面试时可以这样回答：...",
  "nextAction": "进入下一知识点"
}

score 范围 0-100，level 为 skilled(>=85)/familiar(>=60)/unfamiliar(<60)。`;

    // 转发请求到用户配置的 AI 服务
    const targetUrl = `${baseUrl.replace(/\/+$/, '')}/chat/completions`;
    const aiResponse = await fetch(targetUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: `知识点：${topicTitle}\n\n我的回答：\n${userAnswer}` },
        ],
        temperature: 0.3,
        max_tokens: 2000,
      }),
    });

    if (!aiResponse.ok) {
      const errorText = await aiResponse.text();
      console.error('AI upstream error:', aiResponse.status);
      return json({
        error: 'AI 服务请求失败',
      }, aiResponse.status);
    }

    const aiResult = await aiResponse.json() as any;
    const content = aiResult.choices?.[0]?.message?.content || '';

    // 尝试从回复中提取 JSON
    const jsonMatch = content.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      try {
        return json(JSON.parse(jsonMatch[0]));
      } catch (_) {
        // JSON 解析失败，返回原始内容
      }
    }

    return json({
      score: 0,
      level: 'unfamiliar',
      summary: content,
      missedPoints: [],
      wrongPoints: [],
      improvedAnswer: '',
      nextAction: '重试',
    });
  } catch (e) {
    console.error('AI proxy error:', e);
    return json({ error: 'AI 代理请求失败' }, 500);
  }
}

// 初始化同步表
async function initSyncTables(db: D1Database): Promise<void> {
  await db.exec(`
    CREATE TABLE IF NOT EXISTS user_progress (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      topic_id TEXT NOT NULL,
      status TEXT DEFAULT 'unfamiliar',
      score INTEGER DEFAULT 0,
      review_count INTEGER DEFAULT 0,
      next_review_at TEXT,
      updated_at TEXT DEFAULT (datetime('now')),
      UNIQUE(user_id, topic_id)
    );
    CREATE INDEX IF NOT EXISTS idx_user_progress_user ON user_progress(user_id);
    CREATE INDEX IF NOT EXISTS idx_user_progress_topic ON user_progress(user_id, topic_id);

    CREATE TABLE IF NOT EXISTS user_settings (
      user_id TEXT PRIMARY KEY,
      current_domain TEXT DEFAULT 'java',
      recommend_strategy TEXT DEFAULT 'weighted',
      language TEXT DEFAULT 'zh',
      theme_mode TEXT DEFAULT 'system',
      updated_at TEXT DEFAULT (datetime('now'))
    );
  `);
}

// 上传学习进度
async function handleSyncProgress(request: Request, env: Env): Promise<Response> {
  try {
    const userId = await getUserIdFromRequest(request, env);
    if (!userId) {
      return json({ error: '未登录或 token 已过期' }, 401);
    }

    const body = await request.json() as any;
    const { progressMap, settings } = body;

    await initSyncTables(env.DB);

    // 同步学习进度
    if (progressMap && typeof progressMap === 'object') {
      for (const [topicId, progress] of Object.entries(progressMap)) {
        const p = progress as any;
        await env.DB.prepare(`
          INSERT INTO user_progress (user_id, topic_id, status, score, review_count, next_review_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
          ON CONFLICT(user_id, topic_id) DO UPDATE SET
            status = CASE
              WHEN excluded.score > user_progress.score THEN excluded.status
              ELSE user_progress.status
            END,
            score = MAX(excluded.score, user_progress.score),
            review_count = excluded.review_count,
            next_review_at = COALESCE(excluded.next_review_at, user_progress.next_review_at),
            updated_at = datetime('now')
        `)
          .bind(userId, topicId, p.status || 'unfamiliar', p.score || 0, p.reviewCount || 0, p.nextReviewAt || null)
          .run();
      }
    }

    // 同步用户设置
    if (settings && typeof settings === 'object') {
      await env.DB.prepare(`
        INSERT INTO user_settings (user_id, current_domain, recommend_strategy, language, theme_mode, updated_at)
        VALUES (?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(user_id) DO UPDATE SET
          current_domain = excluded.current_domain,
          recommend_strategy = excluded.recommend_strategy,
          language = excluded.language,
          theme_mode = excluded.theme_mode,
          updated_at = datetime('now')
      `)
        .bind(userId, settings.currentDomain || 'java', settings.recommendStrategy || 'weighted', settings.language || 'zh', settings.themeMode || 'system')
        .run();
    }

    return json({ success: true, syncedAt: new Date().toISOString() });
  } catch (e) {
    console.error('SyncProgress error:', e);
    return json({ error: '同步失败' }, 500);
  }
}

// 获取云端学习进度
async function handleGetProgress(request: Request, env: Env): Promise<Response> {
  try {
    const userId = await getUserIdFromRequest(request, env);
    if (!userId) {
      return json({ error: '未登录或 token 已过期' }, 401);
    }

    await initSyncTables(env.DB);

    // 获取学习进度
    const progressRows = await env.DB.prepare(
      'SELECT topic_id, status, score, review_count, next_review_at, updated_at FROM user_progress WHERE user_id = ?'
    )
      .bind(userId)
      .all();

    const progressMap: Record<string, any> = {};
    for (const row of progressRows.results) {
      const r = row as any;
      progressMap[r.topic_id] = {
        status: r.status,
        score: r.score,
        reviewCount: r.review_count,
        nextReviewAt: r.next_review_at,
        updatedAt: r.updated_at,
      };
    }

    // 获取用户设置
    const settings = await env.DB.prepare(
      'SELECT current_domain, recommend_strategy, language, theme_mode FROM user_settings WHERE user_id = ?'
    )
      .bind(userId)
      .first() as any;

    return json({
      success: true,
      progressMap,
      settings: settings ? {
        currentDomain: settings.current_domain,
        recommendStrategy: settings.recommend_strategy,
        language: settings.language,
        themeMode: settings.theme_mode,
      } : null,
    });
  } catch (e) {
    console.error('GetProgress error:', e);
    return json({ error: '获取进度失败' }, 500);
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'access-control-allow-origin': '*',
    },
  });
}

interface Env {
  CONTENT_MANIFEST_URL: string;
  TEST_CONTENT_BASE_URL: string;
  PROD_CONTENT_BASE_URL: string;
  DB: D1Database;
  JWT_SECRET: string;
}

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

    // 获取用户信息（需要认证）
    if (url.pathname === '/auth/me' && request.method === 'GET') {
      return handleGetMe(request, env);
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
    return json({ error: 'Upstream fetch failed', detail: String(e) }, 502);
  }
}

// 简单的密码哈希（生产环境应使用 bcrypt）
async function hashPassword(password: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

// 生成简单的 JWT token
async function generateToken(userId: string, secret: string): Promise<string> {
  const header = { alg: 'HS256', typ: 'JWT' };
  const payload = {
    userId,
    exp: Math.floor(Date.now() / 1000) + 7 * 24 * 60 * 60, // 7 天过期
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

    // 检查用户名是否已存在
    const existing = await env.DB.prepare('SELECT id FROM users WHERE username = ?')
      .bind(username)
      .first();

    if (existing) {
      return json({ error: '用户名已存在' }, 409);
    }

    // 创建用户
    const userId = crypto.randomUUID();
    const passwordHash = await hashPassword(password);
    const finalNickname = nickname || username;

    await env.DB.prepare(
      'INSERT INTO users (id, username, password_hash, nickname) VALUES (?, ?, ?, ?)'
    )
      .bind(userId, username, passwordHash, finalNickname)
      .run();

    // 生成 token
    const token = await generateToken(userId, env.JWT_SECRET);

    return json({
      success: true,
      user: { id: userId, username, nickname: finalNickname },
      token,
    });
  } catch (e) {
    return json({ error: '注册失败', detail: String(e) }, 500);
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

    // 查找用户
    const user = await env.DB.prepare(
      'SELECT id, username, password_hash, nickname FROM users WHERE username = ?'
    )
      .bind(username)
      .first() as any;

    if (!user) {
      return json({ error: '用户名或密码错误' }, 401);
    }

    // 验证密码
    const passwordHash = await hashPassword(password);
    if (passwordHash !== user.password_hash) {
      return json({ error: '用户名或密码错误' }, 401);
    }

    // 更新最后登录时间
    await env.DB.prepare('UPDATE users SET last_login_at = datetime(\'now\') WHERE id = ?')
      .bind(user.id)
      .run();

    // 生成 token
    const token = await generateToken(user.id, env.JWT_SECRET);

    return json({
      success: true,
      user: { id: user.id, username: user.username, nickname: user.nickname },
      token,
    });
  } catch (e) {
    return json({ error: '登录失败', detail: String(e) }, 500);
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
    return json({ error: '获取用户信息失败', detail: String(e) }, 500);
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
      return json({
        error: 'AI service error',
        status: aiResponse.status,
        detail: errorText,
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
    return json({ error: 'AI proxy error', detail: String(e) }, 500);
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
    return json({ error: '同步失败', detail: String(e) }, 500);
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
    return json({ error: '获取进度失败', detail: String(e) }, 500);
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

import type { Env } from "./env";
import { initDatabase } from "./db";
import { json } from "./http";
import {
  getJwtSecret,
  hashPassword,
  hashRefreshToken,
  issueAuthTokens,
  parseStoredDateMs,
  verifyPassword,
  verifyToken,
} from "./crypto";

// 从请求中获取用户 ID
export async function getUserIdFromRequest(
  request: Request,
  env: Env,
): Promise<string | null> {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return null;

  const token = authHeader.slice(7);
  const payload = await verifyToken(token, getJwtSecret(env));
  return payload?.userId || null;
}

export async function getActiveUserFromRequest(
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

// 用户注册
export async function handleRegister(request: Request, env: Env): Promise<Response> {
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

    // 客户端应发送 PBKDF2 派生的 base64 哈希（44 字符）。校验形状可挡住
    // 绕过客户端直连、提交弱口令明文的请求。
    if (!isClientPasswordHash(password_hash)) {
      return json({ error: "密码哈希格式无效" }, 400);
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

    try {
      await env.DB.prepare(
        "INSERT INTO users (id, username, password_hash, nickname, role) VALUES (?, ?, ?, ?, 'user')",
      )
        .bind(userId, normalizedUsername, passwordHash, finalNickname)
        .run();
    } catch (insertErr) {
      // UNIQUE 约束冲突：两个请求几乎同时注册同一用户名，统一返回 409
      const msg =
        insertErr instanceof Error ? insertErr.message : String(insertErr);
      if (msg.toLowerCase().includes("unique")) {
        return json({ error: "用户名已存在" }, 409);
      }
      throw insertErr;
    }

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
    // 不向客户端透传内部错误细节（如配置缺失），仅记录到日志。
    return json({ error: "注册失败，请稍后重试" }, 500);
  }
}

// 客户端密码哈希应为 PBKDF2-SHA256(32B) 的 base64，长度 40-64 且仅 base64 字符。
export function isClientPasswordHash(value: unknown): boolean {
  return (
    typeof value === "string" &&
    value.length >= 40 &&
    value.length <= 64 &&
    /^[A-Za-z0-9+/]+={0,2}$/.test(value)
  );
}

// 用户登录
export async function handleLogin(request: Request, env: Env): Promise<Response> {
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
    // 不向客户端透传内部错误细节，仅记录到日志。
    return json({ error: "登录失败，请稍后重试" }, 500);
  }
}

// 刷新登录态，成功后轮换 refresh token
export async function handleRefreshToken(
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
      const revokedMs = parseStoredDateMs(tokenRow.revoked_at);
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
        parseStoredDateMs(successor.expires_at) <= Date.now()
      ) {
        return json({ error: "登录已过期，请重新登录" }, 401);
      }
      // 从后继 token 正常旋转
      tokenRow.id = successor.id;
      tokenRow.user_id = successor.user_id;
      tokenRow.revoked_at = null;
    }

    if (parseStoredDateMs(tokenRow.expires_at) <= Date.now()) {
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
      const nowIso = new Date().toISOString();
      await env.DB.prepare(
        `
        UPDATE refresh_tokens
        SET revoked_at = COALESCE(revoked_at, ?), last_used_at = ?
        WHERE id = ?
      `,
      )
        .bind(nowIso, nowIso, tokenRow.id)
        .run();
      return json({ error: "账号已被禁用，请联系管理员" }, 403);
    }

    const { token, refreshToken: nextRefreshToken, refreshTokenId } = await issueAuthTokens(
      env.DB,
      user.id,
      getJwtSecret(env),
    );

    // 吊销当前 token，并记录宽限期链接
    const nowIso = new Date().toISOString();
    await env.DB.prepare(
      `
      UPDATE refresh_tokens
      SET revoked_at = ?, last_used_at = ?, rotated_to = ?
      WHERE id = ?
    `,
    )
      .bind(nowIso, nowIso, refreshTokenId, tokenRow.id)
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
export async function handleLogout(request: Request, env: Env): Promise<Response> {
  try {
    const body = (await request.json().catch(() => ({}))) as any;
    const { refreshToken } = body;

    if (refreshToken && typeof refreshToken === "string") {
      await initDatabase(env.DB);
      const tokenHash = await hashRefreshToken(refreshToken);
      const nowIso = new Date().toISOString();
      await env.DB.prepare(
        `
        UPDATE refresh_tokens
        SET revoked_at = COALESCE(revoked_at, ?)
        WHERE token_hash = ?
      `,
      )
        .bind(nowIso, tokenHash)
        .run();
    }

    return json({ success: true });
  } catch (e) {
    console.error("Logout error:", e);
    return json({ error: "退出登录失败" }, 500);
  }
}

// 获取当前用户信息
export async function handleGetMe(request: Request, env: Env): Promise<Response> {
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
export async function handleChangePassword(
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

    if (
      !isClientPasswordHash(old_password_hash) ||
      !isClientPasswordHash(new_password_hash)
    ) {
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

    const nowIso = new Date().toISOString();
    await env.DB.prepare(
      `
      UPDATE refresh_tokens
      SET revoked_at = COALESCE(revoked_at, ?)
      WHERE user_id = ?
    `,
    )
      .bind(nowIso, userId)
      .run();

    return json({ success: true, message: "密码修改成功" });
  } catch (e) {
    console.error("ChangePassword error:", e);
    return json({ error: "修改密码失败" }, 500);
  }
}

export async function requireAdmin(
  request: Request,
  env: Env,
): Promise<{ id: string; role: string } | Response> {
  const user = await getActiveUserFromRequest(request, env);
  if (!user) return json({ error: "未登录或 token 已过期" }, 401);
  if (user.role !== "admin") return json({ error: "需要管理员权限" }, 403);
  return user;
}

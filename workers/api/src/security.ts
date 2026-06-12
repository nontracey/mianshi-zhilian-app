import type { Env } from "./env";
import { initDatabase } from "./db";
import { json } from "./http";

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

export async function checkSecurityBlock(
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

/**
 * KV 滑动窗口限流：以 IP + 端点 + 时间桶为 key，计数并对比上限。
 * KV 故障时放行（fail open），不阻塞正常请求。
 * @param windowSeconds 时间窗口长度（秒）
 * @param limit         窗口内最多允许的请求次数
 */
export async function checkRateLimit(
  request: Request,
  env: Env,
  endpoint: string,
  limit: number,
  windowSeconds: number,
): Promise<Response | null> {
  const ip = getClientIp(request);
  if (!ip) return null;
  const bucket = Math.floor(Date.now() / 1000 / windowSeconds);
  const key = `rl:${endpoint}:${ip}:${bucket}`;
  try {
    const raw = await env.KV.get(key);
    const count = raw ? parseInt(raw, 10) + 1 : 1;
    await env.KV.put(key, count.toString(), {
      expirationTtl: windowSeconds * 2,
    });
    if (count > limit) {
      return json({ error: "请求过于频繁，请稍后再试" }, 429);
    }
  } catch {
    // KV 不可用时放行
  }
  return null;
}

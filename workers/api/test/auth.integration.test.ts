import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import { Miniflare } from "miniflare";
import worker from "../src/index";

const CLIENT_HASH = "A".repeat(43) + "=";
const JWT_SECRET = "test-jwt-secret-for-auth-integration";
const SECURITY_RULES_KV_KEY = "security_block_rules:v1";

type TestEnv = {
  DB: D1Database;
  KV: KVNamespace;
  JWT_SECRET: string;
};

let mf: Miniflare;
let env: TestEnv;

async function api(
  path: string,
  options: {
    method?: string;
    body?: unknown;
    ip?: string;
    headers?: Record<string, string>;
  } = {},
): Promise<{ response: Response; data: any }> {
  const headers = new Headers(options.headers);
  if (options.ip) headers.set("CF-Connecting-IP", options.ip);
  let body: BodyInit | undefined;
  if (options.body !== undefined) {
    headers.set("Content-Type", "application/json");
    body = JSON.stringify(options.body);
  }

  const response = await worker.fetch(
    new Request(`https://api.test${path}`, {
      method: options.method ?? (body ? "POST" : "GET"),
      headers,
      body,
    }),
    env,
  );
  const text = await response.text();
  return { response, data: text ? JSON.parse(text) : null };
}

async function legacyHash(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function clearKvPrefix(prefix: string): Promise<void> {
  let cursor: string | undefined;
  do {
    const list = await env.KV.list({ prefix, cursor });
    await Promise.all(list.keys.map((key) => env.KV.delete(key.name)));
    cursor = list.list_complete ? undefined : list.cursor;
  } while (cursor);
}

async function resetState(): Promise<void> {
  await env.DB.prepare("DELETE FROM refresh_tokens").run();
  await env.DB.prepare("DELETE FROM security_block_rules").run();
  await env.DB.prepare("DELETE FROM users").run();
  await env.KV.delete(SECURITY_RULES_KV_KEY);
  await clearKvPrefix("rl:");
}

beforeAll(async () => {
  mf = new Miniflare({
    modules: true,
    script: "export default { fetch() { return new Response('ok') } }",
    d1Databases: ["DB"],
    kvNamespaces: ["KV"],
  });
  await mf.ready;
  const bindings = await mf.getBindings();
  env = {
    DB: bindings.DB as D1Database,
    KV: bindings.KV as KVNamespace,
    JWT_SECRET,
  };

  await api("/auth/login", {
    body: { username: "__init__", password_hash: CLIENT_HASH },
  });
  await resetState();
});

afterEach(async () => {
  await resetState();
});

afterAll(async () => {
  await mf.dispose();
});

describe("Worker auth integration", () => {
  it("轮换 refresh token，并在 logout 后撤销最新 refresh token", async () => {
    const registered = await api("/auth/register", {
      ip: "198.51.100.10",
      body: {
        username: "rotate_user",
        password_hash: CLIENT_HASH,
        nickname: "Rotate User",
      },
    });
    expect(registered.response.status).toBe(200);
    expect(registered.data.refreshToken).toBeTypeOf("string");

    const firstRefreshToken = registered.data.refreshToken as string;
    const rotatedOnce = await api("/auth/refresh", {
      ip: "198.51.100.10",
      body: { refreshToken: firstRefreshToken },
    });
    expect(rotatedOnce.response.status).toBe(200);
    expect(rotatedOnce.data.refreshToken).not.toBe(firstRefreshToken);

    const graceRetry = await api("/auth/refresh", {
      ip: "198.51.100.10",
      body: { refreshToken: firstRefreshToken },
    });
    expect(graceRetry.response.status).toBe(200);
    expect(graceRetry.data.refreshToken).not.toBe(firstRefreshToken);
    expect(graceRetry.data.refreshToken).not.toBe(rotatedOnce.data.refreshToken);

    const loggedOut = await api("/auth/logout", {
      body: { refreshToken: graceRetry.data.refreshToken },
    });
    expect(loggedOut.response.status).toBe(200);
    expect(loggedOut.data).toMatchObject({ success: true });

    const afterLogout = await api("/auth/refresh", {
      ip: "198.51.100.10",
      body: { refreshToken: graceRetry.data.refreshToken },
    });
    expect(afterLogout.response.status).toBe(401);
  });

  it("登录旧 SHA-256 密码哈希后升级为 PBKDF2 salt:hash 格式", async () => {
    const userId = crypto.randomUUID();
    await env.DB.prepare(
      "INSERT INTO users (id, username, password_hash, nickname, role) VALUES (?, ?, ?, ?, 'user')",
    )
      .bind(userId, "legacy_user", await legacyHash(CLIENT_HASH), "Legacy User")
      .run();

    const loggedIn = await api("/auth/login", {
      ip: "198.51.100.20",
      body: { username: "legacy_user", password_hash: CLIENT_HASH },
    });
    expect(loggedIn.response.status).toBe(200);
    expect(loggedIn.data.token).toBeTypeOf("string");

    const row = await env.DB.prepare(
      "SELECT password_hash FROM users WHERE id = ?",
    )
      .bind(userId)
      .first<{ password_hash: string }>();
    expect(row?.password_hash).toContain(":");
    expect(row?.password_hash).not.toBe(await legacyHash(CLIENT_HASH));
  });

  it("登录接口按 IP 命中 KV 限流", async () => {
    const statuses: number[] = [];
    for (let i = 0; i < 11; i += 1) {
      const result = await api("/auth/login", {
        ip: "198.51.100.30",
        body: { username: "missing_user", password_hash: CLIENT_HASH },
      });
      statuses.push(result.response.status);
    }

    expect(statuses.slice(0, 10)).toEqual(Array(10).fill(401));
    expect(statuses[10]).toBe(429);
  });

  it("命中安全封禁规则时在认证处理前返回 403", async () => {
    await env.DB.prepare(
      "INSERT INTO security_block_rules (id, type, value, reason, is_active) VALUES (?, ?, ?, ?, 1)",
    )
      .bind("rule-device-1", "device_id", "blocked-device", "test rule")
      .run();
    await env.KV.delete(SECURITY_RULES_KV_KEY);

    const blocked = await api("/auth/login", {
      ip: "198.51.100.40",
      headers: { "X-Device-Id": "blocked-device" },
      body: { username: "any_user", password_hash: CLIENT_HASH },
    });

    expect(blocked.response.status).toBe(403);
    expect(blocked.data).toMatchObject({
      blocked: true,
      type: "device_id",
      reason: "test rule",
    });
  });
});

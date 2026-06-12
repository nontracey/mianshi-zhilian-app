import type { Env } from "./env";

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

export async function hashPassword(
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
export async function verifyPassword(
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

export function getJwtSecret(env: Env): string {
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
export async function generateToken(userId: string, secret: string): Promise<string> {
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

export async function hashRefreshToken(token: string): Promise<string> {
  const encoder = new TextEncoder();
  const hash = await crypto.subtle.digest("SHA-256", encoder.encode(token));
  return toHex(hash);
}

function refreshTokenExpiresAt(): string {
  return new Date(Date.now() + REFRESH_TOKEN_TTL_SECONDS * 1000).toISOString();
}

export function parseStoredDateMs(value: string): number {
  if (/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(value)) {
    return Date.parse(`${value.replace(" ", "T")}Z`);
  }
  return Date.parse(value);
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

export async function issueAuthTokens(
  db: D1Database,
  userId: string,
  secret: string,
): Promise<{ token: string; refreshToken: string; refreshTokenId: string }> {
  const token = await generateToken(userId, secret);
  const { token: refreshToken, id: refreshTokenId } = await issueRefreshToken(db, userId);
  return { token, refreshToken, refreshTokenId };
}

// 验证 JWT token
export async function verifyToken(token: string, secret: string): Promise<any> {
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

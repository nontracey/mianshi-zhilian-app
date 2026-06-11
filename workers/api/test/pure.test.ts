import { describe, it, expect } from "vitest";
import {
  hashPassword,
  verifyPassword,
  generateToken,
  verifyToken,
  isClientPasswordHash,
  isUuidLike,
  asString,
  parseImageUrls,
  normalizeUpdateManifest,
} from "../src/index";

// 客户端预哈希形如 PBKDF2-SHA256(32B) 的 base64（44 字符）。
const CLIENT_HASH = "A".repeat(43) + "=";

describe("isClientPasswordHash", () => {
  it("接受合法的 base64 哈希", () => {
    expect(isClientPasswordHash(CLIENT_HASH)).toBe(true);
  });
  it("拒绝过短串（绕过客户端的弱口令明文）", () => {
    expect(isClientPasswordHash("123456")).toBe(false);
  });
  it("拒绝含非 base64 字符", () => {
    expect(isClientPasswordHash("has space " + "A".repeat(40))).toBe(false);
  });
  it("拒绝非字符串", () => {
    expect(isClientPasswordHash(null)).toBe(false);
    expect(isClientPasswordHash(123)).toBe(false);
  });
});

describe("isUuidLike", () => {
  it("接受 UUID / 设备 ID 形态", () => {
    expect(isUuidLike("550e8400-e29b-41d4-a716-446655440000")).toBe(true);
    expect(isUuidLike("abcdEF_12-34")).toBe(true);
  });
  it("拒绝过短或含非法字符", () => {
    expect(isUuidLike("short")).toBe(false);
    expect(isUuidLike("has space here")).toBe(false);
  });
});

describe("asString", () => {
  it("trim 并按上限截断", () => {
    expect(asString("  hi  ")).toBe("hi");
    expect(asString("abcdef", 3)).toBe("abc");
  });
  it("非字符串返回空串", () => {
    expect(asString(123)).toBe("");
    expect(asString(null)).toBe("");
  });
});

describe("password hashing (PBKDF2)", () => {
  it("hash 后 verify 通过，错误密码失败", async () => {
    const stored = await hashPassword(CLIENT_HASH);
    expect(stored).toContain(":"); // salt:hash 新格式
    expect(await verifyPassword(CLIENT_HASH, stored)).toBe(true);
    expect(await verifyPassword("B".repeat(43) + "=", stored)).toBe(false);
  });

  it("同一密码两次 hash 因随机盐而不同", async () => {
    const a = await hashPassword(CLIENT_HASH);
    const b = await hashPassword(CLIENT_HASH);
    expect(a).not.toBe(b);
    expect(await verifyPassword(CLIENT_HASH, a)).toBe(true);
    expect(await verifyPassword(CLIENT_HASH, b)).toBe(true);
  });

  it("兼容旧格式（无盐纯 SHA-256）", async () => {
    const enc = new TextEncoder();
    const digest = await crypto.subtle.digest("SHA-256", enc.encode(CLIENT_HASH));
    const legacy = Array.from(new Uint8Array(digest))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    expect(await verifyPassword(CLIENT_HASH, legacy)).toBe(true);
    expect(await verifyPassword("wrong", legacy)).toBe(false);
  });
});

describe("JWT (HS256)", () => {
  const secret = "test-secret";

  it("sign 后 verify 取回 payload", async () => {
    const token = await generateToken("user-1", secret);
    const payload = await verifyToken(token, secret);
    expect(payload?.userId).toBe("user-1");
    expect(typeof payload?.exp).toBe("number");
  });

  it("错误 secret 验签失败", async () => {
    const token = await generateToken("user-1", secret);
    expect(await verifyToken(token, "wrong-secret")).toBeNull();
  });

  it("篡改 payload 验签失败", async () => {
    const token = await generateToken("user-1", secret);
    const [h, , s] = token.split(".");
    const forged = `${h}.${btoa(JSON.stringify({ userId: "admin", exp: 9999999999 }))
      .replace(/=/g, "")}.${s}`;
    expect(await verifyToken(forged, secret)).toBeNull();
  });

  it("过期 token 返回 null", async () => {
    // 手工构造一个已过期 token（exp 在过去），用相同签名流程。
    const header = btoa(JSON.stringify({ alg: "HS256", typ: "JWT" })).replace(/=/g, "");
    const payload = btoa(JSON.stringify({ userId: "u", exp: 1 })).replace(/=/g, "");
    const message = `${header}.${payload}`;
    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
    const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig)))
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=/g, "");
    expect(await verifyToken(`${message}.${sigB64}`, secret)).toBeNull();
  });
});

describe("parseImageUrls", () => {
  it("保留 http(s) URL，最多 3 张", () => {
    const urls = parseImageUrls([
      "https://a.com/1.png",
      "http://b.com/2.png",
      "https://c.com/3.png",
      "https://d.com/4.png",
    ]);
    expect(urls).toHaveLength(3);
  });
  it("丢弃非法协议", () => {
    expect(parseImageUrls(["javascript:alert(1)", "ftp://x"])).toEqual([]);
  });
});

describe("normalizeUpdateManifest", () => {
  it("从 latest 下载链接推导 assetPath", () => {
    const data = {
      platforms: {
        android: {
          url: "https://github.com/o/r/releases/latest/download/app.apk",
        },
      },
    };
    normalizeUpdateManifest(data);
    expect(data.platforms.android).toMatchObject({
      assetPath: "/releases/latest/download/app.apk",
    });
  });
});

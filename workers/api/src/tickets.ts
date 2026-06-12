import type { Env } from "./env";
import { initDatabase } from "./db";
import { json } from "./http";
import {
  getActiveUserFromRequest,
  isClientPasswordHash,
  requireAdmin,
} from "./auth";
import { hashPassword } from "./crypto";
import { asString } from "./validators";

const TICKET_TYPES = new Set(["password_reset", "feedback", "question"]);
const TICKET_STATUSES = new Set([
  "pending",
  "processing",
  "needs_info",
  "rejected",
  "resolved",
  "closed",
]);

const TICKET_IMAGE_MAX = 3; // 最多 3 张
const TICKET_IMAGE_MAX_BYTES = 150 * 1024; // 单图 ≤ 150KB（解 base64 后）
const TICKET_IMAGE_B64_HEAD = /^data:image\/(jpeg|png|webp|gif);base64,/i;

/**
 * 工单图片 URL 解析：限 3 张、限 150KB，仅接受 http(s):// 或 data:image/{jpeg,png,webp,gif};base64,
 * 直接存 D1（不依赖 R2 之类的对象存储）。
 */
export function parseImageUrls(value: unknown): string[] {
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

export function normalizePasswordResetTicketReceipt(row: any): any {
  const ticket = normalizeTicket(row);
  return {
    id: ticket.id,
    type: ticket.type,
    status: ticket.status,
    created_at: ticket.created_at,
  };
}

/**
 * Admin 重置用户密码（无原密码，仅管理员可调）。
 * POST /admin/users/:id/reset-password  body: { password_hash }
 * 哈希到新格式并撤销该用户所有 refresh token。
 */
export async function handleAdminResetPassword(
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
    if (!isClientPasswordHash(clientKey))
      return json({ error: "password_hash 格式无效" }, 400);
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
    const nowIso = new Date().toISOString();
    await env.DB.prepare(
      "UPDATE refresh_tokens SET revoked_at = COALESCE(revoked_at, ?) WHERE user_id = ?",
    )
      .bind(nowIso, userId)
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
export async function handleAdminDeleteTicket(
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

export async function handleCreateTicket(
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

export async function handleCreatePasswordResetTicket(
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
      ticket: normalizePasswordResetTicketReceipt(
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

export async function handleGetMyTickets(
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

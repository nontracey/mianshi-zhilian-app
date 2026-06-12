import type { Env } from "./env";
import { initDatabase } from "./db";
import { json } from "./http";
import { getActiveUserFromRequest } from "./auth";
import { asString, isUuidLike } from "./validators";

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
  "ai_eval_success",
  "ai_eval_failed",
  "content_load_failed",
  "manual_sync",
  "sync_success",
  "sync_failed",
  "ticket_submit",
  "login",
  "update_check",
]);

export async function handleBindDevice(request: Request, env: Env): Promise<Response> {
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

export async function handleAnalyticsBatch(
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

    const analyticsUserId: string | null = null;
    const platform = asString(body.platform, 40) || "unknown";
    const appVersion = asString(body.app_version, 40) || "unknown";
    const osVersion = asString(body.os_version, 80) || "unknown";
    const deviceModel = asString(body.device_model, 80) || "unknown";
    const days = Array.isArray(body.days) ? body.days.slice(0, 7) : [];
    let totalOpen = 0;
    let totalDuration = 0;

    // 收集所有写入，最后用 db.batch() 原子执行：要么全成功、batch_id 落库（重试
    // 被 dedup 拒绝）；要么整体回滚、batch_id 未落库（客户端重试不会重复累加统计）。
    const statements: D1PreparedStatement[] = [
      env.DB.prepare(
        `INSERT INTO analytics_batches (batch_id, device_id, user_id) VALUES (?, ?, ?)`,
      ).bind(batchId, deviceId, analyticsUserId),
    ];

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
      statements.push(
        env.DB.prepare(
          `
        INSERT INTO daily_visit_stats (date, device_id, user_id, platform, app_version, open_count, duration_seconds, last_seen_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(date, device_id) DO UPDATE SET
          user_id = excluded.user_id,
          platform = excluded.platform,
          app_version = excluded.app_version,
          open_count = daily_visit_stats.open_count + excluded.open_count,
          duration_seconds = MIN(86400, daily_visit_stats.duration_seconds + excluded.duration_seconds),
          last_seen_at = datetime('now')
      `,
        ).bind(
          date,
          deviceId,
          analyticsUserId,
          platform,
          appVersion,
          openCount,
          durationSeconds,
        ),
      );

      statements.push(
        ...countMapStatements(
          env.DB,
          "daily_section_stats",
          "section",
          date,
          deviceId,
          analyticsUserId,
          day.section_counts,
          ANALYTICS_SECTIONS,
        ),
        ...countMapStatements(
          env.DB,
          "daily_feature_stats",
          "feature",
          date,
          deviceId,
          analyticsUserId,
          day.feature_counts,
          ANALYTICS_FEATURES,
        ),
      );
    }

    statements.push(
      env.DB.prepare(
        `
      INSERT INTO user_devices (device_id, user_id, platform, app_version, os_version, device_model, first_seen_at, last_seen_at, visit_count, total_duration_seconds)
      VALUES (?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'), ?, ?)
      ON CONFLICT(device_id) DO UPDATE SET
        user_id = COALESCE(user_devices.user_id, excluded.user_id),
        platform = excluded.platform,
        app_version = excluded.app_version,
        os_version = excluded.os_version,
        device_model = excluded.device_model,
        last_seen_at = datetime('now'),
        visit_count = user_devices.visit_count + excluded.visit_count,
        total_duration_seconds = user_devices.total_duration_seconds + excluded.total_duration_seconds
    `,
      ).bind(
        deviceId,
        analyticsUserId,
        platform,
        appVersion,
        osVersion,
        deviceModel,
        totalOpen,
        totalDuration,
      ),
    );

    await env.DB.batch(statements);

    return json({ success: true });
  } catch (e) {
    console.error("AnalyticsBatch error:", e);
    return json({ error: "访问统计上报失败" }, 500);
  }
}

function countMapStatements(
  db: D1Database,
  table: string,
  column: string,
  date: string,
  deviceId: string,
  userId: string | null,
  value: any,
  allowed: Set<string>,
): D1PreparedStatement[] {
  if (!value || typeof value !== "object") return [];
  const statements: D1PreparedStatement[] = [];
  for (const [key, rawCount] of Object.entries(value).slice(0, 20)) {
    if (!allowed.has(key)) continue;
    const count = Math.max(0, Math.min(Number(rawCount) || 0, 1000));
    if (count === 0) continue;
    statements.push(
      db
        .prepare(
          `
      INSERT INTO ${table} (date, device_id, user_id, ${column}, count)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(date, device_id, ${column}) DO UPDATE SET
        user_id = excluded.user_id,
        count = ${table}.count + excluded.count
    `,
        )
        .bind(date, deviceId, userId, key, count),
    );
  }
  return statements;
}

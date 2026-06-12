import pkg from "../package.json";
import { handleAnalyticsBatch, handleBindDevice } from "./analytics";
import {
  handleChangePassword,
  handleGetMe,
  handleLogin,
  handleLogout,
  handleRefreshToken,
  handleRegister,
} from "./auth";
import {
  contentBackupBaseUrl,
  contentPrimaryBaseUrl,
  contentStageSubPath,
  contentTargetUrls,
  normalizeUpdateManifest,
  proxyFetchWithFallback,
  proxyUpdateManifest,
} from "./content_proxy";
import { generateToken, hashPassword, verifyPassword, verifyToken } from "./crypto";
import type { Env } from "./env";
import { json } from "./http";
import { checkRateLimit, checkSecurityBlock } from "./security";
import {
  handleAdminDeleteTicket,
  handleAdminResetPassword,
  handleCreatePasswordResetTicket,
  handleCreateTicket,
  handleGetMyTickets,
  normalizePasswordResetTicketReceipt,
  parseImageUrls,
} from "./tickets";
import { asString, isUuidLike } from "./validators";

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
      });
    }

    if (url.pathname === "/update.json") {
      return proxyUpdateManifest();
    }

    const blocked = await checkSecurityBlock(request, env);
    if (blocked) return blocked;

    // 用户注册（每 IP 每分钟最多 10 次）
    if (url.pathname === "/auth/register" && request.method === "POST") {
      const limited = await checkRateLimit(request, env, "register", 10, 60);
      if (limited) return limited;
      return handleRegister(request, env);
    }

    // 用户登录（每 IP 每分钟最多 10 次）
    if (url.pathname === "/auth/login" && request.method === "POST") {
      const limited = await checkRateLimit(request, env, "login", 10, 60);
      if (limited) return limited;
      return handleLogin(request, env);
    }

    // 刷新登录态（每 IP 每分钟最多 30 次，防刷新接口被滥用）
    if (url.pathname === "/auth/refresh" && request.method === "POST") {
      const limited = await checkRateLimit(request, env, "refresh", 30, 60);
      if (limited) return limited;
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
      // 工单提交：每 IP 每小时最多 10 次
      const limited = await checkRateLimit(request, env, "tickets", 10, 3600);
      if (limited) return limited;
      return handleCreateTicket(request, env);
    }

    if (url.pathname === "/tickets" && request.method === "GET") {
      return handleGetMyTickets(request, env);
    }

    if (
      url.pathname === "/tickets/password-reset" &&
      request.method === "POST"
    ) {
      // 密码重置工单：每 IP 每 10 分钟最多 5 次
      const limited = await checkRateLimit(
        request,
        env,
        "pw-reset",
        5,
        600,
      );
      if (limited) return limited;
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

// 纯函数导出，供单元测试覆盖（auth/validators 等无需 Workers 运行时绑定）。
export {
  asString,
  generateToken,
  hashPassword,
  isUuidLike,
  normalizePasswordResetTicketReceipt,
  normalizeUpdateManifest,
  parseImageUrls,
  verifyPassword,
  verifyToken,
};
export { isClientPasswordHash } from "./auth";

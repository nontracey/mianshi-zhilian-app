import type { Env } from "./env";
import { json } from "./http";

// 主备口径与客户端 RouteResolver 保持一致：de5.net 为主用，pages.dev 为备用。
export function contentPrimaryBaseUrl(env: Env): string {
  return (
    env.CONTENT_PRIMARY_BASE_URL ||
    "https://mianshizhilian-content.nontracey.de5.net"
  );
}

export function contentBackupBaseUrl(env: Env): string {
  return (
    env.CONTENT_BACKUP_BASE_URL ||
    "https://mianshi-zhilian-content.pages.dev"
  );
}

export function contentTargetUrls(env: Env, subPath: string): string[] {
  const path = subPath.replace(/^\/+/, "");
  const urls = [
    `${contentPrimaryBaseUrl(env).replace(/\/+$/, "")}/${path}`,
    `${contentBackupBaseUrl(env).replace(/\/+$/, "")}/${path}`,
  ];
  return Array.from(new Set(urls));
}

export function contentStageSubPath(stage: "test" | "draft", subPath: string): string {
  const normalized = subPath.replace(/^\/+/, "");
  if (normalized === "manifest.json") {
    return stage === "draft" ? "draft-manifest.json" : "staging-manifest.json";
  }
  return normalized;
}

export async function proxyFetchWithFallback(
  targetUrls: string[],
  originalRequest: Request,
): Promise<Response> {
  let lastError: unknown;
  for (let i = 0; i < targetUrls.length; i++) {
    const targetUrl = targetUrls[i];
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 8000);
    try {
      const response = await fetch(targetUrl, {
        method: originalRequest.method,
        headers: {
          Accept: originalRequest.headers.get("Accept") || "application/json",
        },
        redirect: "follow",
        signal: controller.signal,
      });
      clearTimeout(timeoutId);
      if (i < targetUrls.length - 1 && response.status >= 500) {
        lastError = `HTTP ${response.status} from ${targetUrl}`;
        continue;
      }
      const body = await response.text();
      return new Response(body, {
        status: response.status,
        headers: {
          "content-type":
            response.headers.get("content-type") ||
            "application/json; charset=utf-8",
          "access-control-allow-origin": "*",
          "cache-control": "public, max-age=300",
        },
      });
    } catch (e) {
      clearTimeout(timeoutId);
      lastError = e;
      if (i < targetUrls.length - 1) continue;
    }
  }
  console.error("ProxyFetch error:", lastError);
  return json({ error: "上游请求失败" }, 502);
}

export async function proxyUpdateManifest(): Promise<Response> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 8000);
  try {
    const res = await fetch(
      "https://github.com/nontracey/mianshi-zhilian-app/releases/latest/download/update.json",
      { redirect: "follow", signal: controller.signal },
    );
    if (!res.ok) {
      return json({ error: "update manifest not found" }, 404);
    }
    const data = await res.json();
    normalizeUpdateManifest(data);
    return new Response(JSON.stringify(data), {
      headers: {
        "content-type": "application/json; charset=utf-8",
        "access-control-allow-origin": "*",
        "cache-control": "public, max-age=300",
      },
    });
  } catch (e) {
    console.error("proxyUpdateManifest error:", e);
    return json({ error: "上游请求失败" }, 502);
  } finally {
    clearTimeout(timeoutId);
  }
}

export function normalizeUpdateManifest(data: any): void {
  const platforms = data?.platforms;
  if (!platforms || typeof platforms !== "object") return;
  for (const platform of Object.values(platforms) as any[]) {
    if (!platform || typeof platform !== "object" || platform.assetPath)
      continue;
    const rawUrl = typeof platform.url === "string" ? platform.url : "";
    try {
      const url = new URL(rawUrl);
      const latestMarker = "/releases/latest/download/";
      const latestIndex = url.pathname.indexOf(latestMarker);
      if (latestIndex >= 0) {
        platform.assetPath = url.pathname.slice(latestIndex);
        continue;
      }
      const versionedMatch = url.pathname.match(
        /^\/[^/]+\/[^/]+\/releases\/download\/[^/]+\/(.+)$/,
      );
      if (versionedMatch?.[1]) {
        platform.assetPath = `${latestMarker}${versionedMatch[1]}`;
      }
    } catch {
      // Ignore non-URL asset values; clients will keep using url/mirrors.
    }
  }
}

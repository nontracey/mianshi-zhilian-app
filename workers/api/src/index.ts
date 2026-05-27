export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

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
      return json({ error: 'AI proxy is not configured in MVP. Use a local client AI configuration first.' }, 501);
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
}

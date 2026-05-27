export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === '/health') {
      return json({ ok: true, service: 'mianshi-zhilian-api', version: '0.1.0' });
    }

    if (url.pathname === '/config') {
      return json({
        contentManifestUrl: env.CONTENT_MANIFEST_URL,
        updateManifestUrl: 'https://github.com/nontracey/mianshi-zhilian-app/releases/latest',
        aiProxyEnabled: true,
      });
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
}

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
      return handleAiProxy(request, env);
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

async function handleAiProxy(request: Request, env: Env): Promise<Response> {
  try {
    const body = await request.json() as any;

    // 从请求中获取用户的 AI 配置（不存储，只转发）
    const { apiKey, baseUrl, model, topicTitle, mustHave, commonMistakes, userAnswer, language } = body;

    if (!apiKey || !baseUrl || !model) {
      return json({ error: 'Missing required fields: apiKey, baseUrl, model' }, 400);
    }

    // 构建系统提示词
    const systemPrompt = `你是一个技术面试评估专家。请评估用户对知识点的回答。

评估维度：
1. 核心概念完整性 (40%)：是否覆盖标准要点
2. 表达准确性 (25%)：是否有明显错误或混淆
3. 面试表达质量 (20%)：是否像面试回答，结构是否清晰
4. 扩展深度 (15%)：是否能结合场景、优缺点、实践经验

标准要点：${(mustHave || []).join('、')}
常见错误：${(commonMistakes || []).join('、')}

请用${language || '中文'}回答，并以如下 JSON 格式输出：
{
  "score": 86,
  "level": "skilled",
  "summary": "整体理解正确，但可以补充...",
  "missedPoints": ["遗漏要点1"],
  "wrongPoints": ["错误点1"],
  "improvedAnswer": "面试时可以这样回答：...",
  "nextAction": "进入下一知识点"
}

score 范围 0-100，level 为 skilled(>=85)/familiar(>=60)/unfamiliar(<60)。`;

    // 转发请求到用户配置的 AI 服务
    const targetUrl = `${baseUrl.replace(/\/+$/, '')}/chat/completions`;
    const aiResponse = await fetch(targetUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: `知识点：${topicTitle}\n\n我的回答：\n${userAnswer}` },
        ],
        temperature: 0.3,
        max_tokens: 2000,
      }),
    });

    if (!aiResponse.ok) {
      const errorText = await aiResponse.text();
      return json({
        error: 'AI service error',
        status: aiResponse.status,
        detail: errorText,
      }, aiResponse.status);
    }

    const aiResult = await aiResponse.json() as any;
    const content = aiResult.choices?.[0]?.message?.content || '';

    // 尝试从回复中提取 JSON
    const jsonMatch = content.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      try {
        return json(JSON.parse(jsonMatch[0]));
      } catch (_) {
        // JSON 解析失败，返回原始内容
      }
    }

    return json({
      score: 0,
      level: 'unfamiliar',
      summary: content,
      missedPoints: [],
      wrongPoints: [],
      improvedAnswer: '',
      nextAction: '重试',
    });
  } catch (e) {
    return json({ error: 'AI proxy error', detail: String(e) }, 500);
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

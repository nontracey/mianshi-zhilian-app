/// P2 子层单测：模型网关 / 定向 RAG / 岗位导入 / 简历解析（§6.3–6.9、§8.1）。
///
/// 全部纯 Dart、不连网：网络与模型均以注入的假实现替代。使用合成"演示数据"。
library;

import 'dart:convert';

import 'harness.dart';

import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/domain/goal.dart';
import 'package:mianshi_zhilian/coach/model/errors.dart';
import 'package:mianshi_zhilian/coach/model/gateway.dart';
import 'package:mianshi_zhilian/coach/model/http_client.dart';
import 'package:mianshi_zhilian/coach/model/messages.dart';
import 'fakes/mock_gateway.dart';
import 'package:mianshi_zhilian/coach/model/compat_gateway.dart';
import 'package:mianshi_zhilian/coach/knowledge/chunker.dart';
import 'package:mianshi_zhilian/coach/knowledge/importer.dart';
import 'package:mianshi_zhilian/coach/knowledge/index.dart';
import 'package:mianshi_zhilian/coach/knowledge/parser.dart';
import 'package:mianshi_zhilian/coach/knowledge/retriever.dart';
import 'package:mianshi_zhilian/coach/knowledge/source.dart';
import 'package:mianshi_zhilian/coach/jobs/jd_import_service.dart';
import 'package:mianshi_zhilian/coach/jobs/link_parser.dart';
import 'package:mianshi_zhilian/coach/jobs/models.dart';
import 'package:mianshi_zhilian/coach/jobs/search_service.dart';
import 'package:mianshi_zhilian/coach/resume/claim_mapping.dart';
import 'package:mianshi_zhilian/coach/resume/resume_parse.dart';

final DateTime now = DateTime(2026, 9, 11, 10, 0);

Future<void> main() async {
  group('ModelGateway - Mock 网关（离线兜底）', () {
    test('complete 回显并注明演示来源', () async {
      final gw = MockModelGateway();
      final resp = await gw.complete(
        ModelGatewayRequest(messages: [ChatMessage.user('解释 HashMap')]),
      );
      expect(resp.message.role, ChatRole.assistant);
      expect(resp.message.content, contains('演示模型'));
      expect(resp.providerConfigId, 'mock');
    });

    test('stream 逐块输出并以 isDone 结束', () async {
      final gw = MockModelGateway(
        responder: (_) => ModelGatewayResponse(
          message: ChatMessage.assistant(content: '第一句。第二句。'),
        ),
      );
      final events = <ModelStreamEvent>[];
      await for (final e in gw.stream(
        ModelGatewayRequest(messages: [ChatMessage.user('q')]),
      )) {
        events.add(e);
      }
      expect(events.last.isDone, isTrue);
      final text = events
          .where((e) => e.deltaContent != null)
          .map((e) => e.deltaContent)
          .join();
      expect(text, '第一句。第二句。');
    });

    test('probe 返回能力声明', () async {
      final caps = await MockModelGateway().probe();
      expect(caps.supportsStreaming, isTrue);
      expect(caps.supportsTools, isTrue);
      expect(caps.detectedModel, 'mock-coach');
    });

    test('取消后 complete 抛 ModelCanceledException', () async {
      final token = CancelToken()..cancel();
      await expectThrowsAsync(
        () => MockModelGateway().complete(
          ModelGatewayRequest(messages: [ChatMessage.user('q')]),
          cancel: token,
        ),
        isA<ModelCanceledException>(),
      );
    });
  });

  group('ModelGateway - OpenAI 兼容解析（假 HTTP）', () {
    test('complete 解析 choices/usage，tool_calls.arguments 为字符串', () async {
      final http = _FakeHttp(
        postBody: jsonEncode({
          'model': 'demo-model',
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '好的',
                'tool_calls': [
                  {
                    'id': 'call_1',
                    'function': {'name': 'lookup', 'arguments': '{"q":"java"}'},
                  },
                ],
              },
            },
          ],
          'usage': {
            'prompt_tokens': 3,
            'completion_tokens': 5,
            'total_tokens': 8,
          },
        }),
      );
      final gw = _gateway(http);
      final resp = await gw.complete(
        ModelGatewayRequest(messages: [ChatMessage.user('hi')]),
      );
      expect(resp.message.content, '好的');
      expect(resp.usage!.totalTokens, 8);
      expect(resp.message.toolCalls!.single.name, 'lookup');
      expect(resp.message.toolCalls!.single.arguments['q'], 'java');
    });

    test('401 → ModelAuthException，429 → ModelRateLimitException', () async {
      await expectThrowsAsync(
        () => _gateway(
          _FakeHttp(postStatus: 401),
        ).complete(ModelGatewayRequest(messages: [ChatMessage.user('hi')])),
        isA<ModelAuthException>(),
      );
      await expectThrowsAsync(
        () => _gateway(
          _FakeHttp(postStatus: 429),
        ).complete(ModelGatewayRequest(messages: [ChatMessage.user('hi')])),
        isA<ModelRateLimitException>(),
      );
    });

    test('SSE 流式解析增量并按 [DONE] 结束', () async {
      final http = _FakeHttp(
        sseChunks: [
          _sse({
            'choices': [
              {
                'delta': {'content': '你好'},
              },
            ],
          }),
          _sse({
            'choices': [
              {
                'delta': {'content': '世界'},
              },
            ],
          }),
          'data: [DONE]\n\n',
        ],
      );
      final events = <ModelStreamEvent>[];
      await for (final e in _gateway(http).stream(
        ModelGatewayRequest(messages: [ChatMessage.user('hi')], stream: true),
      )) {
        events.add(e);
      }
      final text = events
          .where((e) => e.deltaContent != null && e.deltaContent!.isNotEmpty)
          .map((e) => e.deltaContent)
          .join();
      expect(text, '你好世界');
      expect(events.last.isDone, isTrue);
    });

    test('工具调用分片在 done 事件聚合', () async {
      final http = _FakeHttp(
        sseChunks: [
          _sse({
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_9',
                      'function': {'name': 'search', 'arguments': '{"q":'},
                    },
                  ],
                },
              },
            ],
          }),
          _sse({
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'function': {'arguments': '"java"}'},
                    },
                  ],
                },
              },
            ],
          }),
          'data: [DONE]\n\n',
        ],
      );
      ModelStreamEvent? done;
      await for (final e in _gateway(http).stream(
        ModelGatewayRequest(messages: [ChatMessage.user('hi')], stream: true),
      )) {
        if (e.isDone) done = e;
      }
      expect(done!.toolCalls!.single.name, 'search');
      expect(done.toolCalls!.single.arguments['q'], 'java');
    });
  });

  group('ChatMessage - 线格式', () {
    test('tool_calls.arguments 序列化为字符串', () {
      final msg = ChatMessage.assistant(
        content: '',
        toolCalls: [
          ToolCall(id: 'c1', name: 'search', arguments: {'q': 'java'}),
        ],
      );
      final json = msg.toWireJson();
      expect(json['role'], 'assistant');
      final tc = (json['tool_calls'] as List).first as Map;
      final fn = tc['function'] as Map;
      expect(fn['arguments'], isA<String>());
      expect(fn['arguments'], contains('java'));
    });
  });

  group('定向 RAG - 切块与索引', () {
    test('Chunker 按标题维护标题路径', () {
      final chunker = Chunker(targetChars: 40, overlapChars: 0);
      final chunks = chunker.chunk(
        '# 第一章\n\n段落A内容。\n\n# 第二章\n\n段落B内容。',
        baseTitlePath: '资料',
      );
      expect(chunks.length, 2);
      expect(chunks[0].titlePath, '资料 / 第一章');
      expect(chunks[1].titlePath, '资料 / 第二章');
      expect(chunks[0].content, contains('段落A'));
    });

    test('Chunker 超长切分保留重叠', () {
      final chunker = Chunker(targetChars: 20, overlapChars: 15);
      final chunks = chunker.chunk('一二三四五六七八九十\n\n甲乙丙丁戊己庚辛壬癸\n\n子丑寅卯辰巳午未申酉');
      expect(chunks.length, 2);
      expect(chunks[1].content, contains('甲乙丙丁'));
    });

    test('关键词召回命中中文（混合分词）', () {
      final idx = InMemoryIndex();
      idx.addChunk(
        IndexedChunk(
          SourceChunk(
            id: 'c1',
            sourceId: 's1',
            sourceRevision: 1,
            index: 0,
            content: 'Spring Boot 事务隔离',
          ),
          'p1',
        ),
      );
      idx.addChunk(
        IndexedChunk(
          SourceChunk(
            id: 'c2',
            sourceId: 's1',
            sourceRevision: 1,
            index: 1,
            content: 'HashMap 扩容',
          ),
          'p1',
        ),
      );
      final scores = idx.keywordRecall('事务');
      expect(scores.containsKey('c1'), isTrue);
      expect(scores.containsKey('c2'), isFalse);
    });

    test('余弦相似度仅在同一 embedding profile 内比较', () {
      final idx = InMemoryIndex();
      idx.addEmbedding('c1', 'e1', [1, 0, 0]);
      idx.addEmbedding('c2', 'e1', [0.9, 0.1, 0]);
      idx.addEmbedding('c3', 'e2', [1, 0, 0]);
      final top = idx.cosineTopK([1, 0, 0], 'e1');
      expect(top.length, 2);
      expect(top.first.$1, 'c1');
    });
  });

  group('定向 RAG - 导入与检索', () {
    test('DocumentImporter 生成 Source/分块并计算内容哈希', () async {
      final importer = DocumentImporter(
        parser: PlainTextParser(),
        chunker: Chunker(),
        idGen: IdGenerator.deterministic(),
        clock: FixedClock(now),
      );
      final res = await importer.importText(
        ImportRequest(
          text: '第一段。\n\n第二段。',
          title: '演示资料',
          type: SourceType.markdown,
          profileId: 'p1',
        ),
      );
      expect(res.source.title, '演示资料');
      expect(res.source.type, SourceType.markdown);
      expect(res.source.status, IngestionStatus.ready);
      expect(res.chunks.length, 1);
      expect(res.chunks.single.sourceId, res.source.id);
      expect(res.contentHash.length, 8);
    });

    test('相同内容哈希一致（去重依据）', () async {
      final importer = DocumentImporter(
        parser: PlainTextParser(),
        chunker: Chunker(),
        idGen: IdGenerator.deterministic(),
        clock: FixedClock(now),
      );
      final a = await importer.importText(
        ImportRequest(text: '完全相同的内容', profileId: 'p1'),
      );
      final b = await importer.importText(
        ImportRequest(text: '完全相同的内容', profileId: 'p1'),
      );
      expect(a.contentHash, b.contentHash);
      expect(a.source.id == b.source.id, isFalse);
    });

    test('KnowledgeRetriever 做档案/知识点范围过滤', () async {
      final idx = InMemoryIndex();
      idx.addSource(
        Source(
          id: 's1',
          profileId: 'p1',
          title: '资料1',
          type: SourceType.txt,
          contentHash: 'h1',
          status: IngestionStatus.ready,
        ),
      );
      idx.addSource(
        Source(
          id: 's2',
          profileId: 'p2',
          title: '资料2',
          type: SourceType.txt,
          contentHash: 'h2',
          status: IngestionStatus.ready,
        ),
      );
      idx.addChunk(
        IndexedChunk(
          SourceChunk(
            id: 'c1',
            sourceId: 's1',
            sourceRevision: 1,
            index: 0,
            content: '事务隔离级别',
          ),
          'p1',
          knowledgeItemId: 'k1',
        ),
      );
      idx.addChunk(
        IndexedChunk(
          SourceChunk(
            id: 'c2',
            sourceId: 's2',
            sourceRevision: 1,
            index: 0,
            content: '事务隔离级别',
          ),
          'p2',
        ),
      );
      final retriever = KnowledgeRetriever(index: idx);
      final hits = await retriever.retrieve('事务隔离', profileId: 'p1');
      expect(hits.length, 1);
      expect(hits.single.citationId, 'c1');

      final noHit = await retriever.retrieve(
        '事务隔离',
        profileId: 'p1',
        knowledgeItemId: 'k9',
      );
      expect(noHit.length, 0);
    });
  });

  group('岗位 - 链接解析与搜索', () {
    test('extractFirstUrl 从说明文字中提取链接', () {
      expect(
        extractFirstUrl(
          '看看这个 https://www.zhipin.com/job_detail/abc123.html ，谢谢',
        ),
        'https://www.zhipin.com/job_detail/abc123.html',
      );
    });

    test('parseJobLink 识别平台/岗位 ID 并去跟踪参数', () {
      final p = parseJobLink(
        'https://www.zhipin.com/job_detail/abc123.html?utm_source=share&spm=1',
      );
      expect(p!.platform, JobPlatform.boss);
      expect(p.externalJobId, 'abc123');
      expect(p.url.contains('utm_source'), isFalse);
      expect(p.url.contains('spm'), isFalse);
    });

    test('无链接时返回 null（引导手动粘贴）', () {
      expect(parseJobLink('这里没有任何链接'), null);
    });

    test('WebSearchJobAdapter 映射原始结果并标注完整性', () async {
      final adapter = WebSearchJobAdapter(
        transport: _FakeTransport([
          RawSearchItem(
            title: 'Java 后端',
            company: '示例科技',
            salary: '20-30K',
            url: 'https://www.zhipin.com/job_detail/x1.html',
          ),
          RawSearchItem(title: '无链接岗位'),
        ]),
        idGen: IdGenerator.deterministic(),
      );
      final cards = await adapter.search(SearchQuery(keywords: 'java'));
      expect(cards.length, 2);
      expect(cards[0].platform, JobPlatform.boss);
      expect(cards[0].completeness, 'summary');
      expect(cards[1].completeness, 'link_only');
      expect(cards[1].url, null);
    });
  });

  group('岗位 - JD 导入', () {
    test('importFromText 构建目标与能力要求', () async {
      final svc = JdImportService(
        fetcher: _FakeFetcher(''),
        parser: ModelJdParser(
          _jsonModel({
            'title': 'Java 后端（演示）',
            'company': '示例科技',
            'location': '杭州',
            'salaryText': '20-30K',
            'requirements': [
              {
                'statement': '精通 Java',
                'type': 'hardRequirement',
                'importance': 'high',
                'jdSourceSpan': '精通 Java',
              },
              {
                'statement': '了解 Redis',
                'type': 'niceToHave',
                'importance': 'medium',
                'inferred': true,
              },
            ],
          }),
        ),
        idGen: IdGenerator.deterministic(),
        clock: FixedClock(now),
      );
      final res = await svc.importFromText(
        'JD 正文',
        profileId: 'p1',
        platform: JobPlatform.boss,
        url: 'https://x',
      );
      expect(res.status, JobImportStatus.complete);
      expect(res.goal.title, 'Java 后端（演示）');
      expect(res.goal.platform, 'boss');
      expect(res.goal.active, isTrue);
      expect(res.requirements.length, 2);
      expect(res.requirements.first.importance, Importance.high);
      expect(res.requirements[1].inferred, isTrue);
    });

    test('importFromUrl 正文为空 → takenDown（保留快照）', () async {
      final svc = JdImportService(
        fetcher: _FakeFetcher('   '),
        parser: ModelJdParser(_jsonModel({'title': 't', 'requirements': []})),
        idGen: IdGenerator.deterministic(),
        clock: FixedClock(now),
      );
      final link = parseJobLink('https://www.zhipin.com/job_detail/abc.html')!;
      final res = await svc.importFromUrl(link, profileId: 'p1');
      expect(res.status, JobImportStatus.takenDown);
    });

    test('抓取失败 → failed 且目标未激活', () async {
      final svc = JdImportService(
        fetcher: _ThrowingFetcher(),
        parser: ModelJdParser(_jsonModel({'title': 't', 'requirements': []})),
        idGen: IdGenerator.deterministic(),
        clock: FixedClock(now),
      );
      final link = parseJobLink('https://www.zhipin.com/job_detail/abc.html')!;
      final res = await svc.importFromUrl(link, profileId: 'p1');
      expect(res.status, JobImportStatus.failed);
      expect(res.goal.active, isFalse);
    });

    test('模型解析失败 → failed（不伪造要求）', () async {
      final svc = JdImportService(
        fetcher: _FakeFetcher('x'),
        parser: ModelJdParser(
          MockModelGateway(responder: (_) => throw StateError('boom')),
        ),
        idGen: IdGenerator.deterministic(),
        clock: FixedClock(now),
      );
      final res = await svc.importFromText('JD', profileId: 'p1');
      expect(res.status, JobImportStatus.failed);
      expect(res.requirements.length, 0);
    });
  });

  group('简历 - 主张映射', () {
    test('产出 jdAndResume / jdOnly / resumeOnly 三类依据', () async {
      final matcher = KeywordClaimMatcher();
      final reqs = [
        GoalRequirement(
          id: 'r1',
          goalId: 'g',
          profileId: 'p',
          type: RequirementType.hardRequirement,
          title: '订单重复提交处理',
        ),
        GoalRequirement(
          id: 'r2',
          goalId: 'g',
          profileId: 'p',
          type: RequirementType.capability,
          title: '分布式事务',
        ),
      ];
      final links = await matcher.match(
        claimStatements: ['负责订单重复提交处理，保证幂等', '熟悉 Redis 缓存'],
        requirements: reqs,
      );
      final r1 = links.firstWhere((l) => l.requirementId == 'r1');
      expect(r1.mappingType, 'jdAndResume');
      expect(r1.claimIndex, 0);
      final r2 = links.firstWhere((l) => l.requirementId == 'r2');
      expect(r2.mappingType, 'jdOnly');
      final resumeOnly = links
          .where((l) => l.mappingType == 'resumeOnly')
          .toList();
      expect(resumeOnly.length, 1);
      expect(resumeOnly.single.claimIndex, 1);
    });
  });

  group('简历 - 解析与导入', () {
    test('RuleBasedResumeParser 按项目标题切块提取要点', () async {
      const parser = RuleBasedResumeParser();
      final res = await parser.parse(
        '项目：订单系统\n- 负责订单重复提交处理\n- 使用唯一请求号保证幂等\n项目：支付网关\n- 负责对账',
      );
      expect(res.projects.length, 2);
      expect(res.projects.first.name, contains('订单系统'));
      expect(res.claims.length, 3);
      expect(res.claims.first.statement, '负责订单重复提交处理');
      expect(res.claims.first.projectName, contains('订单系统'));
    });

    test('ResumeImportService 生成 Resume/Project/Claim 并按需映射', () async {
      final svc = ResumeImportService(
        parser: const RuleBasedResumeParser(),
        idGen: IdGenerator.deterministic(),
        clock: FixedClock(now),
        matcher: KeywordClaimMatcher(),
      );
      final res = await svc.importText(
        '项目：订单系统\n- 负责订单重复提交处理',
        profileId: 'p1',
        fileName: 'demo-resume.txt',
        requirements: [
          GoalRequirement(
            id: 'r1',
            goalId: 'g',
            profileId: 'p1',
            type: RequirementType.hardRequirement,
            title: '订单重复提交处理',
          ),
        ],
      );
      expect(res.resume.fileName, 'demo-resume.txt');
      expect(res.projects.length, 1);
      expect(res.claims.length, 1);
      // 主张默认待确认，不能从 JD 补成已做事实。
      expect(res.claims.single.status, ClaimStatus.pending);
      expect(res.claims.single.projectId, res.projects.single.id);
      expect(res.links.length, 1);
      expect(res.links.single.mappingType, 'jdAndResume');
      expect(res.links.single.claimId, res.claims.single.id);
    });
  });
}

// ---- 测试替身 ----

OpenAiCompatibleGateway _gateway(HttpClient http) => OpenAiCompatibleGateway(
  baseUrl: 'https://api.example.com/v1',
  apiKey: 'demo-key',
  model: 'demo-model',
  http: http,
);

MockModelGateway _jsonModel(Map<String, dynamic> payload) => MockModelGateway(
  responder: (_) => ModelGatewayResponse(
    message: ChatMessage.assistant(content: jsonEncode(payload)),
  ),
);

String _sse(Map<String, dynamic> payload) => 'data: ${jsonEncode(payload)}\n\n';

class _FakeHttp implements HttpClient {
  _FakeHttp({this.postBody, this.postStatus = 200, this.sseChunks = const []});
  final String? postBody;
  final int postStatus;
  final List<String> sseChunks;

  @override
  Future<HttpResponse> post(
    String url, {
    Map<String, String>? headers,
    required String body,
    CancelToken? cancel,
  }) async => HttpResponse(statusCode: postStatus, body: postBody ?? '{}');

  @override
  Stream<String> postStreaming(
    String url, {
    Map<String, String>? headers,
    required String body,
    CancelToken? cancel,
  }) async* {
    for (final chunk in sseChunks) {
      yield chunk;
    }
  }
}

class _FakeTransport implements JobSearchTransport {
  _FakeTransport(this.items);
  final List<RawSearchItem> items;

  @override
  Future<RawSearchResponse> fetch(
    SearchQuery query, {
    CancelToken? cancel,
  }) async => RawSearchResponse(items: items);
}

class _FakeFetcher implements JdFetcher {
  _FakeFetcher(this.text);
  final String text;

  @override
  Future<String> fetchText(String url, {CancelToken? cancel}) async => text;
}

class _ThrowingFetcher implements JdFetcher {
  @override
  Future<String> fetchText(String url, {CancelToken? cancel}) async =>
      throw Exception('网络错误');
}

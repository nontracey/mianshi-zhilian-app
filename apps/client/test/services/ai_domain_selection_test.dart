import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mianshi_zhilian/models/ai_config.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/services/ai_route_generator.dart';

import '../helpers/mocks.mocks.dart';

/// 本地领域匹配（无 AI / AI 失败时的降级）准确度：宁缺毋滥，
/// 「agent 目标不应混入前端八股」「java 目标不应拉一堆无关领域」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Domain dom(String id, String title, String desc) =>
      Domain(id: id, title: title, description: desc);

  final allDomains = [
    dom('java', 'Java 核心与中间件', 'JVM、并发、Spring、中间件'),
    dom('python', 'Python 开发', 'Python 基础、并发、Web'),
    dom('agent', 'Agent 开发', 'LLM、RAG、Agent、MCP'),
    dom('frontend', '前端八股', 'JavaScript、React、Vue、Node.js'),
    dom('algorithm', '算法与数据结构', '数组、链表、树、动态规划'),
    dom('dotnet', '.NET 开发', 'C#、ASP.NET、WPF'),
  ];

  late MockAiService mockAi;
  late AiRouteGenerator generator;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockAi = MockAiService();
    generator = AiRouteGenerator(allDomains);
    // 强制走本地降级：AI 调用抛错
    when(mockAi.isConfigAvailable(any)).thenReturn(true);
    when(mockAi.sendMessage(any, config: anyNamed('config')))
        .thenThrow(Exception('no network'));
  });

  Future<List<String>> select(PrepPlan plan) => generator.selectDomainIds(
        plan: plan,
        aiService: mockAi,
        aiConfig: const AiConfig(
            id: 't', name: 't', baseUrl: 'x', apiKey: 'k', model: 'm'),
      );

  test('agent goal does NOT pull in frontend', () async {
    final ids = await select(PrepPlan(
      targetRole: 'AI Agent 开发工程师',
      techStack: 'Python LangChain RAG',
      jobDescription: '',
      updatedAt: DateTime(2026),
    ));
    expect(ids, contains('agent'));
    expect(ids, contains('python'));
    expect(ids, isNot(contains('frontend')));
    expect(ids, isNot(contains('dotnet')));
    expect(ids.length, lessThanOrEqualTo(4));
  });

  test('java backend goal stays focused, not a 7-domain sprawl', () async {
    final ids = await select(PrepPlan(
      targetRole: 'Java 后端工程师',
      techStack: 'Java Spring Boot',
      jobDescription: '',
      updatedAt: DateTime(2026),
    ));
    expect(ids, contains('java'));
    expect(ids, isNot(contains('frontend')));
    expect(ids.length, lessThanOrEqualTo(4));
  });

  test('frontend goal selects frontend, not jvm/middleware domains', () async {
    final ids = await select(PrepPlan(
      targetRole: '前端工程师',
      techStack: 'React TypeScript',
      jobDescription: '',
      updatedAt: DateTime(2026),
    ));
    expect(ids, contains('frontend'));
    expect(ids, isNot(contains('java')));
  });

  test('empty-ish goal falls back to a single default domain, not all', () async {
    final ids = await select(PrepPlan(updatedAt: DateTime(2026)));
    expect(ids.length, 1);
  });
}

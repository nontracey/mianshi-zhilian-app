import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mianshi_zhilian/models/learning_route.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/learning_scope_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/services/content_api_service.dart';
import 'package:mianshi_zhilian/services/route_composer.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/widgets/scope_selector_dialog.dart';

import '../helpers/fake_content_client.dart';

/// 关键 UI 冒烟：范围选择 Chip 正确反映「路线模式 + 路线名」，
/// 验证 scope → 展示层接线。
///
/// 说明：整页（CatalogPage/DashboardPage）的像素级 widget 测试在测试视口下
/// 布局约束很脆（unbounded RenderFlex），性价比低；其数据正确性已由
/// integration/ 下的业务层端到端测试覆盖（如跨域路线解析出全部 topic）。
/// 这里只对小而稳定的关键控件做冒烟。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ScopeSelectorChip 在路线模式显示路线名', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    final content = ContentProvider(
      ContentApiService(baseUrl: 'https://fake.test', httpClient: FakeContentClient()),
      storage,
    );
    final scope = LearningScopeProvider(storage);
    final l10n = LocalizationProvider(initialLanguage: 'zh');

    await content.loadContent();
    await content.loadDomainTopics('java');
    await content.loadDomainTopics('agent');
    await content.loadDomainTopics('python');
    await scope.load();

    final phases = RouteComposer.composePhasesFromContent(
      orderedDomainIds: ['java', 'agent', 'python'],
      allDomains: content.domains,
      getTopicById: content.getTopicById,
    );
    await scope.upsertRoute(
      LearningRoute(
        id: 'r',
        name: '我的备考路线',
        domainIds: RouteComposer.domainsOf(phases),
        phases: phases,
        source: 'custom',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      activate: true,
      contentProvider: content,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: content),
          ChangeNotifierProvider.value(value: scope),
          ChangeNotifierProvider.value(value: l10n),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(child: ScopeSelectorChip()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(scope.isRouteMode, isTrue);
    expect(find.text('我的备考路线'), findsOneWidget);
    // 路线模式用 route 图标
    expect(find.byIcon(Icons.route), findsOneWidget);
  });
}

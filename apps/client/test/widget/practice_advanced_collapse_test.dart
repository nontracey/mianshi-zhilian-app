import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mianshi_zhilian/models/learning_scope.dart';
import 'package:mianshi_zhilian/pages/practice/practice_page.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/learning_scope_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/providers/theme_provider.dart';
import 'package:mianshi_zhilian/services/content_api_service.dart';
import 'package:mianshi_zhilian/services/data_sync_service.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';

import '../helpers/fake_content_client.dart';

/// 关键 UI 冒烟（U-6）：练习中心首屏只突出 3 个核心模式，进阶模式默认折叠，
/// 展开后才出现。锁住「降噪折叠」这一交互契约。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('进阶练习默认折叠，展开后出现进阶模式卡片', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    final content = ContentProvider(
      ContentApiService(baseUrl: 'https://fake.test', httpClient: FakeContentClient()),
      storage,
    );
    final progress = ProgressProvider(storage);
    final theme = ThemeProvider();
    final settings = SettingsProvider(storage, DataSyncService(storage), theme);
    final scope = LearningScopeProvider(storage);
    final l10n = LocalizationProvider(initialLanguage: 'zh');

    await content.loadContent();
    await content.loadDomainTopics('java');
    await settings.loadSettings();
    await scope.load();
    await scope.setScope(LearningScope.singleDomain('java'), contentProvider: content);

    final advancedHeader = l10n.get('practice_advanced'); // 进阶练习
    final followUp = l10n.get('follow_up_training'); // 追问训练（进阶卡片）

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: content),
          ChangeNotifierProvider.value(value: progress),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: scope),
          ChangeNotifierProvider.value(value: l10n),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1100,
              height: 1900,
              child: PracticePage(
                onDailyReview: () {},
                onRandomQuiz: (_) {},
                onMockInterview: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 进阶分区标题在（折叠态也显示标题），但进阶模式卡片默认不出现
    expect(find.text(advancedHeader), findsOneWidget);
    expect(find.text(followUp), findsNothing, reason: '进阶模式默认应折叠');

    // 展开进阶分区
    await tester.tap(find.text(advancedHeader));
    await tester.pumpAndSettle();

    expect(find.text(followUp), findsOneWidget, reason: '展开后应出现进阶模式卡片');
  });
}

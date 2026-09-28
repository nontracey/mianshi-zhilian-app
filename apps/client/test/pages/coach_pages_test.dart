/// coach 入口页面的搭建冒烟测试。
///
/// 目的不是验证业务逻辑（那由 test/coach 下的纯 Dart 单测覆盖），而是保证
/// **每个页面都能在真实 provider 环境里成功 build 并完成首帧**：
/// 这类错误（引用了不存在的 widget、provider 里缺字段、异步 load 抛错）
/// 只在运行时暴露，静态分析查不出来。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/jobs/jd_import_service.dart';
import 'package:mianshi_zhilian/coach/knowledge/chunker.dart';
import 'package:mianshi_zhilian/coach/knowledge/importer.dart';
import 'package:mianshi_zhilian/coach/knowledge/parser.dart';
import 'package:mianshi_zhilian/coach/knowledge/source.dart';
// coach 的 HttpClient 与 dart:io 同名，这里只需要 CancelToken / HttpCanceledException。
import 'package:mianshi_zhilian/coach/model/http_client.dart'
    hide HttpClient, HttpResponse;
import 'package:mianshi_zhilian/coach/persistence/coach_store.dart';
import 'package:mianshi_zhilian/coach/persistence/extension_records.dart';
import 'package:mianshi_zhilian/coach/resume/claim_mapping.dart';
import 'package:mianshi_zhilian/coach/resume/resume_parse.dart';
import 'package:mianshi_zhilian/pages/coach/coach_shell.dart';
import 'package:mianshi_zhilian/pages/coach/goals_materials_page.dart';
import 'package:mianshi_zhilian/pages/coach/sync_conflicts_page.dart';
import 'package:mianshi_zhilian/pages/coach/deletion_preview_page.dart';
import 'package:mianshi_zhilian/pages/coach/interview_page.dart';
import 'package:mianshi_zhilian/pages/coach/interview_report_page.dart';
import 'package:mianshi_zhilian/pages/coach/job_search_page.dart';
import 'package:mianshi_zhilian/pages/coach/resume_review_page.dart';
import 'package:mianshi_zhilian/pages/coach/today_page.dart';
import 'package:mianshi_zhilian/pages/coach/training_arrangement_page.dart';
import 'package:mianshi_zhilian/providers/coach_provider.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/goal_provider.dart';
import 'package:mianshi_zhilian/providers/learning_scope_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/providers/theme_provider.dart';
import 'package:mianshi_zhilian/services/content_api_service.dart';
import 'package:mianshi_zhilian/services/data_sync_service.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';

import '../helpers/fake_content_client.dart';

/// 不联网的 JD 抓取器：导入链路会返回明确的失败状态。
class _UnsupportedJdFetcher implements JdFetcher {
  @override
  Future<String> fetchText(String url, {CancelToken? cancel}) async {
    throw HttpCanceledException();
  }
}

/// 把 [page] 挂到真实的 provider 组合上，并等待首帧之后的异步加载完成。
Future<void> _pumpCoach(
  WidgetTester tester,
  Widget page, {
  CoachStore? store,
}) async {
  final shared = store ?? InMemoryCoachStore();
  final idGen = IdGenerator();

  final coachProvider = CoachProvider(store: shared, idGen: idGen);
  final goalProvider = GoalProvider(
    store: shared,
    documents: DocumentImporter(
      parser: const BuiltInDocumentParser(),
      chunker: Chunker(),
      idGen: idGen,
      clock: const SystemClock(),
    ),
    resumeImport: ResumeImportService(
      parser: const RuleBasedResumeParser(),
      idGen: idGen,
      clock: const SystemClock(),
      matcher: KeywordClaimMatcher(),
    ),
    jdImport: JdImportService(
      fetcher: _UnsupportedJdFetcher(),
      parser: const HeuristicJdParser(),
      idGen: idGen,
      clock: const SystemClock(),
    ),
  );

  // 先加载一次，让页面首帧就有档案/目标状态，而不是空指针。
  await coachProvider.load();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LocalizationProvider>.value(
          value: LocalizationProvider(initialLanguage: 'zh'),
        ),
        ChangeNotifierProvider<CoachProvider>.value(value: coachProvider),
        ChangeNotifierProvider<GoalProvider>.value(value: goalProvider),
      ],
      child: MaterialApp(home: page),
    ),
  );

  // 页面里的 postFrameCallback 异步加载需要额外的 pump 才能稳定。
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // NavigationBar 里选中项显示 selectedIcon，其余显示 outlined 图标。
  // 按初始选中顺序依次切换：tab0 选中(filled) → tab1 → tab2。
  const _tabIcons = [
    Icons.menu_book,
    Icons.today_outlined,
    Icons.donut_large_outlined,
  ];

  /// CoachShell 现在内嵌内容库/掌握度页（CDN 内容源），
  /// 需要完整的内容侧 provider 组合。
  Future<void> _pumpShell(WidgetTester tester, Widget page) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    final content = ContentProvider(
      ContentApiService(
        baseUrl: 'https://fake.test',
        httpClient: FakeContentClient(),
      ),
      storage,
    );
    final settings = SettingsProvider(
      storage,
      DataSyncService(storage),
      ThemeProvider(),
    );
    await settings.loadSettings();
    final progress = ProgressProvider(storage)..loadProgress();
    final scope = LearningScopeProvider(storage)..load();
    await content.loadContent();

    final shared = InMemoryCoachStore();
    final idGen = IdGenerator();
    final coachProvider = CoachProvider(store: shared, idGen: idGen);
    final goalProvider = GoalProvider(
      store: shared,
      documents: DocumentImporter(
        parser: const BuiltInDocumentParser(),
        chunker: Chunker(),
        idGen: idGen,
        clock: const SystemClock(),
      ),
      resumeImport: ResumeImportService(
        parser: const RuleBasedResumeParser(),
        idGen: idGen,
        clock: const SystemClock(),
        matcher: KeywordClaimMatcher(),
      ),
      jdImport: JdImportService(
        fetcher: _UnsupportedJdFetcher(),
        parser: const HeuristicJdParser(),
        idGen: idGen,
        clock: const SystemClock(),
      ),
    );
    await coachProvider.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalizationProvider>.value(
            value: LocalizationProvider(initialLanguage: 'zh'),
          ),
          ChangeNotifierProvider<ContentProvider>.value(value: content),
          ChangeNotifierProvider<ProgressProvider>.value(value: progress),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<LearningScopeProvider>.value(value: scope),
          ChangeNotifierProvider<CoachProvider>.value(value: coachProvider),
          ChangeNotifierProvider<GoalProvider>.value(value: goalProvider),
        ],
        child: MaterialApp(home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('CoachShell 三入口（知识/学习/掌握度）都能 build', (tester) async {
    await _pumpShell(tester, const CoachShell());
    expect(find.byType(CoachShell), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    // 三个 tab 依次可切换且都能完成首帧。
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(_tabIcons[i]));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('TodayPage 空状态可渲染', (tester) async {
    await _pumpCoach(tester, const TodayPage());
    expect(find.byType(TodayPage), findsOneWidget);
  });

  testWidgets('InterviewPage 可渲染（含训练安排入口）', (tester) async {
    await _pumpCoach(tester, const InterviewPage());
    expect(find.byType(InterviewPage), findsOneWidget);
  });

  testWidgets('JobSearchPage 在通道未配置时如实提示而不是空结果', (tester) async {
    await _pumpCoach(tester, const JobSearchPage());
    expect(find.byType(JobSearchPage), findsOneWidget);
    // 未配置通道时搜索按钮必须是禁用的，不能假装能搜。
    final runButton = tester.widget<FilledButton>(
      find.ancestor(of: find.text('搜索'), matching: find.byType(FilledButton)),
    );
    expect(runButton.onPressed, isNull);
  });

  testWidgets('TrainingArrangementPage 可渲染并给出内置模板卡片', (tester) async {
    await _pumpCoach(tester, const TrainingArrangementPage());
    expect(find.byType(TrainingArrangementPage), findsOneWidget);
    // 默认模板「日常推进」的第一张卡是回测已学内容。
    expect(find.text('回测已学内容'), findsWidgets);
  });

  testWidgets(
    'GoalsMaterialsPage can update a source revision from its dialog',
    (tester) async {
      final store = InMemoryCoachStore();
      await store.putSource(
        Source(
          id: 'source',
          profileId: kDefaultProfileId,
          title: 'Synthetic reference',
          type: SourceType.txt,
          contentHash: computeContentHash('Before'),
          status: IngestionStatus.ready,
          content: 'Before',
          revision: 1,
        ),
      );
      await _pumpCoach(tester, const GoalsMaterialsPage(), store: store);
      final edit = find.byTooltip('更新资料正文');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'After');
      await tester.tap(find.widgetWithText(FilledButton, '导入').last);
      await tester.pumpAndSettle();
      expect((await store.getSource('source'))!.revision, 2);
      expect((await store.getSource('source'))!.content, 'After');
    },
  );

  testWidgets(
    'CoachSyncConflictsPage shows both source texts and resolves a choice',
    (tester) async {
      final store = InMemoryCoachStore();
      for (final (id, content) in [
        ('source', 'Alpha source'),
        ('source.conflict.x', 'Beta source'),
      ]) {
        await store.putSource(
          Source(
            id: id,
            profileId: kDefaultProfileId,
            title: 'Reference',
            type: SourceType.txt,
            contentHash: computeContentHash(content),
            status: IngestionStatus.ready,
            content: content,
            revision: 1,
          ),
        );
        await store.putSourceChunk(
          SourceChunk(
            id: '$id.chunk',
            sourceId: id,
            sourceRevision: 1,
            index: 0,
            content: content,
          ),
        );
      }
      await store.putExtension(
        CoachExtensionRecord(
          profileId: kDefaultProfileId,
          kind: CoachExtensionKind.syncMetadata,
          id: 'conflict.source.x',
          revision: 1,
          value: {
            'table': 'sources',
            'entityId': 'source',
            'variantId': 'source.conflict.x',
          },
          updatedAt: DateTime(2026),
        ),
      );
      await _pumpCoach(tester, const CoachSyncConflictsPage(), store: store);
      expect(find.textContaining('Alpha source'), findsOneWidget);
      expect(find.textContaining('Beta source'), findsOneWidget);
      await tester.tap(find.text('选择另一版本'));
      await tester.pumpAndSettle();
      expect((await store.getSource('source'))!.content, 'Beta source');
      expect(find.text('没有待处理冲突'), findsOneWidget);
    },
  );

  testWidgets('ResumeReviewPage 无简历时给出导入指引', (tester) async {
    await _pumpCoach(tester, const ResumeReviewPage());
    expect(find.byType(ResumeReviewPage), findsOneWidget);
  });

  testWidgets('DeletionPreviewPage 无目标时给出空状态且禁用确认', (tester) async {
    await _pumpCoach(
      tester,
      const DeletionPreviewPage(goalIds: ['not-existing']),
    );
    expect(find.byType(DeletionPreviewPage), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.ancestor(of: find.text('确认删除'), matching: find.byType(FilledButton)),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets(
    'InterviewReportPage does not expose assessments during an unfinished interview',
    (tester) async {
      final store = InMemoryCoachStore();
      final coach = CoachProvider(store: store);
      await coach.load();
      final session = await coach.startSession(mode: SessionMode.interview);
      await _pumpCoach(
        tester,
        InterviewReportPage(sessionId: session.id, mode: SessionMode.interview),
        store: store,
      );
      expect(find.text('请先结束本场训练，再查看评价与复盘。'), findsOneWidget);
      expect(find.textContaining('没有已保存的有效评价'), findsNothing);
    },
  );

  testWidgets('InterviewReportPage 未接入模型时明确说明「没有自动点评」', (tester) async {
    final store = InMemoryCoachStore();
    final coach = CoachProvider(store: store, idGen: IdGenerator());
    await coach.load();
    final session = await coach.startSession(mode: SessionMode.interview);
    await coach.sendUserMessage('演示数据：我的原答');
    await coach.endSession();

    await _pumpCoach(
      tester,
      InterviewReportPage(sessionId: session.id, mode: SessionMode.interview),
      // 必须复用同一个 store，否则页面读不到刚写入的会话与原答。
      store: store,
    );
    expect(find.byType(InterviewReportPage), findsOneWidget);
    // 未接入模型时必须如实说明「没有自动点评、界面不会编造评语」，
    // 而不是笼统地说「没有已保存的评价」——后者会把"未接入"和"接入了但没评价"
    // 混为一谈，让用户以为评价已经跑过。
    expect(find.textContaining('未接入模型'), findsWidgets);
    // 原答必须原样回显。
    expect(find.textContaining('演示数据：我的原答'), findsWidgets);
  });
}

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'l10n/l10n.dart';

import 'theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/content_provider.dart';
import 'providers/ai_provider.dart';
import 'providers/localization_provider.dart';
import 'providers/progress_provider.dart';
import 'providers/learning_scope_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/update_download_provider.dart';
import 'services/analytics_service.dart';
import 'services/app_log_service.dart';
import 'services/data_sync_service.dart';
import 'services/endpoint_fallback_client.dart';
import 'services/route_state_store.dart';
import 'services/storage_service.dart';
import 'services/update_service.dart';
import 'services/ai_service.dart';
import 'services/content_api_service.dart';
import 'pages/auth/login_page.dart';
import 'pages/auth/change_password_page.dart';
import 'pages/profile/ai_config_page.dart';
import 'pages/profile/log_management_page.dart';
import 'pages/profile/on_device_model_management_page.dart';
import 'pages/profile/sync_backup_page.dart';
import 'pages/profile/ai_voice_settings_page.dart';
import 'pages/profile/learning_preferences_page.dart';
import 'pages/profile/appearance_language_page.dart';
import 'pages/profile/content_source_page.dart';
import 'pages/profile/route_preference_page.dart';
import 'pages/profile/about_update_page.dart';
import 'pages/profile/job_search_settings_page.dart';
import 'pages/profile/profile_page.dart';
import 'pages/profile/embedding_settings_page.dart';
import 'pages/coach/legacy_archive_page.dart';
import 'services/embedding_config_service.dart';
import 'pages/coach/coach_shell.dart';

import 'coach/domain/common.dart';
import 'coach/jobs/jd_import_service.dart';
import 'coach/knowledge/chunker.dart';
import 'coach/knowledge/importer.dart';
import 'coach/resume/claim_mapping.dart';
import 'coach/resume/resume_parse.dart';
import 'providers/coach_provider.dart';
import 'providers/goal_provider.dart';
import 'services/coach_store_factory.dart';
import 'services/pdf_document_parser.dart';
import 'services/coach_legacy_migration.dart';
import 'services/coach_material_parsers.dart';
import 'services/coach_model_binding.dart';
import 'services/coach_rules_loader.dart';
import 'services/http_jd_fetcher.dart';
import 'pages/profile/mcp_settings_page.dart';
import 'services/job_search_config.dart';
import 'services/mcp_config_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogService.instance.initialize();
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (!kReleaseMode) originalDebugPrint(message, wrapWidth: wrapWidth);
    final text = message;
    if (!kReleaseMode && text != null && text.trim().isNotEmpty) {
      unawaited(AppLog.debug(text, source: 'debugPrint'));
    }
  };
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      AppLog.error(
        details.exceptionAsString(),
        source: 'flutter',
        error: details.exception,
        stackTrace: details.stack,
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(
      AppLog.error(
        'Uncaught platform error',
        source: 'platform',
        error: error,
        stackTrace: stack,
      ),
    );
    return false;
  };

  final storage = StorageService();
  final routeClient = EndpointFallbackClient(
    stateStore: EndpointStateStore(storage),
  );
  // 先加载已保存的设置，获取正确的 contentBaseUrl
  final savedSettings = await storage.loadSettings();
  final contentApi = ContentApiService(
    baseUrl: savedSettings.contentBaseUrl,
    routeClient: routeClient,
  );
  final aiService = AiService();
  final aiProvider = AiProvider(aiService, storage);
  await aiProvider.loadConfigs();
  final updateService = UpdateService(routeClient: routeClient);
  final dataSyncService = DataSyncService(storage);
  final analyticsService = AnalyticsService(storage, routeClient: routeClient)
    ..start();
  final connectivityProvider = ConnectivityProvider()..start();

  // ── 教练模块（目标化改造）──
  // 存储不可用时关闭教练写入，旧功能仍可使用。
  final coachStoreHandle = await openCoachStore();
  final coachStore = coachStoreHandle.store;
  final idGen = IdGenerator();
  final clock = const SystemClock();

  // 教练用的模型网关：直接读用户在「AI 配置」里填的服务，不另建一套凭据。
  // 没有可用文本配置时返回 null，教练如实显示“未配置”，不生成自动点评。
  final coachModels = CoachModelBindingFactory(
    selector: () =>
        defaultCoachConfig(aiProvider.configs, aiProvider.defaultConfig),
  );
  final coachRules = CoachRulesLoader();

  final mcpConfigService = McpConfigService(
    store: coachStore,
    storage: storage,
  );
  final embeddingService = EmbeddingConfigService(
    store: coachStore,
    storage: storage,
    profileId: kDefaultProfileId,
  );
  if (coachStoreHandle.available) await embeddingService.load();
  final coachProvider = CoachProvider(
    store: coachStore,
    modelBindingProvider: coachModels,
    rulesProvider: coachRules.load,
    remoteToolsProvider: mcpConfigService.openCoachTools,
  );
  if (coachStoreHandle.available) {
    dataSyncService.attachCoach(
      coachStore,
      canImport: () => !coachProvider.isGenerating,
      onImported: coachProvider.reload,
    );
  }
  coachProvider.setEmbeddingProvider(embeddingService.provider);
  embeddingService.addListener(
    () => coachProvider.setEmbeddingProvider(embeddingService.provider),
  );
  final jobSearchConfig = JobSearchConfigController(storage: storage);
  await jobSearchConfig.sync(savedSettings);

  final goalProvider = GoalProvider(
    store: coachStore,
    canMutate: () => !coachProvider.isGenerating,
    // 通道随设置变化，这里传“每次现取”的函数而不是固定实例。
    jobSearchProvider: () => jobSearchConfig.service,
    channelProvider: () => jobSearchConfig.state,
    documents: DocumentImporter(
      // 文本/粘贴导入不走字节解析器；PDF/DOCX 未配置时明确抛错，不静默通过。
      parser: const PdfDocumentParser(),
      chunker: Chunker(),
      idGen: idGen,
      clock: clock,
    ),
    resumeImport: ResumeImportService(
      // 使用当前 AI 提取草稿，失败时保留离线解析和原文。
      parser: ConfiguredResumeParser(coachModels.call),
      idGen: idGen,
      clock: clock,
      matcher: KeywordClaimMatcher(),
    ),
    jdImport: JdImportService(
      fetcher: HttpJdFetcher(),
      // 模型提案必须锚定原文，否则标为待确认推断。
      parser: ConfiguredJdParser(coachModels.call),
      idGen: idGen,
      clock: clock,
    ),
  );
  // 目标/资料变更后，让教练状态（今天计划、目标要求）及时刷新。
  goalProvider.onDataChanged = coachProvider.reload;
  if (coachStoreHandle.available) {
    await coachProvider.load();
    // 旧版练习原答 → 教练库（可重入，失败不阻塞启动）。
    await migrateLegacyPracticeData(storage: storage, store: coachStore);
    await coachProvider.reload();
  }

  runApp(
    MianshiZhilianApp(
      storage: storage,
      dataSyncService: dataSyncService,
      analyticsService: analyticsService,
      contentApi: contentApi,
      aiService: aiService,
      updateService: updateService,
      routeClient: routeClient,
      initialLanguage: savedSettings.language,
      aiProvider: aiProvider,
      themeProvider: ThemeProvider(),
      connectivityProvider: connectivityProvider,
      coachStoreHandle: coachStoreHandle,
      coachProvider: coachProvider,
      goalProvider: goalProvider,
      coachModels: coachModels,
      jobSearchConfig: jobSearchConfig,
      mcpConfigService: mcpConfigService,
      embeddingService: embeddingService,
    ),
  );
}

class MianshiZhilianApp extends StatefulWidget {
  final StorageService storage;
  final DataSyncService dataSyncService;
  final AnalyticsService analyticsService;
  final ContentApiService contentApi;
  final AiService aiService;
  final UpdateService updateService;
  final EndpointFallbackClient routeClient;
  final String initialLanguage;
  final ThemeProvider themeProvider;
  final ConnectivityProvider connectivityProvider;
  final CoachStoreHandle coachStoreHandle;
  final CoachProvider coachProvider;
  final GoalProvider goalProvider;
  final CoachModelBindingFactory coachModels;
  final JobSearchConfigController jobSearchConfig;
  final McpConfigService mcpConfigService;
  final AiProvider aiProvider;
  final EmbeddingConfigService? embeddingService;

  const MianshiZhilianApp({
    super.key,
    required this.storage,
    required this.dataSyncService,
    required this.analyticsService,
    required this.contentApi,
    required this.aiService,
    required this.updateService,
    required this.routeClient,
    required this.initialLanguage,
    required this.themeProvider,
    required this.connectivityProvider,
    required this.coachStoreHandle,
    required this.coachProvider,
    required this.goalProvider,
    required this.coachModels,
    required this.jobSearchConfig,
    required this.mcpConfigService,
    required this.aiProvider,
    this.embeddingService,
  });

  @override
  State<MianshiZhilianApp> createState() => _MianshiZhilianAppState();
}

class _MianshiZhilianAppState extends State<MianshiZhilianApp> {
  Widget _withCoachStorage(BuildContext context, Widget child) {
    if (widget.coachStoreHandle.available) return child;
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.watch<LocalizationProvider>().get(
              widget.coachStoreHandle.unavailableReasonKey!,
            ),
          ),
        ),
      ),
    );
  }

  bool _contentLoaded = false;
  late final GoRouter _router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => _withCoachStorage(context, const CoachShell()),
      ),
      GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
      GoRoute(
        path: '/profile/legacy',
        builder: (context, _) =>
            _withCoachStorage(context, const LegacyArchivePage()),
      ),
      GoRoute(
        path: '/profile/embedding',
        builder: (context, _) =>
            _withCoachStorage(context, const EmbeddingSettingsPage()),
      ),
      GoRoute(
        path: '/coach',
        builder: (context, state) => _withCoachStorage(
          context,
          CoachShell(initialIndex: (state.extra as int?) ?? 0),
        ),
      ),
      GoRoute(
        path: '/topic',
        redirect: (_, state) => state.extra == null ? '/' : null,
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/recall',
        redirect: (_, state) => state.extra == null ? '/' : null,
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/mock-interview',
        redirect: (_, state) => state.extra == null ? '/' : null,
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/today-review',
        redirect: (_, state) => state.extra == null ? '/' : null,
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/weakness-training',
        redirect: (_, state) => state.extra == null ? '/' : null,
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/answer-versions',
        redirect: (_, state) => state.extra == null ? '/' : null,
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/follow-up-training',
        redirect: (_, state) => state.extra == null ? '/' : null,
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/high-frequency',
        redirect: (_, state) => state.extra == null ? '/' : null,
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/system-design',
        redirect: (_, state) => state.extra == null ? '/' : null,
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/project-dig',
        redirect: (_, state) => state.extra == null ? '/' : null,
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/auth/login',
        builder: (_, state) => state.extra as Widget? ?? const LoginPage(),
      ),
      GoRoute(
        path: '/auth/change-password',
        builder: (_, state) =>
            state.extra as Widget? ?? const ChangePasswordPage(),
      ),
      GoRoute(
        path: '/auth/submit-ticket',
        redirect: (_, state) => state.extra == null ? '/' : null,
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/profile/ai-config',
        builder: (_, state) => state.extra as Widget? ?? const AiConfigPage(),
      ),
      GoRoute(
        path: '/profile/log-management',
        builder: (_, state) =>
            state.extra as Widget? ?? const LogManagementPage(),
      ),
      GoRoute(
        path: '/profile/model-management',
        builder: (_, state) =>
            state.extra as Widget? ?? const OnDeviceModelManagementPage(),
      ),
      GoRoute(
        path: '/profile/sync-backup',
        builder: (_, state) => state.extra as Widget? ?? const SyncBackupPage(),
      ),
      GoRoute(
        path: '/profile/ai-voice-settings',
        builder: (_, state) =>
            state.extra as Widget? ?? const AiVoiceSettingsPage(),
      ),
      GoRoute(
        path: '/profile/learning-preferences',
        builder: (_, state) =>
            state.extra as Widget? ?? const LearningPreferencesPage(),
      ),
      GoRoute(
        path: '/profile/appearance-language',
        builder: (_, state) =>
            state.extra as Widget? ?? const AppearanceLanguagePage(),
      ),
      GoRoute(
        path: '/profile/content-source',
        builder: (_, state) =>
            state.extra as Widget? ?? const ContentSourcePage(),
      ),
      GoRoute(
        path: '/profile/route-preference',
        builder: (_, state) =>
            state.extra as Widget? ?? const RoutePreferencePage(),
      ),
      GoRoute(
        path: '/profile/about-update',
        builder: (_, state) =>
            state.extra as Widget? ?? const AboutUpdatePage(),
      ),
      GoRoute(
        path: '/profile/job-search',
        builder: (_, state) =>
            state.extra as Widget? ?? const JobSearchSettingsPage(),
      ),
      GoRoute(
        path: '/profile/mcp-services',
        builder: (context, state) => _withCoachStorage(
          context,
          state.extra as Widget? ?? const McpSettingsPage(),
        ),
      ),
    ],
  );

  @override
  void dispose() {
    widget.dataSyncService.stop();
    widget.analyticsService.stop();
    widget.connectivityProvider.dispose();
    widget.coachProvider.dispose();
    widget.goalProvider.dispose();
    widget.coachStoreHandle.dispose();
    widget.coachModels.dispose();
    widget.embeddingService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.connectivityProvider),
        ChangeNotifierProvider.value(value: widget.themeProvider),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(
            widget.storage,
            widget.dataSyncService,
            widget.themeProvider,
          )..loadSettings(),
        ),
        ChangeNotifierProvider(
          create: (_) => ContentProvider(widget.contentApi, widget.storage),
        ),
        ChangeNotifierProvider.value(value: widget.aiProvider),
        ChangeNotifierProvider(
          create: (_) => ProgressProvider(widget.storage)..loadProgress(),
        ),
        ChangeNotifierProvider(
          create: (_) => LearningScopeProvider(widget.storage),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              AuthProvider(widget.storage, routeClient: widget.routeClient)
                ..loadUser(),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              LocalizationProvider(initialLanguage: widget.initialLanguage),
        ),
        Provider<AnalyticsService>.value(value: widget.analyticsService),
        Provider<DataSyncService>.value(value: widget.dataSyncService),
        if (widget.embeddingService != null)
          ChangeNotifierProvider<EmbeddingConfigService>.value(
            value: widget.embeddingService!,
          ),
        ChangeNotifierProvider(
          create: (_) => UpdateDownloadProvider(widget.storage),
        ),
        // 教练模块：共享同一 CoachStore 的两个状态源。
        ChangeNotifierProvider<CoachProvider>.value(
          value: widget.coachProvider,
        ),
        ChangeNotifierProvider<GoalProvider>.value(value: widget.goalProvider),
        ChangeNotifierProvider<JobSearchConfigController>.value(
          value: widget.jobSearchConfig,
        ),
        ChangeNotifierProvider<McpConfigService>.value(
          value: widget.mcpConfigService,
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) {
          final l10n = context.watch<LocalizationProvider>();
          final settings = context.watch<SettingsProvider>();
          // 岗位搜索通道随设置重建（幂等，设置没变不做事）。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted)
              widget.jobSearchConfig.syncIfChanged(settings.settings);
          });
          // 设置加载完成后，再加载内容（使用当前领域）
          if (!settings.isLoading && !_contentLoaded) {
            _contentLoaded = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final progressProvider = context.read<ProgressProvider>();
              final settingsProvider = context.read<SettingsProvider>();
              final aiProvider = context.read<AiProvider>();
              final localizationProvider = context.read<LocalizationProvider>();
              final learningScopeProvider = context
                  .read<LearningScopeProvider>();
              widget.dataSyncService.onDataImported = () async {
                await progressProvider.loadProgress();
                await settingsProvider.loadSettings();
                await aiProvider.loadConfigs();
                localizationProvider.setLanguage(
                  settingsProvider.settings.language,
                );
                await learningScopeProvider.reload(
                  legacyDomainId: settingsProvider.settings.currentDomain,
                );
              };
              widget.dataSyncService.start();
              // 同步语言设置到 LocalizationProvider
              context.read<LocalizationProvider>().setLanguage(
                settings.settings.language,
              );
              // 加载学习范围（含旧键迁移）
              learningScopeProvider.load(
                legacyDomainId: settings.settings.currentDomain,
              );
            });
          }

          // 获取系统亮度
          final systemBrightness = MediaQuery.platformBrightnessOf(context);
          final systemIsDark = systemBrightness == Brightness.dark;

          // 构建主题
          final appTheme = buildTheme(
            theme.primaryColor,
            theme.accentColor,
            theme.themeType.key,
            fontScale: theme.fontScale,
            cardDensity: theme.cardDensity,
            systemIsDark: systemIsDark,
          );

          return MaterialApp.router(
            title: l10n.get('interview_intelligence_training'),
            debugShowCheckedModeBanner: false,
            locale: Locale(l10n.language),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L10n.supportedLocales,
            themeMode: settings.settings.themeMode,
            theme: appTheme,
            routerConfig: _router,
          );
        },
      ),
    );
  }
}

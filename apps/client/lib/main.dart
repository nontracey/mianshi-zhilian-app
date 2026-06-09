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
import 'pages/learning_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogService.instance.initialize();
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (!kReleaseMode) originalDebugPrint(message, wrapWidth: wrapWidth);
    final text = message;
    if (text != null && text.trim().isNotEmpty) {
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
  final updateService = UpdateService(routeClient: routeClient);
  final dataSyncService = DataSyncService(storage);
  final analyticsService = AnalyticsService(storage, routeClient: routeClient)
    ..start();
  final connectivityProvider = ConnectivityProvider()..start();

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
      themeProvider: ThemeProvider(),
      connectivityProvider: connectivityProvider,
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
  });

  @override
  State<MianshiZhilianApp> createState() => _MianshiZhilianAppState();
}

class _MianshiZhilianAppState extends State<MianshiZhilianApp> {
  bool _contentLoaded = false;
  late final GoRouter _router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const LearningShell(),
      ),
      GoRoute(
        path: '/topic',
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/recall',
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/mock-interview',
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/today-review',
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/weakness-training',
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/answer-versions',
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/follow-up-training',
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/high-frequency',
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/system-design',
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/practice/project-dig',
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/auth/login',
        builder: (_, state) =>
            state.extra as Widget? ?? const LoginPage(),
      ),
      GoRoute(
        path: '/auth/change-password',
        builder: (_, state) =>
            state.extra as Widget? ?? const ChangePasswordPage(),
      ),
      GoRoute(
        path: '/auth/submit-ticket',
        builder: (_, state) => state.extra as Widget,
      ),
      GoRoute(
        path: '/profile/ai-config',
        builder: (_, state) =>
            state.extra as Widget? ?? const AiConfigPage(),
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
        builder: (_, state) =>
            state.extra as Widget? ?? const SyncBackupPage(),
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
    ],
  );

  @override
  void dispose() {
    widget.dataSyncService.stop();
    widget.analyticsService.stop();
    widget.connectivityProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.connectivityProvider),
        ChangeNotifierProvider.value(value: widget.themeProvider),
        ChangeNotifierProvider(
          create: (_) =>
              SettingsProvider(widget.storage, widget.dataSyncService, widget.themeProvider)
                ..loadSettings(),
        ),
        ChangeNotifierProvider(
          create: (_) => ContentProvider(widget.contentApi, widget.storage),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              AiProvider(widget.aiService, widget.storage)..loadConfigs(),
        ),
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
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) {
          final l10n = context.watch<LocalizationProvider>();
          final settings = context.watch<SettingsProvider>();
          // 设置加载完成后，再加载内容（使用当前领域）
          if (!settings.isLoading && !_contentLoaded) {
            _contentLoaded = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final progressProvider = context.read<ProgressProvider>();
              final settingsProvider = context.read<SettingsProvider>();
              final aiProvider = context.read<AiProvider>();
              final localizationProvider = context.read<LocalizationProvider>();
              final learningScopeProvider = context.read<LearningScopeProvider>();
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
              // 加载内容
              final contentProvider = context.read<ContentProvider>();
              contentProvider.loadContent(
                currentDomainId: settings.settings.currentDomain,
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


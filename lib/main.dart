import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'screens/landing_screen.dart';
import 'screens/main_tab_screen.dart';
import 'screens/philosophy_intro_screen.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'services/analytics_service.dart';
import 'services/apple_calendar_sync_service.dart';
import 'services/auth_service.dart';
import 'services/coach_id_migration_service.dart';
import 'services/task_resistance_service.dart';
import 'services/notification_service.dart';
import 'services/ongoing_task_nudge_service.dart';
import 'services/tasks_sync_service.dart';
import 'services/widget_sync_service.dart';
import 'models/user_data.dart';
import 'theme/app_design_tokens.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('ko', null);
  await CoachIdMigrationService.migrateLegacyNyangHalbaeIds();
  await TaskResistanceService.purgeRemovedPreemptiveKeys();
  await NotificationService().init();

  runApp(const ProviderScope(child: NyangCoachApp()));
  unawaited(_runStartupBackgroundJobs());
}

Future<void> _runStartupBackgroundJobs() async {
  try {
    await NotificationService().syncDailyMorningCall();
  } catch (e, stackTrace) {
    debugPrint('Startup morning call sync failed: $e');
    debugPrintStack(stackTrace: stackTrace);
  }

  try {
    await NotificationService().disableNightCallReminders();
  } catch (e, stackTrace) {
    debugPrint('Startup night call cleanup failed: $e');
    debugPrintStack(stackTrace: stackTrace);
  }

  try {
    await NotificationService().syncCoreReminders();
  } catch (e, stackTrace) {
    debugPrint('Startup core reminder sync failed: $e');
    debugPrintStack(stackTrace: stackTrace);
  }

  try {
    await WidgetSyncService.syncFromStoredTasks();
  } catch (e, stackTrace) {
    debugPrint('Startup widget sync failed: $e');
    debugPrintStack(stackTrace: stackTrace);
  }

  try {
    await AppleCalendarSyncService.instance.syncAll();
  } catch (e, stackTrace) {
    debugPrint('Startup Apple calendar sync failed: $e');
    debugPrintStack(stackTrace: stackTrace);
  }

  try {
    await NotificationService().handleLaunchNotification();
  } catch (e, stackTrace) {
    debugPrint('Launch notification handling failed: $e');
    debugPrintStack(stackTrace: stackTrace);
  }

  try {
    await NotificationService().handleNativeMorningAlarm();
  } catch (e, stackTrace) {
    debugPrint('Native morning alarm handling failed: $e');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class NyangCoachApp extends StatefulWidget {
  const NyangCoachApp({super.key});

  @override
  State<NyangCoachApp> createState() => _NyangCoachAppState();
}

class _NyangCoachAppState extends State<NyangCoachApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService().recordAppActive();
    OngoingTaskNudgeService.setAppForeground(true);
    unawaited(OngoingTaskNudgeService.reconcile());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(NotificationService().requestNotificationPermissions());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationService().handleNativeMorningAlarm();
      NotificationService().recordAppActive();
      // 앱을 보고 있는 동안에는 냥냥이가 다른 앱 위로 나가지 않는다.
      OngoingTaskNudgeService.setAppForeground(true);
      // 플래너를 열지 않아도, 끝난 일정이 잠금화면에 남아 있는 일은 없어야 한다.
      OngoingTaskNudgeService.reconcile();
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      TasksSyncService.syncToCloud();
      NotificationService().syncDailyPlannerNudge();
      OngoingTaskNudgeService.setAppForeground(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '냥냥 코치',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppDesignTokens.brand,
          surface: AppDesignTokens.surface,
        ),
        scaffoldBackgroundColor: AppDesignTokens.surface,
        dividerColor: AppDesignTokens.divider,
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansKrTextTheme(Theme.of(context).textTheme)
            .apply(
              bodyColor: AppDesignTokens.textPrimary,
              displayColor: AppDesignTokens.textPrimary,
            ),
      ),
      navigatorKey: navigatorKey,
      // 화면 이동을 자동으로 기록해 콘솔에서 화면별 체류·이탈을 볼 수 있게 한다.
      navigatorObservers: [
        FirebaseAnalyticsObserver(analytics: AnalyticsService.analytics),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
      home: const StartupGateScreen(),
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => const LandingScreen(),
          settings: settings,
        );
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

class StartupGateScreen extends StatefulWidget {
  const StartupGateScreen({super.key});

  @override
  State<StartupGateScreen> createState() => _StartupGateScreenState();
}

class _StartupGateScreenState extends State<StartupGateScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_routeInitialScreen());
  }

  Future<void> _routeInitialScreen() async {
    Widget target = const LandingScreen();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final allowed = await AuthService().ensureCurrentUserAllowed();
        if (allowed) {
          await UserDataService.syncFromCloud().timeout(
            const Duration(seconds: 8),
            onTimeout: () {},
          );
          final data = await UserDataService.load();
          _enforceWidgetAccessInBackground(
            hasMasterPlan: data.isPlanActive && data.planType == 'master',
          );
          await _syncTasksBeforeNavigation();

          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          final widgetRoute = prefs.getString('widget_route');
          final widgetCoachId = prefs.getString('widget_coach_id');
          final widgetDate = prefs.getString('widget_date');
          final widgetItemId = prefs.getString('widget_item_id');

          if (widgetRoute != null) unawaited(prefs.remove('widget_route'));
          if (widgetCoachId != null) unawaited(prefs.remove('widget_coach_id'));
          if (widgetDate != null) unawaited(prefs.remove('widget_date'));
          if (widgetItemId != null) unawaited(prefs.remove('widget_item_id'));

          final hasWidgetIntent =
              widgetRoute != null ||
              widgetCoachId != null ||
              widgetDate != null ||
              widgetItemId != null;
          final targetCoachId = hasWidgetIntent
              ? 'cat'
              : data.selectedCoachId ?? 'cat';

          if (data.selectedCoachId != null) {
            if (!data.canAccessCoach(targetCoachId)) {
              await UserDataService.setSelectedCoach('cat');
              target = const PhilosophyIntroScreen();
            } else {
              if (hasWidgetIntent && data.selectedCoachId != 'cat') {
                await UserDataService.setSelectedCoach('cat');
              } else if (widgetCoachId != null &&
                  widgetCoachId != data.selectedCoachId) {
                await UserDataService.setSelectedCoach(widgetCoachId);
              }

              final isWidgetTasksRoute = isPlannerOverlayRoute(widgetRoute);
              final initBottomSheet = widgetRoute == 'tasks_done_bottom_sheet'
                  ? 'done'
                  : widgetRoute == 'tasks_remaining_bottom_sheet'
                  ? 'remaining'
                  : null;
              target = MainTabScreen(
                coachId: targetCoachId,
                initialBottomSheet: initBottomSheet,
                openTasksOverlayOnStart: isWidgetTasksRoute,
                initialPlannerTabIndex: plannerOverlayTabIndexForRoute(
                  widgetRoute,
                ),
                initialPlannerDateKey: widgetDate,
                initialPlannerItemId: widgetItemId,
              );
            }
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Startup routing failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    }

    if (!mounted) return;
    final nav = Navigator.of(context);
    final startupRoute = ModalRoute.of(context);
    final route = MaterialPageRoute(builder: (_) => target);
    if (startupRoute != null && startupRoute.isActive && nav.canPop()) {
      nav.replace(oldRoute: startupRoute, newRoute: route);
    } else {
      nav.pushReplacement(route);
    }
  }

  void _enforceWidgetAccessInBackground({required bool hasMasterPlan}) {
    unawaited(
      WidgetSyncService.enforcePlanAccess(
        hasMasterPlan: hasMasterPlan,
      ).catchError((Object e, StackTrace stackTrace) {
        debugPrint('Widget access sync failed: $e');
        debugPrintStack(stackTrace: stackTrace);
        return false;
      }),
    );
  }

  Future<void> _syncTasksBeforeNavigation() async {
    try {
      final diag = await TasksSyncService.syncFromCloudWithRetry();
      if (!_isTaskSyncUsable(diag)) {
        debugPrint('Startup task sync was not usable: ${diag['message']}');
      }
    } catch (e, stackTrace) {
      debugPrint('Startup task sync failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  bool _isTaskSyncUsable(Map<String, dynamic> diag) {
    if (diag['success'] == true) return true;
    if (diag['code'] == 'not_signed_in') return true;
    if (diag['code'] == 'cloud_empty_keep_local') return true;
    if (diag['code'] == 'cloud_stale_keep_local') return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: AppDesignTokens.surface);
  }
}

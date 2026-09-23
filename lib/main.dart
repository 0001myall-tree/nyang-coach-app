import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'theme/app_font.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
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
import 'services/purchase_service.dart';
import 'services/ongoing_task_nudge_service.dart';
import 'services/tasks_sync_service.dart';
import 'services/active_coaching_sync.dart';
import 'services/gap_coaching_service.dart';
import 'services/nyang_banner_nudge.dart';
import 'services/widget_sync_service.dart';
import 'models/user_data.dart';
import 'theme/app_design_tokens.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// 이 앱에서 온 요청인지 서버가 알아볼 수 있게 표를 붙인다.
///
/// 지금까지 서버가 보는 것은 로그인 토큰뿐이었다. 그것만으로는 진짜 앱에서
/// 왔는지, 흉내 낸 기기나 스크립트에서 왔는지 가릴 수가 없다. 계정은 돈으로
/// 대량으로 만들 수 있어도 진짜 기기는 한 대씩 사야 하므로, 계정을 세는 것보다
/// 기기를 보는 쪽이 막는 힘이 세다.
///
/// **켠다고 바로 막히지는 않는다.** 앱은 표를 붙이기만 하고, 그 표가 없는
/// 요청을 물리칠지는 Firebase 콘솔에서 따로 켠다. 그래서 먼저 이대로 며칠
/// 두고 무엇이 얼마나 걸리는지 본 다음에 적용해야 한다 — 바로 적용하면 심사
/// 중인 쪽이나 멀쩡한 사용자가 같이 막힐 수 있다.
///
/// 실패해도 앱은 그대로 뜬다. 표가 없으면 나중에 거절당할 뿐이고, 여기서
/// 멈추면 앱이 아예 안 열린다.
Future<void> _activateAppCheck() async {
  try {
    await FirebaseAppCheck.instance.activate(
      // 개발 중에는 디버그 표를 쓴다. 정식 표는 스토어에서 받은 설치본에만
      // 나오므로, 이게 없으면 손에서 돌리는 빌드가 전부 막힌다.
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
    );
  } catch (e) {
    debugPrint('App Check activate failed: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _activateAppCheck();
  await initializeDateFormatting('ko', null);
  await CoachIdMigrationService.migrateLegacyNyangHalbaeIds();
  await TaskResistanceService.purgeRemovedPreemptiveKeys();
  await NotificationService().init();
  // 결제 결과는 앱이 꺼져 있는 동안에도 도착한다. 켜자마자 듣고 있어야
  // 그때 들어온 구매를 확인 처리할 수 있고, 안 하면 사흘 뒤 자동 환불된다.
  await PurchaseService.instance.start();

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
    unawaited(
      OngoingTaskNudgeService.applyPendingAnswer().then(
        (_) => OngoingTaskNudgeService.reconcile(),
      ),
    );
    unawaited(NyangBannerNudge.sync());
    // 등급이 내려갔거나 폰을 새로 켰을 수 있다. 틈새 코칭 예약도 지금 상태로
    // 다시 맞춘다.
    unawaited(GapCoachingService.sync());
    unawaited(ActiveCoachingSync.sync());
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
      // 앱 밖에서 고른 답을 여기서 반영한다. 플래너를 열 필요가 없다.
      OngoingTaskNudgeService.applyPendingAnswer().then(
        (_) => OngoingTaskNudgeService.reconcile(),
      );
      unawaited(NotificationService().syncCoreReminders());
      // 배너에서 "시작할게"를 눌렀으면 저장소는 이미 바뀌어 있다. 다음 배너를
      // 다시 잡아둬야 그 일정에 계속 걸려 있지 않는다.
      unawaited(NyangBannerNudge.sync());
      unawaited(GapCoachingService.sync());
      unawaited(ActiveCoachingSync.sync());
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      TasksSyncService.syncToCloud();
      NotificationService().syncDailyPlannerNudge();
      OngoingTaskNudgeService.setAppForeground(false);
      // 앱을 보고 있는 동안에는 개입이 뜨지 않는다. 그 차례는 그냥 지나가므로,
      // 나가는 지금 다음 자리를 다시 잡아둔다. 안 그러면 앱을 다시 열기
      // 전까지 걸린 것이 하나도 없다.
      unawaited(ActiveCoachingSync.sync());
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
        fontFamily: kAppFontFamily,
        textTheme: Theme.of(context).textTheme.apply(
          fontFamily: kAppFontFamily,
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
    // 첫 프레임을 그린 뒤에 시작한다.
    //
    // 이 안에서 마지막에 ModalRoute를 찾는데, 로그인 전이라 앞의 기다림이 전부
    // 건너뛰어지면 initState가 끝나기도 전에 거기 닿는다. 그러면 화면을 넘기지
    // 못하고 흰 화면에 멈춘다 — 새로 설치하고 처음 켠 자리가 정확히 그렇다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_routeInitialScreen());
    });
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

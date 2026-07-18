import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'screens/landing_screen.dart';
import 'screens/coach_config.dart';
import 'services/notification_service.dart';
import 'services/tasks_sync_service.dart';
import 'services/widget_sync_service.dart';
import 'theme/app_design_tokens.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('ko', null);
  await NotificationService().init();

  final prefs = await SharedPreferences.getInstance();
  final _secMaleName = prefs.getString('nyang_coach_name_sec_male');
  final _secFemaleName = prefs.getString('nyang_coach_name_sec_female');
  CoachConfigs.customSecMaleName =
      (_secMaleName != null && _secMaleName.isNotEmpty) ? _secMaleName : null;
  CoachConfigs.customSecFemaleName =
      (_secFemaleName != null && _secFemaleName.isNotEmpty)
      ? _secFemaleName
      : null;

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
    await NotificationService().syncDailyNightCall();
  } catch (e, stackTrace) {
    debugPrint('Startup night call sync failed: $e');
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
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      TasksSyncService.syncToCloud();
      NotificationService().scheduleInactiveReturnReminder();
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
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
      home: const LandingScreen(),
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

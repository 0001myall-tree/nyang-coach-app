import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'screens/landing_screen.dart';
import 'services/notification_service.dart';
import 'services/tasks_sync_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('ko', null);
  await NotificationService().init();
  await NotificationService().syncDailyNightCall();
  runApp(const ProviderScope(child: NyangCoachApp()));
  await NotificationService().handleLaunchNotification();
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      TasksSyncService.syncToCloud();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '냥냥 코치',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B7CCC),
          surface: Colors.white,
          background: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansKrTextTheme(Theme.of(context).textTheme),
      ),
      navigatorKey: navigatorKey,
      home: const LandingScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

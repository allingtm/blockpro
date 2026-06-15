import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'database/database.dart';
import 'providers/auth_provider.dart';
import 'providers/database_provider.dart';
import 'providers/outbox_drain_provider.dart';
import 'providers/outbox_provider.dart';
import 'providers/theme_provider.dart';
import 'utils/draft_photo_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await dotenv.load(fileName: '.env');

  // Initialize database
  final database = AppDatabase();

  // Initialize auth — loads persisted token from SharedPreferences
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
    ],
  );
  final authRepo = container.read(authRepositoryProvider);
  // On sign-out, purge the offline outbox (queued completions + their photos)
  // and draft photos BEFORE wiping the DB cache, so a different user logging in
  // next can never inherit them. Awaited via auth_repository so it completes
  // before the next login.
  authRepo.onSignOut = () async {
    await container.read(outboxStoreProvider).clearAll();
    await const DraftPhotoStore().deleteAllPhotos();
    await database.clearAllData();
  };
  await authRepo.initialize();

  // Send anything queued from a previous (offline) session. Bails internally if
  // still offline; recovers any entry left mid-send by a crash.
  unawaited(container.read(outboxDrainerProvider).drain());

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MainApp(),
    ),
  );
}

class MainApp extends ConsumerStatefulWidget {
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp>
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
    // Returning to the foreground is a good moment to flush the outbox — the
    // user may have regained connectivity while the app was backgrounded.
    if (state == AppLifecycleState.resumed) {
      ref.read(outboxDrainerProvider).drain();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the offline → online drain trigger alive for the whole session.
    ref.watch(outboxDrainTriggerProvider);

    final router = ref.watch(goRouterProvider);
    final lightTheme = ref.watch(lightThemeProvider);
    final darkTheme = ref.watch(darkThemeProvider);
    final themeMode = ref.watch(brightnessModeProvider);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(context).clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.3,
        ),
      ),
      child: MaterialApp.router(
        title: 'BlockPro',
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        themeAnimationDuration: const Duration(milliseconds: 300),
        themeAnimationCurve: Curves.easeInOut,
        routerConfig: router,
        builder: (context, child) => GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: child,
        ),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

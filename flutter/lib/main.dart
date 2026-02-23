import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await dotenv.load(fileName: '.env');

  // Initialize auth — loads persisted token from SharedPreferences
  final container = ProviderContainer();
  await container.read(authRepositoryProvider).initialize();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MainApp(),
    ),
  );
}

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

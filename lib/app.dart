import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/alice_debug_layer.dart';
import 'core/app_config.dart';
import 'screens/auth/app_lock_screen.dart';
import 'services/app_lock.dart';
import 'services/unread_service.dart';
import 'core/app_theme.dart';
import 'core/navigation/app_router.dart';
import 'widgets/nx_atmosphere.dart';

class NextXMobileApp extends StatefulWidget {
  const NextXMobileApp({super.key});

  @override
  State<NextXMobileApp> createState() => _NextXMobileAppState();
}

class _NextXMobileAppState extends State<NextXMobileApp> with WidgetsBindingObserver {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createAppRouter(context.read<AppConfig>());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) AppLock.instance.onPaused();
    if (state == AppLifecycleState.resumed) {
      AppLock.instance.onResumed(loggedIn: context.read<AppConfig>().isLoggedIn);
      context.read<AppConfig>().flushOfflineQueue();
      UnreadNotifications.instance.refreshIfBound();
      context.read<AppConfig>().refreshSessionIfStale();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppConfig>(
      builder: (_, config, _) {
        final accent = config.accentColor;
        return MaterialApp.router(
          title: 'MOAI NEXT',
          debugShowCheckedModeBanner: false,
          locale: config.uiLocaleCode == 'en' ? const Locale('en', 'US') : const Locale('th', 'TH'),
          supportedLocales: const [Locale('th', 'TH'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.themed(brightness: Brightness.light, accent: accent),
          darkTheme: AppTheme.themed(brightness: Brightness.dark, accent: accent),
          themeMode: config.themeMode,
          builder: (context, child) => NxAtmosphere(
            child: AliceDebugLayer(
              child: ListenableBuilder(
                listenable: AppLock.instance,
                builder: (context, _) => Stack(
                  children: [
                    ?child,
                    if (AppLock.instance.locked && config.isLoggedIn) const Positioned.fill(child: AppLockScreen()),
                  ],
                ),
              ),
            ),
          ),
          routerConfig: _router,
        );
      },
    );
  }
}

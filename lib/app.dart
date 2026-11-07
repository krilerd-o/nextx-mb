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

class _NextXMobileAppState extends State<NextXMobileApp>
    with WidgetsBindingObserver {
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
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden)
      AppLock.instance.onPaused();
    if (state == AppLifecycleState.resumed) {
      AppLock.instance.onResumed(
        loggedIn: context.read<AppConfig>().isLoggedIn,
      );
      context.read<AppConfig>().flushOfflineQueue();
      UnreadNotifications.instance.refreshIfBound();
      context.read<AppConfig>().refreshSessionIfStale();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the app shell only when what it shows changes — not on every
    // AppConfig notify (session refresh on resume, offline queue, …).
    return Selector<AppConfig, (Color, ThemeMode, String, bool)>(
      selector: (_, c) =>
          (c.accentColor, c.themeMode, c.uiLocaleCode, c.isLoggedIn),
      builder: (context, sel, _) {
        final accent = sel.$1;
        return MaterialApp.router(
          title: 'MOAI NEXT',
          debugShowCheckedModeBanner: false,
          locale: sel.$3 == 'en'
              ? const Locale('en', 'US')
              : const Locale('th', 'TH'),
          supportedLocales: const [Locale('th', 'TH'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.themed(brightness: Brightness.light, accent: accent),
          darkTheme: AppTheme.themed(
            brightness: Brightness.dark,
            accent: accent,
          ),
          themeMode: sel.$2,
          builder: (context, child) => BackdropGroup(
            child: NxAtmosphere(
              child: AliceDebugLayer(
                child: ListenableBuilder(
                  listenable: AppLock.instance,
                  builder: (context, _) => Stack(
                    children: [
                      ?child,
                      if (AppLock.instance.locked && sel.$4)
                        const Positioned.fill(child: AppLockScreen()),
                    ],
                  ),
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

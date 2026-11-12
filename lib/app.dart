import 'package:flutter/material.dart';

import 'widgets/nx_keyboard_follow.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/alice_debug_layer.dart';
import 'core/app_config.dart';
import 'screens/auth/app_lock_screen.dart';
import 'screens/calls/call_overlay.dart';
import 'screens/calls/live_captions.dart';
import 'services/app_lock.dart';
import 'services/calls/call_service.dart';
import 'services/calls/live_transcription.dart';
import 'services/unread_service.dart';
import 'core/app_theme.dart';
import 'core/navigation/app_router.dart';
import 'widgets/nx_upload_pill.dart';
import 'core/nx_network.dart';
import 'services/photo_upload_center.dart';
import 'widgets/nx_atmosphere.dart';
import 'widgets/nx_language_switch.dart';
import 'widgets/nx_ui_scale.dart';
import 'core/i18n.dart';

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
    // Back online → resend saved photos / punches.
    NxNetwork.instance.ensureStarted();
    NxNetwork.instance.online.addListener(_onNetwork);
  }

  void _onNetwork() {
    if (!mounted) return;
    final online = NxNetwork.instance.online.value;
    PhotoUploadCenter.instance.offline = !online;
    if (online) context.read<AppConfig>().flushOfflineQueue();
  }

  @override
  void dispose() {
    NxNetwork.instance.online.removeListener(_onNetwork);
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
    return Selector<AppConfig, (Color, ThemeMode, String, bool, String, double)>(
      selector: (_, c) => (
        c.accentColor,
        c.themeMode,
        c.uiLocaleCode,
        c.isLoggedIn,
        c.uiFontFamily,
        c.uiScale,
      ),
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
          theme: AppTheme.themed(
            brightness: Brightness.light,
            accent: accent,
            family: sel.$5,
          ),
          darkTheme: AppTheme.themed(
            brightness: Brightness.dark,
            accent: accent,
            family: sel.$5,
          ),
          themeMode: sel.$2,
          // Theme/colour changes cross-fade instead of snapping.
          themeAnimationDuration: const Duration(milliseconds: 420),
          themeAnimationCurve: Curves.easeInOutCubic,
          builder: (context, child) => NxUiScale(
            scale: sel.$6,
            child: BackdropGroup(
            child: NxKeyboardFollow(
            child: NxAtmosphere(
              child: NxLanguageSwitchLayer(
                child: AliceDebugLayer(
                  child: ListenableBuilder(
                    listenable: AppLock.instance,
                    builder: (context, _) => Stack(
                      children: [
                        ?child,
                        // Incoming / ongoing call above every screen.
                        // Photo uploads (sending / waiting for signal / failed) on every screen.
                        if (sel.$4) NxUploadPill(navigatorKey: _router.routerDelegate.navigatorKey),
                        if (sel.$4 && CallService.instance != null) Positioned.fill(child: CallOverlay(service: CallService.instance!)),
                        // "สรุปการสนทนาพร้อมแล้ว" after a call with AI notes.
                        if (sel.$4 && CallService.instance != null) CallSummaryToast(lt: LiveTranscription.instance, navigatorKey: _router.routerDelegate.navigatorKey),
                        if (AppLock.instance.locked && sel.$4)
                          const Positioned.fill(child: AppLockScreen()),
                        if (!sel.$4) const _AddSpaceCancelPill(),
                      ],
                    ),
                  ),
                ),
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

/// While signing in to an extra Space: a way back to the Space you came from.
class _AddSpaceCancelPill extends StatelessWidget {
  const _AddSpaceCancelPill();

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    if (!config.addingSpace) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      // Above the sign-in screens' full-width bottom button (~56 px + margins).
      bottom: MediaQuery.paddingOf(context).bottom + 92,
      child: Center(
        child: Material(
          color: Theme.of(context).colorScheme.inverseSurface,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => config.cancelAddSpace(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Text(
                tr('ยกเลิกการเพิ่ม Space'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onInverseSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

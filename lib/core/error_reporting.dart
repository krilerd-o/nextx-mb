import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where uncaught errors go. Defaults to the debug console; plug in Crashlytics /
/// Sentry here once their native config is in the project (see PUSH_AND_RELEASE.md).
typedef ErrorSink = void Function(Object error, StackTrace? stack, {bool fatal});

class ErrorReporting {
  ErrorReporting._();

  static const _prefsKey = 'error_log_v1';
  static const _max = 30;

  static ErrorSink sink = _debugSink;

  /// Recent errors (oldest first), kept on device so a crash survives a restart.
  /// Shown in Settings → บันทึกปัญหา for testers to send to the team.
  static final List<String> recent = [];

  static void _debugSink(Object error, StackTrace? stack, {bool fatal = false}) {
    debugPrint('[error${fatal ? ':fatal' : ''}] $error');
    if (stack != null) debugPrint('$stack');
  }

  /// One log line: time, kind, message and the first app frames of the stack.
  @visibleForTesting
  static String formatEntry(Object error, StackTrace? stack, {bool fatal = false, DateTime? at}) {
    final frames = (stack?.toString() ?? '')
        .split('\n')
        .where((l) => l.contains('package:nextx_mobile'))
        .take(3)
        .map((l) => l.trim())
        .join(' | ');
    final msg = error.toString().replaceAll('\n', ' ');
    final clipped = msg.length > 400 ? '${msg.substring(0, 400)}…' : msg;
    return '${(at ?? DateTime.now()).toIso8601String()} ${fatal ? 'FATAL' : 'ERROR'} $clipped${frames.isEmpty ? '' : '  @ $frames'}';
  }

  static void report(Object error, StackTrace? stack, {bool fatal = false}) {
    recent.add(formatEntry(error, stack, fatal: fatal));
    while (recent.length > _max) {
      recent.removeAt(0);
    }
    _persist();
    try {
      sink(error, stack, fatal: fatal);
    } catch (_) {}
  }

  static void _persist() {
    SharedPreferences.getInstance().then((p) => p.setStringList(_prefsKey, List.of(recent))).catchError((Object _) => false);
  }

  /// Restores the log saved by a previous run.
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getStringList(_prefsKey) ?? const [];
      recent
        ..clear()
        ..addAll(saved.length > _max ? saved.sublist(saved.length - _max) : saved);
    } catch (_) {}
  }

  static Future<void> clear() async {
    recent.clear();
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_prefsKey);
    } catch (_) {}
  }

  /// Installs Flutter / platform / zone error handlers, then runs [body].
  static void runGuarded(FutureOr<void> Function() body) {
    runZonedGuarded(() async {
      WidgetsFlutterBinding.ensureInitialized();
      await load();
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        report(details.exception, details.stack, fatal: false);
        previous?.call(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        report(error, stack, fatal: true);
        return true;
      };
      await body();
    }, (error, stack) => report(error, stack, fatal: true));
  }
}

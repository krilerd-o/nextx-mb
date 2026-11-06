import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Where uncaught errors go. Defaults to the debug console; plug in Crashlytics /
/// Sentry here once their native config is in the project (see PUSH_AND_RELEASE.md).
typedef ErrorSink = void Function(Object error, StackTrace? stack, {bool fatal});

class ErrorReporting {
  ErrorReporting._();

  static ErrorSink sink = _debugSink;

  /// Last few errors, shown in Settings → about for support.
  static final List<String> recent = [];

  static void _debugSink(Object error, StackTrace? stack, {bool fatal = false}) {
    debugPrint('[error${fatal ? ':fatal' : ''}] $error');
    if (stack != null) debugPrint('$stack');
  }

  static void report(Object error, StackTrace? stack, {bool fatal = false}) {
    recent.add('${DateTime.now().toIso8601String()} $error');
    if (recent.length > 20) recent.removeAt(0);
    try {
      sink(error, stack, fatal: fatal);
    } catch (_) {}
  }

  /// Installs Flutter / platform / zone error handlers, then runs [body].
  static void runGuarded(FutureOr<void> Function() body) {
    runZonedGuarded(() async {
      WidgetsFlutterBinding.ensureInitialized();
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

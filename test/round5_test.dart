import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/error_reporting.dart';

void main() {
  test('error log entry keeps time, kind, message and app frames', () {
    final stack = StackTrace.fromString('#0 foo (package:nextx_mobile/a.dart:1)\n#1 bar (dart:async)\n#2 baz (package:nextx_mobile/b.dart:2)');
    final e = ErrorReporting.formatEntry(StateError('boom'), stack, fatal: true, at: DateTime(2026, 11, 6, 9));
    expect(e, startsWith('2026-11-06T09:00:00.000 FATAL Bad state: boom'));
    expect(e, contains('package:nextx_mobile/a.dart'));
    expect(e, isNot(contains('dart:async')));
    final long = ErrorReporting.formatEntry('x' * 1000, null);
    expect(long.length, lessThan(460));
  });
}

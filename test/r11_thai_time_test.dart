import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/thai_time.dart';

void main() {
  test('UTC / offset times show as Thailand time (UTC+7)', () {
    final a = parseThai('2026-11-07T02:00:00Z')!;
    expect([a.day, a.hour, a.minute], [7, 9, 0]);
    final b = parseThai('2026-11-07T23:30:00.000Z')!;
    expect([b.day, b.hour, b.minute], [8, 6, 30]);
    final c = parseThai('2026-11-07T10:00:00+09:00')!;
    expect(c.hour, 8);
  });

  test('zone-less NEXTX times are already Thai wall time', () {
    final d = parseThai('2026-11-07 14:05:00')!;
    expect([d.hour, d.minute], [14, 5]);
    expect(parseThai(''), isNull);
    expect(parseThai('x'), isNull);
  });

  test('thaiNow equals UTC now + 7h', () {
    final n = thaiNow();
    final u = DateTime.now().toUtc().add(const Duration(hours: 7));
    expect(n.hour, u.hour);
    expect(n.day, u.day);
  });
}

// Home greeting / date follow Thai time whatever zone the phone is set to.
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/screens/dashboard/mobile_dashboard_screen.dart' show greetingFor, thaiShortDate;

void main() {
  test('UTC 23:30 → 06:30 next day in Bangkok: morning, next day date', () {
    final t = toThai(DateTime.utc(2026, 11, 18, 23, 30));
    expect([t.day, t.hour, t.minute], [19, 6, 30]);
    expect(greetingFor(t), 'สวัสดีตอนเช้า');
    expect(thaiShortDate(t), contains('19'));
  });

  test('11:59 → 12:00 Bangkok switches to afternoon; 17:00 evening', () {
    expect(greetingFor(toThai(DateTime.utc(2026, 11, 19, 4, 59))), 'สวัสดีตอนเช้า');
    expect(greetingFor(toThai(DateTime.utc(2026, 11, 19, 5, 0))), 'สวัสดีตอนบ่าย');
    expect(greetingFor(toThai(DateTime.utc(2026, 11, 19, 10, 0))), 'สวัสดีตอนเย็น');
  });
}

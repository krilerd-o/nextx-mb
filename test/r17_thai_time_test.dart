import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/screens/calendar/cal/cal_model.dart';

void main() {
  group('NEXTX date contract (same rule as the web)', () {
    test('wall-clock fields keep their digits despite the fake Z', () {
      expect(isWallClockField('date_start'), isTrue);
      expect(isWallClockField('date_end'), isTrue);
      expect(isWallClockField('plan_datetime'), isTrue);
      expect(isWallClockField('created_at'), isFalse);
      expect(isWallClockField('created_at', module: 'case'), isTrue);
      expect(isWallClockField('checkindate'), isFalse);

      // Activity saved at 14:00 Thai comes back as …T14:00:00.000Z: still 14:00.
      final w = parseThaiField('2026-11-07T14:00:00.000Z', 'date_start')!;
      expect((w.hour, w.minute, w.day), (14, 0, 7));
      // A real instant (check-in at 02:54 UTC) is 09:54 in Thailand.
      final t = parseThaiField('2026-11-07T02:54:51.000Z', 'checkindate')!;
      expect((t.hour, t.minute), (9, 54));
    });

    test('naive and date-only strings', () {
      expect(parseWall('2026-11-20 10:00:00'), DateTime(2026, 11, 20, 10));
      expect(parseWall('2026-11-20'), DateTime(2026, 11, 20));
      expect(parseWall('garbage'), isNull);
    });

    test('DATE columns from a Bangkok-TZ server show the right day', () {
      // 10 Nov at local midnight serialised by node-pg in Asia/Bangkok.
      expect(thaiDate('2026-11-09T17:00:00.000Z'), '10/11/2026');
      expect(thaiDate('2026-11-10'), '10/11/2026');
      expect(thaiDate('2026-11-10', year: (y) => y + 543), '10/11/2569');
      expect(parseThaiDate('2026-11-30T17:00:00.000Z'), DateTime(2026, 12, 1));
    });

    test('field display never shows raw ISO / UTC', () {
      expect(formatThaiField('2026-11-07T14:00:00.000Z', 'date_start'), '07/11/2026 14:00');
      expect(formatThaiField('2026-11-07T02:36:44.245Z', 'createdtime'), '07/11/2026 09:36');
      expect(formatThaiField('2026-11-07', 'closingdate'), '07/11/2026');
    });
  });

  group('calendar model', () {
    test('activity times are wall clock; all-day spans the day', () {
      final e = CalEvent.from({'id': 1, 'subject': '[QA] นัด', 'date_start': '2026-11-07T14:00:00.000Z', 'date_end': '2026-11-07T15:30:00.000Z'})!;
      expect(e.start, DateTime(2026, 11, 7, 14));
      expect(e.end, DateTime(2026, 11, 7, 15, 30));
      expect(e.on(DateTime(2026, 11, 7)), isTrue);
      expect(e.on(DateTime(2026, 11, 8)), isFalse);
      final a = CalEvent.from({'id': 2, 'subject': 'x', 'date_start': '2026-11-07', 'all_day': true})!;
      expect(a.allDay, isTrue);
      expect(a.end, DateTime(2026, 11, 8));
    });

    test('overlapping events sit side by side', () {
      CalEvent ev(int id, int h, int dur) => CalEvent.from({
            'id': id,
            'subject': '$id',
            'date_start': '2026-11-07 ${h.toString().padLeft(2, '0')}:00:00',
            'date_end': '2026-11-07 ${(h + dur).toString().padLeft(2, '0')}:00:00',
          })!;
      final a = ev(1, 9, 2), b = ev(2, 10, 1), c = ev(3, 13, 1);
      final l = layoutOverlaps([a, b, c]);
      expect(l[a], (0, 2));
      expect(l[b], (1, 2));
      expect(l[c], (0, 1));
    });

    test('Sunday-first weeks, quarters, Thai labels', () {
      expect(weekStart(DateTime(2026, 11, 11)), DateTime(2026, 11, 8));
      expect(quarterStart(DateTime(2026, 11, 11)), DateTime(2026, 10, 1));
      expect(ymdhm(DateTime(2026, 11, 20, 9, 5)), '2026-11-20 09:05:00');
    });
  });
}

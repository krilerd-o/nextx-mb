import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/widgets/nx_status_stepper.dart';
import 'package:nextx_mobile/widgets/nx_timeline.dart';

void main() {
  testWidgets('timeline: date badge once per day, year marker, avatar, time chip', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: NxTimeline(now: DateTime(2026, 11, 9), entries: [
            NxTimelineEntry(at: DateTime(2026, 11, 9, 14, 5), icon: Icons.edit, title: const Text('[QA] แก้ไขสถานะ'), who: 'QA Tester'),
            NxTimelineEntry(at: DateTime(2026, 11, 9, 9, 30), icon: Icons.add, title: const Text('[QA] สร้างรายการ'), body: const Text('รายละเอียด')),
            NxTimelineEntry(at: DateTime(2025, 12, 31, 8, 0), icon: Icons.add, title: const Text('[QA] ปีก่อน')),
          ]),
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('timeline-0')), findsOneWidget);
    expect(find.text('09'), findsOneWidget); // one badge for both entries of 9 Nov
    expect(find.text('พ.ย.'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    expect(find.text('14:05'), findsOneWidget);
    expect(find.text('09:30'), findsOneWidget);
    expect(find.textContaining('2568'), findsOneWidget); // year marker (Buddhist year) for 2025
    expect(tester.takeException(), isNull);
  });

  test('status pills are compact', () {
    expect(NxStatusStepper.pillHeight, lessThanOrEqualTo(32));
  });
}

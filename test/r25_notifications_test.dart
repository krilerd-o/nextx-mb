import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/widgets/nx_notification_view.dart';

void main() {
  test('**bold** markers render bold, never as asterisks', () {
    final spans = boldSpans('งาน **NEXTT-16** เลยกำหนด **38 วัน**');
    final text = spans.map((s) => (s as TextSpan).text).join();
    expect(text, 'งาน NEXTT-16 เลยกำหนด 38 วัน');
    final bold = spans.whereType<TextSpan>().where((s) => s.style?.fontWeight == FontWeight.w800).map((s) => s.text);
    expect(bold, ['NEXTT-16', '38 วัน']);
    expect(plainNotif('**A** b'), 'A b');
  });

  test('categories follow the web rules (meta.module first)', () {
    expect(notifCategory({'type': 'calendar', 'link_path': '/workspace/X-1', 'meta': {'module': 'work'}}), 'work');
    expect(notifCategory({'type': 'calendar', 'link_path': '/workspace/X-1'}), 'work');
    expect(notifCategory({'type': 'chat'}), 'chat');
    expect(notifCategory({'link_path': '/modules/case/5'}), 'case');
    expect(notifCategory({'meta': {'module': 'system'}}), 'other');
  });

  test('read state: read_at or is_read', () {
    expect(notifUnread({'read_at': null}), isTrue);
    expect(notifUnread({'read_at': '2026-11-08'}), isFalse);
    expect(notifUnread({'is_read': true}), isFalse);
  });

  testWidgets('daily digest lists each task; tapping one opens that task', (tester) async {
    String? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NxNotifTile(
          item: {
            'title': 'งานค้าง **2 งาน**',
            'body': '• ...',
            'meta': {
              'module': 'work',
              'event': 'WD1',
              'items': [
                {'board': 'NEXTT', 'code': 'NEXTT-16', 'title': '[QA] เก่าสุด', 'link_path': '/workspace/NEXTT-16', 'days': 38},
                {'board': 'MKTT', 'code': 'MKTT-5', 'title': '[QA] งาน', 'link_path': '/workspace/MKTT-5', 'days': 1},
              ],
            },
          },
          onOpen: () {},
          onOpenLink: (p) => opened = p,
        ),
      ),
    ));
    expect(find.textContaining('งานค้าง'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    expect(find.text('NEXTT-16 [QA] เก่าสุด'), findsOneWidget);
    expect(find.text('เลย 38 วัน'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('digest-MKTT-5')));
    expect(opened, '/workspace/MKTT-5');
  });

  test('day headings', () {
    final now = DateTime(2026, 11, 8, 12);
    expect(notifDayBucket('2026-11-08T08:00:00+07:00', now: now), 'วันนี้');
    expect(notifDayBucket('2026-11-07T20:00:00+07:00', now: now), 'เมื่อวาน');
    expect(notifDayBucket('2026-11-01T20:00:00+07:00', now: now), 'ก่อนหน้า');
  });
}

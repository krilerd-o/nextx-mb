import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/i18n.dart';
import 'package:nextx_mobile/core/i18n_en.dart';

void main() {
  tearDown(() => L10n.set('th'));

  test('Thai is the default and passes through', () {
    L10n.set('th');
    expect(tr('บันทึก'), 'บันทึก');
    expect(uiYear(2026), 2569);
  });

  test('English: exact strings, templates with translated holes, years', () {
    L10n.set('en');
    expect(tr('บันทึก'), 'Save');
    expect(tr('ลบ ลูกค้า แล้ว'), isNot(contains('แล้ว')));
    expect(tr('ยืนยันเช็คอิน'), 'Confirm Check-in'.replaceAll('Check-in', tr('เช็คอิน')));
    expect(tr('3 นาทีที่แล้ว'), '3 min ago');
    expect(tr('Hello world'), 'Hello world');
    expect(uiYear(2026), 2026);
  });

  test('every template key has the same number of holes in English', () {
    for (final e in enPatterns.entries) {
      expect('{}'.allMatches(e.value).length, '{}'.allMatches(e.key).length, reason: e.key);
    }
  });

  testWidgets('switching rebuilds const widgets in place', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Label()));
    expect(find.text('ยกเลิก'), findsOneWidget);
    L10n.set('en');
    rebuildAllChildren(tester.element(find.byType(MaterialApp)));
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);
  });
}

class _Label extends StatelessWidget {
  const _Label();
  @override
  Widget build(BuildContext context) => Text(tr('ยกเลิก'));
}

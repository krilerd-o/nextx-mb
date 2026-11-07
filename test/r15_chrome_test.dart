import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/widgets/nx_app_header.dart';
import 'package:nextx_mobile/widgets/nx_list_toolbar.dart';
import 'package:nextx_mobile/widgets/nx_scroll_scaffold.dart';

void main() {
  setUp(NxChromeBus.reset);

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    var q = const NxListQuery();
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => NxScrollScaffold(
          header: const NxAppHeader(title: '[QA] รายการ'),
          body: Column(
            children: [
              NxListToolbar(
                query: q,
                onChanged: (v) => setState(() => q = v),
                searchHint: 'ค้นหาทดสอบ',
                groups: const [
                  NxFilterGroup(key: 's', label: 'สถานะ', options: [NxFilterOption('a', 'A'), NxFilterOption('b', 'B')]),
                ],
                sorts: const [NxSortOption('new', 'ใหม่สุด'), NxSortOption('old', 'เก่าสุด')],
              ),
              Expanded(
                child: ListView(
                  children: [for (var i = 0; i < 60; i++) SizedBox(height: 60, child: Text('[QA] แถว $i'))],
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Finder searchField() => find.widgetWithText(TextField, 'ค้นหาทดสอบ');

  testWidgets('scrolling down folds the toolbar into header icons and hides the tab bar', (tester) async {
    await pumpPage(tester);
    expect(find.byTooltip('ค้นหา'), findsNothing);
    expect(tester.getSize(find.byType(NxListToolbar)).height, greaterThan(60));

    await tester.drag(find.text('[QA] แถว 3'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(NxChromeBus.hidden.value, isTrue);
    expect(tester.getSize(find.byType(NxListToolbar)).height, lessThan(1));
    expect(find.byTooltip('ค้นหา'), findsOneWidget);
    expect(find.byTooltip('ตัวกรอง'), findsOneWidget);

    // A small scroll back brings everything back.
    await tester.drag(find.byType(ListView), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(NxChromeBus.hidden.value, isFalse);
    expect(find.byTooltip('ค้นหา'), findsNothing);
    expect(tester.getSize(find.byType(NxListToolbar)).height, greaterThan(60));
  });

  testWidgets('header search icon reopens the toolbar and focuses search', (tester) async {
    await pumpPage(tester);
    await tester.drag(find.text('[QA] แถว 3'), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ค้นหา'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(NxListToolbar)).height, greaterThan(60));
    final field = tester.widget<TextField>(searchField());
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('header filter icon opens one sheet with sort and filters, badge counts them', (tester) async {
    await pumpPage(tester);
    await tester.drag(find.text('[QA] แถว 3'), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ตัวกรอง'));
    await tester.pumpAndSettle();
    expect(find.text('เรียงตาม'), findsOneWidget);
    expect(find.text('สถานะ'), findsOneWidget);
    await tester.tap(find.text('เก่าสุด'));
    await tester.tap(find.text('A'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'ใช้ตัวกรอง (1)'));
    await tester.pumpAndSettle();
    // Filter applied; the folded funnel shows 2 (1 filter + non-default sort).
    expect(find.text('2'), findsOneWidget);
  });
}

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

  testWidgets('search / filter are header icons by default; status chips stay under the header', (tester) async {
    await pumpPage(tester);
    expect(find.byTooltip('ค้นหา'), findsOneWidget);
    expect(find.byTooltip('ตัวกรอง'), findsOneWidget);
    expect(searchField(), findsNothing);
    expect(find.text('A'), findsNothing, reason: 'no quick group: chips row is empty');

    await tester.drag(find.text('[QA] แถว 3'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(NxChromeBus.hidden.value, isTrue);
    expect(find.byTooltip('ค้นหา'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(NxChromeBus.hidden.value, isFalse);
  });

  testWidgets('header search icon opens the box ready to type; X closes it', (tester) async {
    await pumpPage(tester);
    await tester.drag(find.text('[QA] แถว 3'), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ค้นหา'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(searchField());
    expect(field.focusNode?.hasFocus, isTrue);
    await tester.tap(find.byTooltip('ปิดค้นหา'));
    await tester.pumpAndSettle();
    expect(searchField(), findsNothing);
  });

  testWidgets('search box keeps the keyboard up after opening (no reopen/close flicker)', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byTooltip('ค้นหา'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final first = tester.state<EditableTextState>(find.byType(EditableText));
    await tester.pumpAndSettle();
    // Same field (not rebuilt), still focused, keyboard still shown.
    expect(tester.state<EditableTextState>(find.byType(EditableText)), same(first));
    expect(tester.widget<TextField>(searchField()).focusNode?.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('typing searches 2.5 s later by itself; keyboard Search runs at once', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byTooltip('ค้นหา'));
    await tester.pumpAndSettle();
    await tester.enterText(searchField(), '[QA] ลูกค้า');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('nx-search-countdown')), findsOneWidget);
    expect(find.text('[QA] แถว 3'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump();
    expect(find.byKey(const ValueKey('nx-search-countdown')), findsNothing);
    expect(tester.widget<TextField>(searchField()).focusNode?.hasFocus, isTrue, reason: 'keep typing after an auto search');
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

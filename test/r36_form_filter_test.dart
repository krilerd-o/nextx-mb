import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/screens/crm/entity_create_screen.dart';
import 'package:nextx_mobile/widgets/nx_app_header.dart';
import 'package:nextx_mobile/widgets/nx_list_toolbar.dart';
import 'package:nextx_mobile/widgets/nx_scroll_scaffold.dart';

const _fields = <Map<String, dynamic>>[
  {'name': 'firstname', 'label_th': 'ชื่อ', 'uitype': 'Text', 'required': true, 'sequence': 1},
  {'name': 'lastname', 'label_th': 'นามสกุล', 'uitype': 'Text', 'sequence': 2},
  {'name': 'email', 'label_th': 'อีเมล', 'uitype': 'Email', 'sequence': 3},
  {'name': 'phone', 'label_th': 'โทรศัพท์', 'uitype': 'Phone', 'required': true, 'sequence': 4},
  {'name': 'city', 'label_th': 'เมือง', 'uitype': 'Text', 'sequence': 5},
  {'name': 'smownerid', 'label_th': 'ผู้รับผิดชอบ', 'uitype': 'Text', 'sequence': 6},
];

Future<void> _pumpForm(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider(
    create: (_) => AppConfig(),
    child: MaterialApp(
      theme: AppTheme.light,
      home: const EntityCreateScreen(module: 'lead', title: '[QA] สร้างลีด', fields: _fields),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('form: "required only" shows just the required fields', (tester) async {
    await _pumpForm(tester);
    expect(find.text('นามสกุล'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('form-required-only')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ชื่อ', findRichText: true), findsWidgets);
    expect(find.text('นามสกุล'), findsNothing);
    expect(find.text('เมือง'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('form-required-only')));
    await tester.pumpAndSettle();
    expect(find.text('นามสกุล'), findsOneWidget);
    await tester.pump(const Duration(minutes: 2));
  });

  testWidgets('form: section chips + folding; save opens a folded section with a missing field', (tester) async {
    await _pumpForm(tester);
    expect(find.byKey(const ValueKey('form-jump-general')), findsOneWidget);
    expect(find.byKey(const ValueKey('form-jump-contact')), findsOneWidget);
    // Fold "ช่องทางติดต่อ" (has the required phone).
    await tester.tap(find.byKey(const ValueKey('form-section-contact')));
    await tester.pumpAndSettle();
    expect(find.textContaining('โทรศัพท์', findRichText: true), findsNothing);
    expect(find.textContaining('กรอกแล้ว 0/2'), findsOneWidget);
    // Save with it missing → the section opens again and shows the error.
    await tester.tap(find.byKey(const ValueKey('entity-save')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.textContaining('โทรศัพท์', findRichText: true), findsWidgets);
    expect(find.text('จำเป็นต้องกรอก'), findsWidgets);
    expect(find.byKey(const ValueKey('entity-cancel')), findsOneWidget);
    await tester.pump(const Duration(minutes: 2));
  });

  testWidgets('filter sheet: cards, active chips, clear one group, clear all, apply', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var q = const NxListQuery();
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => NxScrollScaffold(
          header: const NxAppHeader(title: '[QA] รายการ'),
          body: NxListToolbar(
            query: q,
            onChanged: (v) => setState(() => q = v),
            groups: const [
              NxFilterGroup(key: 's', label: 'สถานะ', options: [NxFilterOption('a', 'ใหม่'), NxFilterOption('b', 'ปิดแล้ว')]),
              NxFilterGroup(key: 't', label: 'ประเภท', options: [NxFilterOption('x', 'ลูกค้า'), NxFilterOption('y', 'คู่ค้า')]),
            ],
            sorts: const [NxSortOption('new', 'ใหม่สุด'), NxSortOption('old', 'เก่าสุด')],
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byTooltip('ตัวกรอง'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('filter-group-s')), findsOneWidget);
    await tester.tap(find.text('ใหม่'));
    await tester.tap(find.text('ลูกค้า'));
    await tester.pumpAndSettle();
    // Summary of what is picked, removable.
    expect(find.byKey(const ValueKey('filter-active')), findsOneWidget);
    expect(find.text('สถานะ: ใหม่'), findsOneWidget);
    // Clear only "สถานะ".
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('filter-group-s')), matching: find.text('ล้าง')));
    await tester.pumpAndSettle();
    expect(find.text('สถานะ: ใหม่'), findsNothing);
    expect(find.text('ประเภท: ลูกค้า'), findsOneWidget);
    await tester.tap(find.text('ใช้ตัวกรอง (1)'));
    await tester.pumpAndSettle();
    expect(q.filters, {'t': {'x'}});
  });
}

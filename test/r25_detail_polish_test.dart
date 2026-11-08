import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/screens/crm/entity_detail_parts.dart';
import 'package:nextx_mobile/screens/crm/entity_ops.dart' show RelatedItemTile, relatedNo, relatedStatus;

void main() {
  test('related rows always have number and status', () {
    expect(relatedNo('deal', {'no': 'DL-1'}), 'DL-1');
    expect(relatedNo('service_contract', {'contract_no': 'SC-9'}), 'SC-9');
    expect(relatedStatus('deal', {'deal_stage': 'Won'}), 'Won');
    expect(relatedStatus('case', {'status': 'Open'}), 'Open');
    expect(relatedNo('lead', {}), '');
  });

  testWidgets('related tile shows name, number and a status pill', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: RelatedItemTile(module: 'contact', name: '[QA] related', no: 'C26110800002', status: 'Active')),
    ));
    expect(find.text('[QA] related'), findsOneWidget);
    expect(find.text('C26110800002'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('stepper: passed stages get a green check, later ones do not', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EntityStatusStepper(
          options: const [(value: 'new', label: 'ใหม่'), (value: 'contacted', label: 'ติดต่อแล้ว'), (value: 'won', label: 'ปิดการขาย')],
          current: 'contacted',
          onSelect: (_) {},
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('step-done-new')), findsOneWidget);
    expect(find.byKey(const ValueKey('step-done-contacted')), findsNothing);
    expect(find.byKey(const ValueKey('step-done-won')), findsNothing);
    final dot = tester.widget<Container>(find.byKey(const ValueKey('step-done-new')));
    expect((dot.decoration as BoxDecoration).color, kStepDoneGreen);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/card_layout.dart';
import 'package:nextx_mobile/widgets/nx_entity_card.dart';

void main() {
  final fields = [
    {'name': 'quotation_no', 'type': 'Counter', 'label_th': 'เลขที่'},
    {'name': 'customer_name', 'type': 'Text', 'label_th': 'ลูกค้า'},
    {'name': 'quotation_name', 'type': 'Text', 'label_th': 'ชื่อใบเสนอราคา'},
    {'name': 'quote_date', 'type': 'Date', 'label_th': 'วันที่ในใบเสนอราคา'},
    {'name': 'smownerid', 'type': 'PicklistUser', 'label_th': 'เจ้าของ'},
    {'name': 'grand_total', 'type': 'Number', 'label_th': 'ยอดรวม'},
    {'name': 'quotation_status', 'type': 'Enum', 'label_th': 'สถานะ'},
  ];

  test('defaults pick number, customer, document date, owner, total and status', () {
    final l = CardLayout.defaults('quotation', fields, statusKey: 'quotation_status');
    expect(l.top, 'quotation_no');
    expect(l.title, 'customer_name');
    expect(l.subtitle, 'quotation_name');
    expect(l.date, 'quote_date');
    expect(l.person, 'smownerid');
    expect(l.amount, 'grand_total');
    expect(l.badge, 'quotation_status');
    final round = CardLayout.fromJson(l.withSlot('top', null).withSubtitleMode('never').toJson());
    expect(round.top, isNull);
    expect(round.subtitleMode, 'never');
  });

  testWidgets('card renders formatted slots', (tester) async {
    final ctx = CardFieldContext(
      fields: fields,
      picklists: {
        'quotation_status': [
          {'value': 'Approved', 'value_th': 'อนุมัติ', 'value_en': 'Approved'},
        ],
      },
      users: {'5': 'รัชพล'},
    );
    final l = CardLayout.defaults('quotation', fields, statusKey: 'quotation_status');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NxEntityCard(
          row: const {
            'quotation_no': 'SCI/H26110047',
            'customer_name': 'BNH Medical',
            'quotation_name': 'Side rail label',
            'quote_date': '2026-11-09',
            'smownerid': 5,
            'grand_total': '3600',
            'quotation_status': 'Approved',
          },
          layout: l,
          fields: ctx,
        ),
      ),
    ));
    expect(find.text('SCI/H26110047'), findsOneWidget);
    expect(find.text('BNH Medical'), findsOneWidget);
    expect(find.text('อนุมัติ'), findsOneWidget);
    expect(find.text('09/11/2569'), findsOneWidget);
    expect(find.text('รัชพล'), findsOneWidget);
    expect(find.text('฿ 3,600.00'), findsOneWidget);
  });
}

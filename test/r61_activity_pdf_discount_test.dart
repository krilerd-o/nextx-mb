import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/screens/docs/document_preview.dart';
import 'package:nextx_mobile/widgets/fields/nx_entity_form.dart';

void main() {
  test('discount text follows its type', () {
    expect(catalogDiscountText('product_discount', {'product_discount': '15', 'product_discount_type': 'percent'}), '15%');
    expect(catalogDiscountText('service_discount', {'service_discount': '100.50', 'service_discount_type': 'amount'}), '฿100.5');
    expect(catalogDiscountText('product_discount', {'product_discount': 200}), '฿200'); // no type = baht
    expect(catalogDiscountText('product_discount', {'product_discount': ''}), isNull);
    expect(catalogDiscountText('product_price', {'product_price': 5}), isNull);
  });

  test('activity PDF document offers Thai and English', () {
    final src = activityDocumentSource('7', subject: 'เข้าพบลูกค้า');
    expect(src.variants.map((v) => v.id), ['th', 'en']);
    expect(src.fileBase, 'activity-7');
  });

  testWidgets('discount has a บาท / % toggle instead of a type field', (tester) async {
    final values = <String, dynamic>{'product_discount': '10', 'product_discount_type': 'amount'};
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: NxEntityForm(
              module: 'product',
              fields: const [
                {'name': 'product_discount', 'label_th': 'ส่วนลด', 'uitype': 'Number'},
                {'name': 'product_discount_type', 'label_th': 'ประเภทส่วนลด', 'uitype': 'Picklist'},
              ],
              values: values,
              onChanged: (k, v) => setState(() => values[k] = v),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('discount-type-product_discount')), findsOneWidget);
    expect(find.text('ประเภทส่วนลด'), findsNothing);
    await tester.tap(find.text('%'));
    await tester.pump();
    expect(values['product_discount_type'], 'percent');
  });
}

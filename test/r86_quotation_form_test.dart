import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/doc_form/doc_form_rules.dart';
import 'package:nextx_mobile/core/doc_form/doc_pick_rules.dart';
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/screens/doc_form/barcode_scan_sheet.dart';
import 'package:nextx_mobile/screens/doc_form/doc_form_launcher.dart';
import 'package:nextx_mobile/services/api_client.dart';

import 'support/doc_form_harness.dart';
import 'support/r86_quote_fake.dart';

final List<Map<String, dynamic>?> results = [];

Widget opener({DocFormMode mode = DocFormMode.create, String? id}) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey('open'),
            onPressed: () async => results.add(await openDocForm(context, module: 'quotation', mode: mode, id: id)),
            child: const Text('open'),
          ),
        ),
      ),
    );

final source9 = <String, Object?>{
  'GET /api/entity/quotation/9': {
    'id': 9, 'quotation_no': 'QT26-0009', 'quotation_status': 'เปิดใบเสนอราคา', 'approval_state': 'approved', 'revision_no': 0,
    'customer_name': 'บริษัท สยามเทค โซลูชั่น จำกัด', 'related_account_id': 5, 'related_contact_id': 71, 'contact_name': 'สมศรี ใจงาม',
    'title_th': 'Endpoint Security', 'quote_date': '2026-11-01', 'valid_until': '2026-12-01', 'validity_days': 30, 'tax_type': 'exclude', 'tax_rate': 7,
    'smownerid': 2, 'template_key': 'template1', 'template_id': 1, 'terms_conditions': '<p>ยืนราคา 30 วัน</p>',
    'header_discount_type': 'amount', 'header_discount_value': 500,
  },
  'GET /api/quotation/9/lines': {
    'list': [
      {'id': 1, 'quotation_id': 9, 'line_no': 1, 'line_type': 'product', 'product_id': 31, 'description': 'Kaspersky Endpoint Security', 'quantity': 25, 'unit': 'License', 'unit_price': 1290, 'discount_type': 'percent', 'discount_pct': 5, 'discount_amount': 0, 'tax_pct': 7},
    ],
  },
  'GET /api/quotation/9/revisions': {'list': [{'id': 9, 'revision_no': 0}]},
  'POST /api/quotation/9/revise': {'id': 10, 'quotation_no': 'QT26-0009-R1', 'revision_no': 1},
  'POST /api/quotation/save': {'id': 9, 'quotation': {'id': 9, 'quotation_no': 'QT26-0009'}},
};

Future<DocFormHarness> openForm(WidgetTester tester, {DocFormMode mode = DocFormMode.create, String? id, Map<String, Object?> extra = const {}, Map<String, Object> prefs = const {}}) async {
  final h = DocFormHarness(tester);
  await h.pump(opener(mode: mode, id: id), quoteFakeReplies(extra: extra), prefs: prefs);
  installQuoteFakeServer(h.adapter);
  await h.tap(const ValueKey('open'));
  await h.settle();
  return h;
}

Future<void> search(DocFormHarness h, String key, String text) async {
  await h.tester.enterText(find.byKey(ValueKey(key)), text);
  await h.tester.pump(const Duration(milliseconds: 350));
  await h.settle();
}

Future<void> pickSiamTech(DocFormHarness h) async {
  await h.tap(const ValueKey('qt-customer-pick'));
  await search(h, 'customer-search', 'สยาม');
  await h.tap(const ValueKey('customer-hit-account-5'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    results.clear();
    DocFormHooks.reset();
  });

  group('product search (owner: "kas" found nothing)', () {
    testWidgets('root cause: q alone only searches the server floor (product_no) — search_cols finds Kaspersky', (tester) async {
      final h = DocFormHarness(tester);
      await h.pump(const SizedBox(), quoteFakeReplies());
      installQuoteFakeServer(h.adapter);
      final api = h.config.apiClient;
      // The old request (the form's inline box): GET /api/entity/product?q=kas → nothing.
      final old = await tester.runAsync(() => api.getEntityList('product', q: 'kas', limit: 8));
      expect(old!.items, isEmpty, reason: 'MODULE_SEARCH_COLUMNS.product = productname / name / product_no: no name column exists');
      // The picker names the real columns.
      for (final q in ['kas', 'KAS', 'Kaspersky', 'KES-B']) {
        final page = await tester.runAsync(() => api.searchPicker('product', q: q));
        expect(page!.items.map((r) => r['id']), [31], reason: q);
      }
      final c = h.adapter.calls.last;
      expect(c.queryParameters['search_cols'], 'product_name_th,product_name_en,product_code,product_no');
      expect(c.queryParameters['q'], 'KES-B');
      expect(pickerQueryParams('service', q: 'x')['search_cols'], contains('service_name_th'));
      expect(pickerQueryParams('product').containsKey('search_cols'), isFalse, reason: 'no text, no columns');
    });

    testWidgets('in the form: kas → Kaspersky with price / unit / stock, picked with a quantity', (tester) async {
      final h = await openForm(tester);
      await pickSiamTech(h);
      await h.tap(const ValueKey('docform-next'));
      await h.tap(const ValueKey('qt-add-catalog'));
      expect(find.byKey(const ValueKey('catalog-picker')), findsOneWidget, reason: 'its own page, not a list in the form');
      await search(h, 'catalog-search', 'kas');
      expect(find.byKey(const ValueKey('catalog-hit-product-31')), findsOneWidget);
      expect(find.byKey(const ValueKey('picker-empty')), findsNothing);
      expect(find.text('฿1,290.00 / License'), findsOneWidget);
      expect(find.text('คงเหลือ 42'), findsOneWidget, reason: 'stock from the parts catalog');
      await h.tap(const ValueKey('catalog-hit-product-31'));
      await h.tap(const ValueKey('qty-plus'));
      await h.tap(const ValueKey('catalog-confirm'));
      expect(find.byKey(const ValueKey('catalog-picker')), findsNothing);
      expect(h.textOf(const ValueKey('qline-0-amount')), '฿2,580.00');
    });
  });

  testWidgets('customer picker: type / owner filters, recent picks first, contact picker with "ไม่ระบุ"', (tester) async {
    const recent = {'nx.docform.recent.customer.1': '[{"module":"lead","id":"91","title":"ปกรณ์ แสงทอง","subtitle":"ร้านกาแฟ คาซ่า"}]'};
    final h = await openForm(tester, prefs: recent);
    expect(find.byKey(const ValueKey('customer-search')), findsNothing, reason: 'no inline search in step 1');
    await h.tap(const ValueKey('qt-customer-pick'));
    expect(find.byKey(const ValueKey('customer-recent-lead-91')), findsOneWidget);
    // All kinds at once, grouped.
    expect(find.byKey(const ValueKey('customer-hit-account-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('customer-hit-contact-71')), findsOneWidget);
    expect(find.byKey(const ValueKey('customer-hit-lead-91')), findsOneWidget);
    // Type filter: contacts only.
    h.adapter.calls.clear();
    await h.tap(const ValueKey('customer-kind-contact'));
    expect(h.adapter.calls.map((c) => c.path).toSet(), {'/api/entity/contact'});
    expect(find.byKey(const ValueKey('customer-hit-account-5')), findsNothing);
    expect(find.byKey(const ValueKey('customer-hit-contact-73')), findsOneWidget);
    // ของฉัน: owner = me.
    await h.tap(const ValueKey('customer-mine'));
    expect(h.adapter.calls.last.queryParameters['filter[smownerid]'], '1');
    expect(find.byKey(const ValueKey('customer-hit-contact-73')), findsNothing, reason: 'owned by user 2');
    await search(h, 'customer-search', 'zzzz');
    expect(find.byKey(const ValueKey('picker-empty')), findsOneWidget);
    await h.tap(const ValueKey('customer-mine'));
    await h.tap(const ValueKey('customer-kind-account'));
    await search(h, 'customer-search', 'สยาม');
    await h.tap(const ValueKey('customer-hit-account-5'));
    // Compact card; details folded; contact = one row.
    expect(find.byKey(const ValueKey('qt-customer-card')), findsOneWidget);
    expect(find.text('99/9 ถนนพระราม 9 ห้วยขวาง กรุงเทพมหานคร'), findsOneWidget, reason: 'card only — the details are folded');
    expect(find.byKey(const ValueKey('nx-field-customer_address')), findsNothing);
    expect(h.textOf(const ValueKey('qt-customer-kind')), 'บัญชีลูกค้า');
    await h.tap(const ValueKey('qt-contact-pick'));
    expect(find.byKey(const ValueKey('contact-hit-71')), findsOneWidget);
    expect(find.byKey(const ValueKey('contact-hit-73')), findsNothing, reason: 'another account');
    await search(h, 'contact-search', 'วิชัย');
    expect(find.byKey(const ValueKey('contact-hit-71')), findsNothing);
    await h.tap(const ValueKey('contact-hit-72'));
    expect(h.textOf(const ValueKey('qt-contact-value')), 'วิชัย ศรีสุข');
    await h.tap(const ValueKey('qt-contact-pick'));
    await h.tap(const ValueKey('contact-none'));
    expect(h.textOf(const ValueKey('qt-contact-value')), 'ไม่ระบุ');
    // แก้รายละเอียดบนเอกสาร opens the prefilled fields.
    await h.tap(const ValueKey('qt-customer-edit-details'));
    expect(find.byKey(const ValueKey('nx-field-customer_address')), findsOneWidget);
    expect(find.byKey(const ValueKey('nx-field-customer_taxid')), findsOneWidget);
    // Picked accounts become recent.
    final prefs = await h.prefsNow();
    expect(prefs['nx.docform.recent.customer.1'], contains('"id":"5"'));
  });

  testWidgets('catalog picker: filters, multi-select add, qty / discount math, line menu', (tester) async {
    final h = await openForm(tester);
    await pickSiamTech(h);
    await h.tap(const ValueKey('docform-next'));
    await h.tap(const ValueKey('qt-add-catalog'));
    // Product / service + category (from the product field schema) filters.
    await h.tap(const ValueKey('catalog-kind-product'));
    expect(find.byKey(const ValueKey('catalog-hit-service-51')), findsNothing);
    await h.tap(const ValueKey('catalog-category'));
    await h.tap(const ValueKey('option-Network'));
    expect(h.adapter.calls.lastWhere((c) => c.path == '/api/entity/product').queryParameters['filter[product_category]'], 'Network');
    expect(find.byKey(const ValueKey('catalog-hit-product-32')), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-hit-product-31')), findsNothing);
    await h.tap(const ValueKey('catalog-hit-product-32'));
    await h.tap(const ValueKey('catalog-kind-all'));
    await h.tap(const ValueKey('catalog-hit-service-51'));
    await h.tap(const ValueKey('catalog-hit-product-31'));
    final plus31 = find.descendant(of: find.byKey(const ValueKey('catalog-hit-product-31')), matching: find.byKey(const ValueKey('qty-plus')));
    await tester.tap(plus31);
    await tester.tap(plus31);
    await h.settle(2);
    expect(find.text('เพิ่ม 3 รายการ'), findsOneWidget);
    await h.tap(const ValueKey('catalog-confirm'));
    // 3 lines in pick order: FortiGate 1, install 1, Kaspersky 3.
    expect([h.textOf(const ValueKey('qline-0-amount')), h.textOf(const ValueKey('qline-1-amount')), h.textOf(const ValueKey('qline-2-amount'))],
        ['฿26,500.00', '฿850.00', '฿3,870.00']);
    // Steppers + line discount %: 4 × 1290 = 5160 − 10 % = 4644.
    await h.tap(const ValueKey('qline-2-plus'));
    await h.type('qline-2-disc', '10');
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('qline-2-disc-type')), matching: find.text('%')));
    await tester.pump();
    expect(h.textOf(const ValueKey('qline-2-amount')), '฿4,644.00');
    expect(h.textOf(const ValueKey('qline-2-math')), '4 × ฿1,290.00 = ฿5,160.00 · ลด ฿516.00');
    // ส่วนลดท้ายบิล: the right label (not the column's "ค่าส่วนลดหัวบิล").
    expect(find.textContaining('ค่าส่วนลดหัวบิล'), findsNothing);
    expect(find.textContaining('ส่วนลดท้ายบิล (บาท)'), findsWidgets);
    await h.type('header_discount_value', '994');
    // 26500 + 850 + 4644 = 31994 − 994 = 31000 + 7 % = 33170.
    expect(h.textOf(const ValueKey('qt-lines-total-subtotal')), '฿32,510.00');
    expect(h.textOf(const ValueKey('qt-lines-total-discount')), '฿1,510.00');
    expect(h.textOf(const ValueKey('qt-lines-total-vat')), '฿2,170.00');
    expect(h.textOf(const ValueKey('docform-bar-total')), '฿33,170.00');
    // Menu: move the install line down, copy, remove (with confirm).
    await h.tap(const ValueKey('qline-1-menu'));
    await h.tap(const ValueKey('qline-menu-down'));
    expect(h.textOf(const ValueKey('qline-2-amount')), '฿850.00');
    await h.tap(const ValueKey('qline-2-menu'));
    await h.tap(const ValueKey('qline-menu-remove'));
    expect(find.byKey(const ValueKey('delete-confirm')), findsOneWidget, reason: 'the app confirm sheet');
    await h.tap(const ValueKey('delete-confirm'));
    expect(find.byKey(const ValueKey('qline-2')), findsNothing);
    // Typed line from the picker.
    await h.tap(const ValueKey('qt-add-catalog'));
    await h.tap(const ValueKey('catalog-free-line'));
    expect(find.byKey(const ValueKey('nx-field-qline-2-desc')), findsOneWidget);
  });

  testWidgets('template names (ค่าเริ่มต้น, never "default") and the rich-text field layout', (tester) async {
    expect(quotationTemplateLabel({'id': 1, 'name': 'default', 'code': 'default', 'layout_json': {'is_default': true}}), 'ค่าเริ่มต้น');
    expect(quotationTemplateLabel({'id': 2, 'name': 'Service', 'layout_json': {'is_default': true}}), 'Service (ค่าเริ่มต้น)');
    expect(quotationTemplateLabel({'id': 3, 'name': '', 'code': 'cb'}), 'cb');
    expect(quotationTemplateLabel({'id': 4, 'name': 'Default'}, th: false), 'Default');
    expect(quotationLayoutLabel('template2'), 'Template-2 · ฟอร์มตาราง');
    expect(cleanFieldLabel('เงื่อนไข (HTML)'), 'เงื่อนไข');

    final h = await openForm(tester);
    await pickSiamTech(h);
    await h.tap(const ValueKey('docform-next'));
    await h.tap(const ValueKey('qt-add-text-line'));
    await h.type('qline-0-desc', 'ค่าบริการ');
    await h.type('qline-0-price', '1000');
    await h.tap(const ValueKey('docform-next'));
    expect(h.textOf(const ValueKey('qt-template-value')), 'ค่าเริ่มต้น');
    await h.tap(const ValueKey('qt-template-pick'));
    expect(find.text('default'), findsNothing);
    expect(find.text('หัวกระดาษเริ่มต้นของธุรกิจ'), findsOneWidget);
    await h.tap(const ValueKey('qt-template-3'));
    expect(h.textOf(const ValueKey('qt-template-value')), 'หัวกระดาษ สาขาชลบุรี');

    // Rich text: label, then toolbar, then text — stacked, never on top of each other.
    expect(find.textContaining('(HTML)'), findsNothing);
    for (final name in ['terms_conditions', 'quote_termcondition']) {
      final f = find.byKey(ValueKey('nx-field-$name'));
      await tester.ensureVisible(f);
      await tester.pump();
      Rect r(String k) => tester.getRect(find.descendant(of: f, matching: find.byKey(ValueKey(k))));
      final label = r('rte-label'), bold = r('rte-bold'), field = r('rte-field');
      expect(label.bottom, lessThanOrEqualTo(bold.top), reason: '$name: toolbar under the label');
      expect(bold.bottom, lessThanOrEqualTo(field.top), reason: '$name: text under the toolbar');
      expect(find.descendant(of: f, matching: find.byType(InputDecorator)).evaluate().length, 1, reason: '$name: one box, not a box in a box');
    }
    expect(find.descendant(of: find.byKey(const ValueKey('nx-field-terms_conditions')), matching: find.text('เงื่อนไข')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('nx-field-quote_termcondition')), matching: find.text('ท้ายเอกสาร')), findsOneWidget);
    // Typing in it writes HTML into the payload.
    final terms = find.descendant(of: find.byKey(const ValueKey('nx-field-terms_conditions')), matching: find.byKey(const ValueKey('rte-field')));
    await tester.enterText(terms, 'ส่งของภายใน 7 วัน');
    await tester.pump();
    await h.tap(const ValueKey('docform-next'));
    expect(h.textOf(const ValueKey('qt-review-template')), 'หัวกระดาษ สาขาชลบุรี');
    await h.tap(const ValueKey('docform-save'), settleFrames: 10);
    final f = Map<String, dynamic>.from(h.body('POST', '/api/quotation/save')['fields'] as Map);
    expect([f['terms_conditions'], f['terms'], f['template_id']], ['<p>ส่งของภายใน 7 วัน</p>', '<p>ส่งของภายใน 7 วัน</p>', 3]);
  });

  testWidgets('step badges: quiet at first, amber count once checked, green check when done; review jumps back', (tester) async {
    final h = await openForm(tester);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('docform-step-missing-$i')), findsNothing);
      expect(find.byKey(ValueKey('docform-step-done-$i')), findsNothing);
    }
    await h.tap(const ValueKey('docform-next'));
    expect(h.textOf(const ValueKey('docform-step-missing-0')), '1');
    expect(find.byKey(const ValueKey('docform-step-warn-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('docform-customer-error')), findsOneWidget);
    await pickSiamTech(h);
    expect(find.byKey(const ValueKey('docform-step-missing-0')), findsNothing);
    await h.tap(const ValueKey('docform-next'));
    expect(find.byKey(const ValueKey('docform-step-done-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('docform-step-missing-1')), findsNothing, reason: 'the current step is not nagged before ถัดไป');
    await h.tap(const ValueKey('docform-next'));
    expect(h.textOf(const ValueKey('docform-step-missing-1')), '1');
    expect(find.byKey(const ValueKey('docform-lines-error')), findsOneWidget);
    await h.tap(const ValueKey('qt-add-catalog'));
    await h.tap(const ValueKey('catalog-hit-product-33'));
    await h.tap(const ValueKey('catalog-confirm'));
    await h.tap(const ValueKey('docform-next'));
    await h.tap(const ValueKey('docform-next'));
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('docform-step-done-$i')), findsOneWidget, reason: 'step $i');
    }
    // Review: jump-to-edit per section.
    await h.tap(const ValueKey('qt-review-edit-1'));
    expect(find.byKey(const ValueKey('qt-add-catalog')), findsOneWidget);
    await h.tap(const ValueKey('docform-step-3'));
    await h.tap(const ValueKey('qt-review-edit-0'));
    expect(find.byKey(const ValueKey('qt-customer-card')), findsOneWidget);
  });

  group('the four modes send what the web sends', () {
    testWidgets('create: POST /quotation/save without id, header + lines', (tester) async {
      final h = await openForm(tester);
      await pickSiamTech(h);
      await h.tap(const ValueKey('qt-contact-pick'));
      await h.tap(const ValueKey('contact-hit-71'));
      await h.tap(const ValueKey('docform-next'));
      await h.tap(const ValueKey('qt-add-catalog'));
      await search(h, 'catalog-search', 'kas');
      await h.tap(const ValueKey('catalog-hit-product-31'));
      await h.tap(const ValueKey('catalog-confirm'));
      await h.tap(const ValueKey('docform-step-3'));
      await h.tap(const ValueKey('docform-next'));
      await h.tap(const ValueKey('docform-next'));
      expect(find.text('สร้างใบเสนอราคา'), findsWidgets);
      await h.tap(const ValueKey('docform-save'), settleFrames: 10);
      final b = h.body('POST', '/api/quotation/save');
      expect(b.containsKey('id'), isFalse);
      final f = Map<String, dynamic>.from(b['fields'] as Map);
      expect([f['customer_name'], f['related_account_id'], f['related_contact_id'], f['contact_name'], f['customer_taxid']],
          ['บริษัท สยามเทค โซลูชั่น จำกัด', 5, 71, 'สมศรี ใจงาม', '0105561000123']);
      expect([f['tax_type'], f['tax_rate'], f['template_key'], f['template_id'], f['header_discount_type'], f['header_discount_value']],
          ['exclude', 7, 'template1', 1, 'none', 0]);
      expect(f['quote_date'], ymd(thaiNow()));
      expect(f['terms_conditions'], contains('ยืนราคา 30 วัน'), reason: 'my default text block');
      final line = (b['lines'] as List).single as Map;
      expect([line['line_no'], line['line_type'], line['product_id'], line['quantity'], line['unit_price'], line['unit'], line.containsKey('_k')],
          [1, 'product', 31, 1, 1290, 'License', false]);
      expect(results.single?['id'], '50');
    });

    testWidgets('edit: POST /quotation/save with id, every core field (cleared ones as null)', (tester) async {
      final h = await openForm(tester, mode: DocFormMode.edit, id: '9', extra: source9);
      expect(find.byKey(const ValueKey('docform-edit-banner')), findsOneWidget);
      expect(find.text('QT26-0009'), findsWidgets);
      await h.tap(const ValueKey('docform-step-1'));
      await h.tap(const ValueKey('qline-0-minus'));
      await h.tap(const ValueKey('docform-step-3'));
      expect(find.text('บันทึกการแก้ไข'), findsOneWidget);
      await h.tap(const ValueKey('docform-save'), settleFrames: 10);
      final b = h.body('POST', '/api/quotation/save');
      expect(b['id'], '9');
      final f = Map<String, dynamic>.from(b['fields'] as Map);
      expect([f['title_th'], f['smownerid'], f['related_account_id'], f['header_discount_type'], f['header_discount_value']], ['Endpoint Security', 2, 5, 'amount', 500]);
      for (final k in ['quotation_status', 'quotation_no', 'grand_total']) {
        expect(f.containsKey(k), isFalse, reason: k);
      }
      final line = (b['lines'] as List).single as Map;
      expect([line['quantity'], line['discount_type'], line['discount_pct'], line.containsKey('id')], [24, 'percent', 5, false]);
    });

    testWidgets('duplicate: a new quotation (no id), "(Copy)", dated today, number / status cleared', (tester) async {
      final h = await openForm(tester, mode: DocFormMode.duplicate, id: '9', extra: source9);
      expect(find.byKey(const ValueKey('docform-duplicate-banner')), findsOneWidget);
      await h.tap(const ValueKey('docform-step-3'));
      expect(find.text('สร้างใบใหม่จากสำเนา'), findsOneWidget);
      await h.tap(const ValueKey('docform-save'), settleFrames: 10);
      final b = h.body('POST', '/api/quotation/save');
      expect(b.containsKey('id'), isFalse);
      final f = Map<String, dynamic>.from(b['fields'] as Map);
      expect([f['title_th'], f['quote_date'], f['valid_until'], f['related_account_id']], ['Endpoint Security (Copy)', ymd(thaiNow()), addDaysYmd(ymd(thaiNow()), 30), 5]);
      for (final k in ['quotation_no', 'quotation_status', 'approval_state', 'revision_no']) {
        expect(f.containsKey(k), isFalse, reason: k);
      }
      final line = (b['lines'] as List).single as Map;
      expect([line['product_id'], line['quantity'], line.containsKey('id'), line.containsKey('quotation_id')], [31, 25, false, false]);
    });

    testWidgets('revise: POST /quotation/:id/revise with fields + lines + revision_note (required)', (tester) async {
      final h = await openForm(tester, mode: DocFormMode.revise, id: '9', extra: source9);
      expect(find.byKey(const ValueKey('docform-revise-banner')), findsOneWidget);
      expect(h.textOf(const ValueKey('docform-step-missing-3')), '1', reason: 'reason still needed');
      await h.tap(const ValueKey('docform-step-1'));
      await h.tap(const ValueKey('qline-0-plus'));
      expect(find.byKey(const ValueKey('qline-0-change')), findsOneWidget);
      await h.tap(const ValueKey('docform-step-3'));
      expect(find.text('สร้างฉบับแก้ไข R1'), findsOneWidget);
      await h.tap(const ValueKey('docform-save'));
      expect(h.called('POST', '/api/quotation/9/revise'), isFalse);
      await h.type('revision_note', 'ลูกค้าเพิ่ม 1 License');
      await h.tap(const ValueKey('docform-save'), settleFrames: 10);
      final b = h.body('POST', '/api/quotation/9/revise');
      expect(b['revision_note'], 'ลูกค้าเพิ่ม 1 License');
      expect(((b['lines'] as List).single as Map)['quantity'], 26);
      final f = Map<String, dynamic>.from(b['fields'] as Map);
      expect([f['title_th'], f['smownerid'], f['quote_date']], ['Endpoint Security', 2, '2026-11-01'], reason: 'the revision keeps the source header');
      expect(h.called('POST', '/api/quotation/save'), isFalse);
      expect(results.single?['id'], '10');
    });
  });

  test('picker query params / display rules', () {
    final p = pickerQueryParams('account', q: 'สยาม', filters: {'smownerid': '1', 'x': ' '});
    expect(p['search_cols'], contains('account_taxid'));
    expect([p['sort'], p['order'], p['with_total'], p['filter[smownerid]'], p.containsKey('filter[x]')], ['account_name', 'asc', '1', '1', false]);
    final v = catalogItemView('product', kasperskyRow);
    expect([v.name, v.code, v.unit, v.priceText, v.stock], [kasperskyRow['product_name_th'], 'KES-B-1Y', 'License', '฿1,290.00 / License', null]);
    final merged = mergeCatalogStock([kasperskyRow], [{'product_id': 31, 'stock_qty': 4}]);
    expect(catalogItemView('product', merged.single).stock, 4);
    expect(customerRowSubtitle('account', fakeAccounts.first), 'ACC-0005 · 021234567 · purchase@siamtech.co.th · เลขภาษี 0105561000123');
    expect(customerRowSubtitle('lead', fakeLeads.first), 'ร้านกาแฟ คาซ่า · 0901112222');
    expect(ApiClient, isNotNull);
  });
}

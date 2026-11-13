import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/doc_form/doc_form_rules.dart';
import 'package:nextx_mobile/core/navigation/notification_deep_link.dart';
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/screens/crm/entity_create_screen.dart';
import 'package:nextx_mobile/screens/doc_form/barcode_scan_sheet.dart';
import 'package:nextx_mobile/screens/doc_form/doc_form_launcher.dart';
import 'package:nextx_mobile/screens/doc_form/job_step_form.dart';
import 'package:nextx_mobile/screens/doc_form/quotation_step_form.dart';
import 'package:nextx_mobile/widgets/fields/nx_form_field.dart';

import 'support/doc_form_harness.dart';

Map<String, dynamic> fld(String name, String type, {String section = 'main', bool required = false, String access = 'editable', bool readonly = false, String? label}) =>
    {'name': name, 'type': type, 'section': section, 'required': required, 'access': access, 'presence': 1, 'readonly': readonly, 'label_th': label ?? name};

List<Map<String, dynamic>> qtFields({List<Map<String, dynamic>> extra = const []}) => [
      fld('quotation_no', 'Counter', readonly: true),
      fld('quotation_status', 'Enum'),
      fld('quote_date', 'Date'),
      fld('valid_until', 'Date'),
      fld('delivery_date', 'Date'),
      fld('title_th', 'Text'),
      fld('customer_name', 'Text'),
      fld('related_account_id', 'AccountSelect'),
      fld('related_contact_id', 'ContactSelect'),
      fld('customer_address', 'LongText'),
      fld('customer_taxid', 'Text'),
      fld('contact_name', 'Text'),
      fld('customer_mobile', 'Phone'),
      fld('customer_email', 'Email'),
      fld('customer_phone', 'Phone'),
      fld('grand_total', 'Number'),
      fld('header_discount_type', 'Enum'),
      fld('header_discount_value', 'Number'),
      fld('tax_type', 'Enum'),
      fld('tax_rate', 'Number'),
      fld('smownerid', 'PicklistUser'),
      fld('payment_details', 'LongText', label: 'การชำระเงิน'),
      fld('validity_days', 'Number'),
      fld('cf_site_contact', 'Text', section: 'ข้อมูลลูกค้าเพิ่มเติม', label: 'ผู้ประสานงานหน้างาน'),
      fld('cf_po_required', 'Text', required: true, label: 'เลข PO ลูกค้า'),
      fld('cf_secret', 'Text', access: 'hidden'),
      ...extra,
    ];

final qtContext = {
  'layouts': {'allowed_layouts': ['template1', 'template2'], 'default_layout': 'template1', 'line_discount_mode': 'per_unit'},
  'new_defaults': {'validity_days': 30, 'payment_details': 'เครดิต 30 วัน', 'tax_type': 'exclude', 'tax_rate': 7},
  'templates': [
    {'id': 1, 'name': 'โลโก้หลัก', 'layout_key': 'template1', 'layout_json': {'is_default': true}},
    {'id': 2, 'name': 'Service', 'layout_key': 'template2', 'layout_json': {'is_default': true}},
  ],
  'users': [
    {'id': 1, 'label': 'สมชาย ใจดี'},
  ],
};

Map<String, Object?> qtReplies({List<Map<String, dynamic>>? fields}) => {
      'GET /api/fields/quotation': {
        'list': fields ?? qtFields(),
        'picklists': {
          'tax_type': [{'value': 'exclude', 'is_default': 1}, {'value': 'include'}],
          'quotation_status': [{'value': 'เปิดใบเสนอราคา'}],
        },
      },
      'GET /api/quotation/context': qtContext,
      'GET /api/quotation/text-templates/defaults/resolve': {'terms': {'html': '<p>ราคานี้ยืนราคา 30 วัน</p>'}},
      'GET /api/entity/account': {'list': [{'id': 5, 'account_name': 'บริษัท เอ จำกัด'}]},
      'GET /api/entity/contact': {'list': [{'id': 7, 'contact_firstname': 'สมศรี', 'contact_lastname': 'ใจงาม', 'account_id': 5}]},
      'GET /api/entity/lead': {'list': <Object>[]},
      'GET /api/entity/account/5': {
        'id': 5, 'account_name': 'บริษัท เอ จำกัด', 'account_taxid': '0105555000001', 'address_line1': '99 ถนนพระราม 9',
        'address_district': 'ห้วยขวาง', 'address_province': 'กรุงเทพมหานคร', 'mobile_1st': '0811111111', 'email_1st': 'buy@a.co.th',
      },
      'GET /api/entity/contact/7': {'id': 7, 'contact_firstname': 'สมศรี', 'contact_lastname': 'ใจงาม', 'mobile_1st': '0899999999', 'email_1st': 'somsri@a.co.th', 'account_id': 5},
      'GET /api/entity/product': {'list': [{'id': 11, 'product_name_th': 'กล้อง IP', 'product_code': 'CAM-01', 'product_selling_price': 900}]},
      'GET /api/entity/service': {'list': <Object>[]},
      'GET /api/entity/product/11': {
        'id': 11, 'product_name_th': 'กล้อง IP', 'product_unit': 'ตัว', 'product_initial_price': 1000, 'product_selling_price': 900,
        'product_discount': 10, 'product_discount_type': 'percent',
      },
      'POST /api/quotation/save': {'id': 50, 'quotation': {'id': 50, 'quotation_no': 'Q26-0050', 'modifiedtime': '2026-11-13T03:00:00.000Z'}},
    };

final List<Map<String, dynamic>?> results = [];

Widget opener(String module, {DocFormMode mode = DocFormMode.create, String? id, Map<String, dynamic>? prefill}) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey('open'),
            onPressed: () async => results.add(await openDocForm(context, module: module, mode: mode, id: id, initialValues: prefill)),
            child: const Text('open'),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    results.clear();
    DocFormHooks.reset();
  });

  testWidgets('create: steps, one customer search with autofill, catalog + inline lines, live totals (VAT / ฿ / %), save like the web', (tester) async {
    final h = DocFormHarness(tester);
    await h.pump(opener('quotation'), qtReplies());
    await h.tap(const ValueKey('open'));
    await h.settle();

    // 4 steps; a new form does not greet the user with warnings (R86): only
    // steps that were checked or left behind show the amber count.
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('docform-step-$i')), findsOneWidget);
      expect(find.byKey(ValueKey('docform-step-missing-$i')), findsNothing);
    }
    // Not asked on create: status, totals; hidden field never drawn.
    expect(find.byKey(const ValueKey('nx-field-quotation_status')), findsNothing);
    expect(find.byKey(const ValueKey('nx-field-grand_total')), findsNothing);
    expect(find.byKey(const ValueKey('nx-field-cf_secret')), findsNothing);
    // Custom field of a customer section sits on the customer step.
    expect(find.byKey(const ValueKey('docform-extra-0-ข้อมูลลูกค้าเพิ่มเติม')), findsOneWidget);
    expect(find.text('ผู้ประสานงานหน้างาน'), findsWidgets);

    // ถัดไป with no customer: stays, shows what is missing.
    await h.tap(const ValueKey('docform-next'));
    expect(find.byKey(const ValueKey('docform-customer-error')), findsOneWidget);
    expect(h.textOf(const ValueKey('docform-step-missing-0')), '1', reason: 'no customer yet');
    expect(find.byKey(const ValueKey('customer-search')), findsNothing, reason: 'search lives in its own page');

    // One search page: accounts + contacts + leads together.
    await h.tap(const ValueKey('qt-customer-pick'));
    await tester.enterText(find.byKey(const ValueKey('customer-search')), 'บริษัท');
    await tester.pump(const Duration(milliseconds: 400));
    await h.settle();
    expect(find.byKey(const ValueKey('customer-hit-account-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('customer-hit-contact-7')), findsOneWidget);
    expect(h.adapter.calls.where((c) => c.path == '/api/entity/lead' && c.queryParameters['q'] == 'บริษัท'), isNotEmpty);
    await h.tap(const ValueKey('customer-hit-account-5'));
    expect(find.byKey(const ValueKey('qt-customer-card')), findsOneWidget);
    expect(find.text('99 ถนนพระราม 9 ห้วยขวาง กรุงเทพมหานคร'), findsWidgets);
    expect(find.byKey(const ValueKey('docform-step-missing-0')), findsNothing);
    // Contact of that customer: one row → its own picker → name / mobile / e-mail.
    await h.tap(const ValueKey('qt-contact-pick'));
    await h.tap(const ValueKey('contact-hit-7'));
    expect(h.textOf(const ValueKey('qt-contact-value')), 'สมศรี ใจงาม');

    await h.tap(const ValueKey('docform-next'));
    expect(find.byKey(const ValueKey('qt-add-catalog')), findsOneWidget);
    // Catalog item: list price + its 10 % discount → 900.
    await h.tap(const ValueKey('qt-add-catalog'));
    await tester.enterText(find.byKey(const ValueKey('catalog-search')), 'กล้อง');
    await tester.pump(const Duration(milliseconds: 400));
    await h.settle();
    await h.tap(const ValueKey('catalog-hit-product-11'));
    await h.tap(const ValueKey('catalog-confirm'));
    expect(h.textOf(const ValueKey('qline-0-amount')), '฿900.00');
    // Typed line: 2 × 500 − ฿50/unit = 900.
    await h.tap(const ValueKey('qt-add-text-line'));
    await h.type('qline-1-desc', 'ค่าติดตั้ง');
    await h.type('qline-1-qty', '2');
    await h.type('qline-1-price', '500');
    await h.type('qline-1-disc', '50');
    expect(h.textOf(const ValueKey('qline-1-amount')), '฿900.00');
    // End-of-bill 10 %: (2000 − 200) × 0.9 = 1620 + VAT 7 % = 1733.40 in the bar.
    await h.type('header_discount_value', '10');
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('header-discount-type')), matching: find.text('%')));
    await tester.pump();
    expect(h.textOf(const ValueKey('docform-bar-total')), '฿1,733.40');

    await h.tap(const ValueKey('docform-next'));
    // VAT included: the same 1620 already holds the VAT.
    await tester.tap(find.text('ราคารวม VAT แล้ว'));
    await tester.pump();
    expect(h.textOf(const ValueKey('docform-bar-total')), '฿1,620.00');
    await h.tap(const ValueKey('qt-valid-15'));
    // The business-required custom field blocks ถัดไป until filled.
    await h.tap(const ValueKey('docform-next'));
    expect(find.byKey(const ValueKey('docform-step-missing-2')), findsOneWidget);
    expect(find.text('จำเป็นต้องกรอก'), findsWidgets);
    await h.type('cf_po_required', 'PO-77');
    await h.tap(const ValueKey('docform-next'));
    expect(find.byKey(const ValueKey('qt-total-grand')), findsOneWidget);
    expect(h.textOf(const ValueKey('qt-total-vat')), '฿105.98');

    await h.tap(const ValueKey('docform-save'), settleFrames: 10);
    final b = h.body('POST', '/api/quotation/save');
    expect(b.containsKey('id'), isFalse, reason: 'create');
    final f = Map<String, dynamic>.from(b['fields'] as Map);
    final today = thaiNow();
    expect(f['customer_name'], 'บริษัท เอ จำกัด');
    expect([f['related_account_id'], f['related_contact_id'], f['contact_name'], f['customer_taxid'], f['customer_mobile'], f['customer_email']],
        [5, 7, 'สมศรี ใจงาม', '0105555000001', '0899999999', 'somsri@a.co.th']);
    expect([f['header_discount_type'], f['header_discount_value'], f['tax_type'], f['tax_rate']], ['percent', 10, 'include', 7]);
    expect([f['template_key'], f['template_id'], (f['document_options'] as Map)['line_discount_mode']], ['template1', 1, 'per_unit']);
    expect([f['quote_date'], f['valid_until'], f['validity_days']], [ymd(today), addDaysYmd(ymd(today), 15), 15]);
    expect([f['payment_details'], f['cf_po_required'], f['smownerid']], ['เครดิต 30 วัน', 'PO-77', 1]);
    expect([f['terms_conditions'], f['terms']], ['<p>ราคานี้ยืนราคา 30 วัน</p>', '<p>ราคานี้ยืนราคา 30 วัน</p>'], reason: 'web dual write');
    for (final k in ['quotation_status', 'offer_status', 'grand_total', 'subtotal', 'quotation_no', 'cf_secret']) {
      expect(f.containsKey(k), isFalse, reason: k);
    }
    final lines = (b['lines'] as List).cast<Map>();
    expect(lines, hasLength(2));
    expect([lines[0]['line_no'], lines[0]['product_id'], lines[0]['unit_price'], lines[0]['discount_type'], lines[0]['discount_pct'], lines[0]['tax_pct']], [1, 11, 1000, 'percent', 10, 7]);
    expect([lines[1]['description'], lines[1]['quantity'], lines[1]['unit_price'], lines[1]['discount_type'], lines[1]['discount_amount']], ['ค่าติดตั้ง', 2, 500, 'amount', 50]);
    expect(results.single?['id'], '50');
    expect((await h.prefsNow()).keys.where((k) => k.startsWith('nx.docform.draft.')), isEmpty, reason: 'draft cleared after save');
  });

  testWidgets('draft: leaving mid-way keeps it; coming back offers ทำต่อจากร่าง / เริ่มใหม่', (tester) async {
    final h = DocFormHarness(tester);
    await h.pump(opener('quotation'), qtReplies());
    await h.tap(const ValueKey('open'));
    await h.settle();
    await h.type('title_th', 'งานด่วน ตึก B');
    await tester.pump(const Duration(milliseconds: 500));
    await h.settle(4);
    expect((await h.prefsNow()).keys, contains('nx.docform.draft.1.quotation.new'));
    await h.tap(const ValueKey('docform-close'));
    expect(results.single, isNull);
    expect(find.text('เก็บร่างไว้ในเครื่องแล้ว — เปิดฟอร์มนี้อีกครั้งเพื่อทำต่อ'), findsOneWidget);

    await h.tap(const ValueKey('open'));
    await h.settle();
    expect(find.byKey(const ValueKey('docform-draft-resume')), findsOneWidget);
    await h.tap(const ValueKey('docform-draft-resume'));
    expect(find.text('งานด่วน ตึก B'), findsOneWidget);
    await h.tap(const ValueKey('docform-close'));

    await h.tap(const ValueKey('open'));
    await h.settle();
    await h.tap(const ValueKey('docform-draft-discard'));
    expect(find.text('งานด่วน ตึก B'), findsNothing);
    expect((await h.prefsNow()).keys, isNot(contains('nx.docform.draft.1.quotation.new')));
  });

  testWidgets('permissions: field access (hidden / read-only), customer search only in allowed menus, barcode adds the product', (tester) async {
    final h = DocFormHarness(tester);
    final fields = [
      for (final f in qtFields())
        if (f['name'] == 'customer_taxid') {...f, 'access': 'hidden'} else if (f['name'] == 'title_th') {...f, 'access': 'readonly'} else f,
    ];
    DocFormHooks.scanBarcode = (_) async => 'CAM-01';
    await h.pump(opener('quotation'), qtReplies(fields: fields), menus: const ['quotation', 'account', 'product', 'service']);
    await h.tap(const ValueKey('open'));
    await h.settle();
    expect(find.byKey(const ValueKey('nx-field-customer_taxid')), findsNothing);
    final title = tester.widget<NxFormField>(find.byWidgetPredicate((w) => w is NxFormField && w.name == 'title_th'));
    expect(title.readOnly, isTrue);
    await h.tap(const ValueKey('qt-customer-pick'));
    await tester.enterText(find.byKey(const ValueKey('customer-search')), 'เอ');
    await tester.pump(const Duration(milliseconds: 400));
    await h.settle();
    expect(h.adapter.calls.where((c) => c.path == '/api/entity/account' && c.queryParameters['q'] == 'เอ'), isNotEmpty);
    expect(h.adapter.calls.where((c) => (c.path == '/api/entity/contact' || c.path == '/api/entity/lead') && c.queryParameters['q'] == 'เอ'), isEmpty);
    await h.tap(const ValueKey('customer-hit-account-5'));
    await h.tap(const ValueKey('docform-next'));
    await h.tap(const ValueKey('qt-scan'));
    expect(h.adapter.calls.any((c) => c.path == '/api/entity/product' && c.queryParameters['q'] == 'CAM-01'), isTrue);
    expect(h.textOf(const ValueKey('qline-0-amount')), '฿900.00');
    // Create: later steps open only after the earlier ones.
    await tester.tap(find.byKey(const ValueKey('docform-step-3')));
    await h.settle(2);
    expect(find.byKey(const ValueKey('qt-add-catalog')), findsOneWidget);
  });

  final src = {
    'id': 9, 'quotation_no': 'Q26-0009', 'quotation_status': 'เปิดใบเสนอราคา', 'approval_state': 'approved', 'revision_no': 0,
    'customer_name': 'บริษัท เอ จำกัด', 'related_account_id': 5, 'title_th': 'กล้องวงจรปิด', 'quote_date': '2026-01-05T17:00:00.000Z',
    'validity_days': 10, 'tax_type': 'exclude', 'tax_rate': 7, 'smownerid': 4, 'terms': 'ส่งของ 7 วัน', 'template_key': 'template1', 'template_id': 1,
    'header_discount_type': 'none', 'header_discount_value': 0, 'cf_po_required': 'PO-1', 'grand_total': 4280,
  };
  final srcLines = {
    'list': [
      {'id': 1, 'quotation_id': 9, 'line_no': 1, 'line_type': 'product', 'product_id': 11, 'description': 'กล้อง IP', 'quantity': 4, 'unit_price': 1000, 'discount_type': 'amount', 'discount_amount': 0, 'discount_pct': 0, 'tax_pct': 7, 'line_amount': 4000},
    ],
  };

  testWidgets('ทำซ้ำ: customer + lines + terms copied; number / status / approval cleared; dated today; any step reachable', (tester) async {
    final h = DocFormHarness(tester);
    await h.pump(opener('quotation', mode: DocFormMode.duplicate, id: '9'), {
      ...qtReplies(),
      'GET /api/entity/quotation/9': src,
      'GET /api/quotation/9/lines': srcLines,
    });
    await h.tap(const ValueKey('open'));
    await h.settle();
    expect(find.text('ทำซ้ำใบเสนอราคา'), findsOneWidget);
    await h.tap(const ValueKey('docform-step-3'));
    expect(h.textOf(const ValueKey('qt-sum-customer')), 'บริษัท เอ จำกัด');
    expect(h.textOf(const ValueKey('qt-total-grand')), '฿4,280.00');
    await h.tap(const ValueKey('docform-save'), settleFrames: 10);
    final b = h.body('POST', '/api/quotation/save');
    expect(b.containsKey('id'), isFalse, reason: 'a new quotation');
    final f = Map<String, dynamic>.from(b['fields'] as Map);
    expect([f['title_th'], f['quote_date'], f['related_account_id'], f['smownerid'], f['terms_conditions'], f['cf_po_required']],
        ['กล้องวงจรปิด (Copy)', ymd(thaiNow()), 5, 1, 'ส่งของ 7 วัน', 'PO-1']);
    expect(f['valid_until'], addDaysYmd(ymd(thaiNow()), 10));
    for (final k in ['quotation_no', 'quotation_status', 'approval_state', 'grand_total', 'revision_no']) {
      expect(f.containsKey(k), isFalse, reason: k);
    }
    final line = (b['lines'] as List).single as Map;
    expect([line['product_id'], line['quantity'], line.containsKey('id'), line.containsKey('quotation_id')], [11, 4, false, false]);
  });

  testWidgets('Revise: banner R{n}, changed / new lines highlighted, reason required, exact revise API', (tester) async {
    final h = DocFormHarness(tester);
    await h.pump(opener('quotation', mode: DocFormMode.revise, id: '9'), {
      ...qtReplies(),
      'GET /api/entity/quotation/9': src,
      'GET /api/quotation/9/lines': srcLines,
      'GET /api/quotation/9/revisions': {'list': [{'id': 9, 'revision_no': 0}]},
      'POST /api/quotation/9/revise': {'id': 10, 'quotation_no': 'Q26-0009-R1', 'revision_no': 1},
    });
    await h.tap(const ValueKey('open'));
    await h.settle();
    expect(find.byKey(const ValueKey('docform-revise-banner')), findsOneWidget);
    expect(find.text('ฉบับแก้ไข R1'), findsWidgets);
    expect(h.textOf(const ValueKey('docform-step-missing-3')), '1', reason: 'reason required');
    await h.tap(const ValueKey('docform-step-1'));
    expect(find.byKey(const ValueKey('qline-0-change')), findsNothing);
    await h.type('qline-0-qty', '6');
    expect(find.descendant(of: find.byKey(const ValueKey('qline-0-change')), matching: find.text('แก้ไข')), findsOneWidget);
    await h.tap(const ValueKey('qt-add-text-line'));
    await h.type('qline-1-desc', 'ค่าเดินสาย');
    await h.type('qline-1-price', '1500');
    expect(find.descendant(of: find.byKey(const ValueKey('qline-1-change')), matching: find.text('ใหม่')), findsOneWidget);
    await h.tap(const ValueKey('docform-step-3'));
    await h.tap(const ValueKey('docform-save'));
    expect(h.called('POST', '/api/quotation/9/revise'), isFalse, reason: 'no reason yet');
    expect(find.text('ระบุเหตุผลที่แก้ไขฉบับนี้'), findsOneWidget);
    await h.type('revision_note', 'ลูกค้าขอเพิ่มจำนวนกล้อง');
    await h.tap(const ValueKey('docform-save'), settleFrames: 10);
    final b = h.body('POST', '/api/quotation/9/revise');
    expect(b['revision_note'], 'ลูกค้าขอเพิ่มจำนวนกล้อง');
    final lines = (b['lines'] as List).cast<Map>();
    expect([lines[0]['quantity'], lines[1]['description'], lines[1]['unit_price']], [6, 'ค่าเดินสาย', 1500]);
    final f = Map<String, dynamic>.from(b['fields'] as Map);
    expect([f['title_th'], f['smownerid']], ['กล้องวงจรปิด', 4], reason: 'title / owner kept');
    expect(h.called('POST', '/api/quotation/save'), isFalse);
    expect(results.single?['id'], '10');
  });

  testWidgets('edit: locked statuses offer Revise instead; read-only share disables saving', (tester) async {
    final h = DocFormHarness(tester);
    await h.pump(opener('quotation', mode: DocFormMode.edit, id: '9'), {
      ...qtReplies(),
      'GET /api/entity/quotation/9': {...src, 'quotation_status': 'อนุมัติใบเสนอราคา'},
      'GET /api/quotation/9/lines': srcLines,
    });
    await h.tap(const ValueKey('open'));
    await h.settle();
    expect(find.byKey(const ValueKey('docform-locked')), findsOneWidget);
    await h.tap(const ValueKey('docform-step-3'));
    expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('docform-save'))).onPressed, isNull);
  });

  testWidgets('every entry point lands on the step forms (generic form kept for other modules)', (tester) async {
    final h = DocFormHarness(tester);
    await h.pump(const EntityCreateScreen(module: 'quotation', title: 'สร้างใบเสนอราคา'), qtReplies());
    expect(find.byType(QuotationStepForm), findsOneWidget);
    expect(h.called('GET', '/api/fields/quotation'), isTrue);
    await h.pump(const EntityCreateScreen(module: 'job', title: 'สร้างใบสั่งงาน'), const {});
    expect(find.byType(JobStepForm), findsOneWidget);
    await h.pump(const EntityCreateScreen(module: 'quotation', title: 'x', genericForm: true), qtReplies());
    expect(find.byType(QuotationStepForm), findsNothing);
    // Web form links.
    expect(notificationDeepLink('/modules/quotation/new'), '/form/quotation?mode=create');
    expect(notificationDeepLink('/modules/quotation/new?from=9'), '/form/quotation?mode=duplicate&id=9');
    expect(notificationDeepLink('/modules/quotation/new?revise=9'), '/form/quotation?mode=revise&id=9');
    expect(notificationDeepLink('/modules/job/12/edit'), '/form/job?mode=edit&id=12');
    expect(notificationDeepLink('/modules/quotation/view/9'), '/crm/quotation/9');
  });
}

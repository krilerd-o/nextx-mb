import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/doc_form/doc_form_rules.dart';
import 'package:nextx_mobile/core/doc_form/quotation_math.dart';

Map<String, dynamic> L(Map<String, dynamic> o) => {'line_type': 'product', 'quantity': 1, 'unit_price': 100, ...o};

void main() {
  group('line math = backend quotationLineService.js (quotationPricingParity.unit.test.js cases)', () {
    // Same cases the backend runs against the web's quotationPricing.js.
    final cases = <({String name, List<Map<String, dynamic>> lines, Map<String, dynamic>? header, String taxType, Object? taxRate, Map<String, double> expect})>[
      (name: 'Excel A001/26 (VAT 7%)', lines: [L({'unit_price': 100000}), L({'unit_price': 20000})], header: null, taxType: 'exclude', taxRate: 7, expect: {'subtotal': 120000, 'tax_total': 8400, 'grand_total': 128400}),
      (name: 'VAT 0%', lines: [L({'quantity': 2})], header: null, taxType: 'exclude', taxRate: 0, expect: {'subtotal': 200, 'tax_total': 0, 'grand_total': 200}),
      (name: 'VAT ว่าง = 7', lines: [L({})], header: null, taxType: 'exclude', taxRate: '', expect: {'tax_total': 7, 'grand_total': 107}),
      (name: 'รวม VAT', lines: [L({'unit_price': 107})], header: null, taxType: 'include', taxRate: 7, expect: {'tax_total': 7, 'grand_total': 107}),
      (name: 'ส่วนลดบาท/หน่วย', lines: [L({'quantity': 3, 'discount_type': 'amount', 'discount_amount': 10})], header: null, taxType: 'exclude', taxRate: 7, expect: {'subtotal': 300, 'discount_total': 30}),
      (name: 'ส่วนลด %', lines: [L({'quantity': 2, 'discount_type': 'percent', 'discount_pct': 25})], header: null, taxType: 'exclude', taxRate: 0, expect: {'discount_total': 50, 'grand_total': 150}),
      (name: 'ส่วนลดเกินยอดแถว ไม่กินแถวอื่น', lines: [L({'discount_type': 'amount', 'discount_amount': 150}), L({})], header: null, taxType: 'exclude', taxRate: 0, expect: {'discount_total': 100, 'grand_total': 100}),
      (name: 'ข้อมูลเดิม discount_pct ไม่มี type', lines: [L({'discount_type': null, 'discount_pct': 10})], header: null, taxType: 'exclude', taxRate: 0, expect: {'grand_total': 90}),
      (name: 'หมายเหตุ/ข้อความไม่นับ', lines: [L({}), {'line_type': 'remark', 'quantity': 5, 'unit_price': 999}], header: null, taxType: 'exclude', taxRate: 0, expect: {'subtotal': 100}),
      (name: 'ส่วนลดท้ายบิล %', lines: [L({'quantity': 10})], header: {'type': 'percent', 'value': 10}, taxType: 'exclude', taxRate: 7, expect: {'discount_total': 100, 'tax_total': 63, 'grand_total': 963}),
    ];
    for (final c in cases) {
      test(c.name, () {
        final t = aggregateHeaderTotals(c.lines, headerType: c.header?['type'], headerValue: c.header?['value'], taxType: c.taxType, taxRate: c.taxRate).toMap();
        c.expect.forEach((k, v) => expect(t[k], v, reason: k));
      });
    }

    test('per_line baht discount (business setting) vs per unit', () {
      final l = L({'quantity': 3, 'discount_type': 'amount', 'discount_amount': 10});
      expect(lineAmount(l), 270);
      expect(lineAmount(l, discountMode: 'per_line'), 290);
    });

    test('VAT included with an end-of-bill baht discount + rounding like JS Math.round', () {
      final t = aggregateHeaderTotals([L({'unit_price': 1070}), L({'unit_price': 0.335, 'quantity': 3})], headerType: 'amount', headerValue: 70, taxType: 'include', taxRate: 7);
      // gross 1070 + 1.005 → 1071.01 (rounded per line), bill discount 70 → 1001.01 incl. VAT
      expect(t.subtotal, 1071.01);
      expect(t.grandTotal, 1001.01);
      expect(t.priceBeforeVat, 935.52);
      expect(t.taxTotal, 65.49);
      // Values printed by node from the backend module itself.
      expect([roundMoney(1.005), roundMoney(2.675), roundMoney(-1.005)], [1, 2.68, -1]);
    });

    test('mixed % / baht discounts + 3% end-of-bill (numbers from the backend module)', () {
      final t = aggregateHeaderTotals([
        L({'quantity': 2, 'unit_price': 1234.56, 'discount_type': 'percent', 'discount_pct': 12.5}),
        L({'quantity': 3, 'unit_price': 99.99, 'discount_type': 'amount', 'discount_amount': 5.55}),
      ], headerType: 'percent', headerValue: 3, taxType: 'exclude', taxRate: 7).toMap();
      expect(t, {
        'subtotal': 2769.09, 'discount_total': 398.6, 'total_line_discount': 325.29, 'bill_discount_amount': 73.31,
        'tax_total': 165.93, 'grand_total': 2536.42, 'price_before_vat': 2370.49, 'after_discount': 2370.49,
      });
      final inc = aggregateHeaderTotals([L({'quantity': 3, 'unit_price': 99.99, 'discount_type': 'amount', 'discount_amount': 5.55})], taxType: 'include', taxRate: 7, discountMode: 'per_line');
      expect([inc.subtotal, inc.discountTotal, inc.taxTotal, inc.grandTotal, inc.priceBeforeVat], [299.97, 5.55, 19.26, 294.42, 275.16]);
    });

    test('blank lines are not saved; payload renumbered with only stored columns', () {
      final p = quotationLinesPayload([
        {'line_type': 'text', 'description': '', 'quantity': 1, 'unit_price': 0},
        L({'description': 'A', 'id': 5, 'line_amount': 999, 'discount_type': 'percent', 'discount_pct': '5'}),
      ]);
      expect(p, hasLength(1));
      expect(p.first['line_no'], 1);
      expect(p.first['discount_pct'], 5);
      expect(p.first.containsKey('id'), isFalse);
      expect(p.first.containsKey('line_amount'), isFalse, reason: 'the server computes line_amount');
    });
  });

  group('catalog → line (web mapProductToLine + catalogLinePricing)', () {
    test('discount % with a list price: the line carries the %', () {
      final l = lineFromCatalog({'id': 11, 'product_name_th': 'กล้อง', 'product_initial_price': 1000, 'product_selling_price': 900, 'product_discount': 10, 'product_discount_type': 'percent', 'product_unit': 'ตัว'}, 'product', taxRate: 7);
      expect([l['line_type'], l['product_id'], l['description'], l['unit_price'], l['discount_type'], l['discount_pct'], l['unit'], l['tax_pct']], ['product', 11, 'กล้อง', 1000.0, 'percent', 10.0, 'ตัว', 7.0]);
      expect(lineAmount(l), 900);
    });
    test('no discount: selling price, baht discount 0', () {
      final l = lineFromCatalog({'id': 3, 'service_name_th': 'ล้างแอร์', 'service_selling_price': '1,200'.replaceAll(',', ''), 'service_initial_price': 1500}, 'service');
      expect([l['service_id'], l['unit_price'], l['discount_amount'], l['discount_type']], [3, 1200.0, 0, 'amount']);
    });
  });

  group('customer autofill (web QuotationFormPage accountPatch / contact pick)', () {
    test('account → name, tax id, address, phone; e-mail only when empty', () {
      final p = quotationAccountPatch({
        'id': 5, 'account_name': 'บริษัท เอ', 'account_taxid': '0105555000001', 'address_line1': '1 ถนนสุขุมวิท', 'address_district': 'คลองเตย',
        'address_province': 'กรุงเทพ', 'mobile_1st': '0812345678', 'email_1st': 'a@a.co',
      }, {'customer_email': 'keep@me.co'});
      expect(p, {
        'related_account_id': 5, 'customer_name': 'บริษัท เอ', 'customer_taxid': '0105555000001', 'customer_address': '1 ถนนสุขุมวิท คลองเตย กรุงเทพ',
        'customer_phone': '0812345678', 'customer_email': 'keep@me.co',
      });
    });
    test('contact → contact name / mobile / e-mail; its account id for the account fetch', () {
      final row = {'id': 7, 'contact_firstname': 'สมศรี', 'contact_lastname': 'ใจดี', 'mobile_1st': '0899', 'email_1st': 's@a.co', 'account_id': 5};
      expect(quotationContactPatch(row, const {}), {'related_contact_id': 7, 'contact_name': 'สมศรี ใจดี', 'customer_mobile': '0899', 'customer_email': 's@a.co'});
      expect(contactAccountId(row), '5');
    });
    test('lead → company as customer, person as contact', () {
      final p = quotationLeadPatch({'id': 3, 'lead_firstname': 'ก', 'lead_lastname': 'ข', 'company_name': 'ร้าน ค', 'company_taxid': '123', 'mobile_1st': '08'}, const {});
      expect([p['related_lead_id'], p['customer_name'], p['contact_name'], p['customer_taxid'], p['customer_mobile']], [3, 'ร้าน ค', 'ก ข', '123', '08']);
    });
  });

  group('custom fields → steps', () {
    Map<String, dynamic> f(String name, {String section = 'main', String type = 'Text', bool required = false, String access = 'editable', Object presence = 1, bool readonly = false}) =>
        {'name': name, 'type': type, 'section': section, 'required': required, 'access': access, 'presence': presence, 'readonly': readonly, 'label_th': name};

    test('quotation: known web sections, business sections, names; the rest in ข้อมูลเพิ่มเติม of เงื่อนไข', () {
      final s = DocFormSchema(module: 'quotation', fields: [
        f('customer_name'), // core
        f('quotation_status'), // never asked
        f('grand_total', type: 'Number'), // computed
        f('quotation_ref'), // web identity → step 0
        f('payment_details', type: 'LongText'), // web terms → step 2
        f('cf_site_contact', section: 'ข้อมูลลูกค้าเพิ่มเติม'), // business section → step 0
        f('cf_freight', section: 'ราคาและส่วนลด'), // → step 1
        f('cf_po_required', required: true), // unmapped → step 2 / ข้อมูลเพิ่มเติม
        f('cf_secret', access: 'hidden'),
        f('cf_ro', readonly: true),
        f('cf_off', presence: 0),
      ]);
      ({int step, String group}) at(String n) {
        final e = s.extra.firstWhere((x) => x.field['name'] == n);
        return (step: e.step, group: e.group);
      }

      expect(s.extra.map((e) => e.field['name']), unorderedEquals(['quotation_ref', 'payment_details', 'cf_site_contact', 'cf_freight', 'cf_po_required']));
      expect(at('quotation_ref').step, 0);
      expect(at('payment_details').step, 2);
      expect(at('cf_site_contact'), (step: 0, group: 'ข้อมูลลูกค้าเพิ่มเติม'));
      expect(at('cf_freight').step, 1);
      expect(at('cf_po_required'), (step: 2, group: 'ข้อมูลเพิ่มเติม'));
      expect(validateExtraFields(s.extraFor(2), const {}).keys, ['cf_po_required']);
      expect(validateExtraFields(s.extraFor(2), const {'cf_po_required': 'PO-1'}), isEmpty);
    });

    test('job: schedule-like / user fields to เมื่อไร, address to ลูกค้า, others to รายละเอียด', () {
      final s = DocFormSchema(module: 'job', fields: [
        f('job_name'), f('actual_start', type: 'DateTime'), f('job_status'), f('work_types'),
        f('job_code'), f('contract_po_no'), f('salesperson_user_id', type: 'PicklistUser'), f('problem_found'),
        f('cf_visit_window', type: 'DateTime'), f('cf_gate_code', section: 'สถานที่หน้างาน'), f('cf_misc'),
      ]);
      final steps = {for (final e in s.extra) e.field['name']: e.step};
      // job_code / contract_po_no / salesperson are drawn by the form itself now.
      expect(steps, {'problem_found': 3, 'cf_visit_window': 2, 'cf_gate_code': 1, 'cf_misc': 3});
      expect(s.extra.firstWhere((e) => e.field['name'] == 'problem_found').group, kJobReportGroup);
      for (final n in ['job_code', 'contract_po_no', 'salesperson_user_id']) {
        expect(kCoreFieldStep['job']!.containsKey(n), isTrue, reason: n);
      }
    });

    test('core fields keep business required / readonly / hidden', () {
      final s = DocFormSchema(module: 'quotation', fields: [f('delivery_date', required: true), f('customer_taxid', access: 'hidden'), f('title_th', readonly: true)]);
      expect(s.requires('delivery_date'), isTrue);
      expect(s.requires('smownerid'), isTrue, reason: 'web rule');
      expect(s.hides('customer_taxid'), isTrue);
      expect(s.locks('title_th'), isTrue);
      expect(s.editable('title_th'), isFalse);
    });
  });

  group('document template (web resolveDocTemplate)', () {
    final tpls = [
      {'id': 1, 'layout_key': 'template1', 'layout_json': {'is_default': true}},
      {'id': 2, 'layout_key': 'template2', 'layout_json': {'is_default': true}},
      {'id': 3, 'layout_key': 'template2', 'layout_json': {}},
    ];
    test('create: the allowed default layout + its default template', () {
      expect(resolveDocTemplate(mode: DocFormMode.create, allowedLayouts: ['template2'], defaultLayout: 'template1', templates: tpls), (layout: 'template2', templateId: 2, changed: null));
    });
    test('duplicate: source kept when allowed, else default with a notice', () {
      expect(resolveDocTemplate(mode: DocFormMode.duplicate, layoutKey: 'template2', templateId: 3, allowedLayouts: ['template1', 'template2'], templates: tpls).templateId, 3);
      expect(resolveDocTemplate(mode: DocFormMode.duplicate, layoutKey: 'template2', templateId: 3, allowedLayouts: ['template1'], templates: tpls), (layout: 'template1', templateId: 1, changed: 'layout'));
      expect(resolveDocTemplate(mode: DocFormMode.revise, layoutKey: 'template2', templateId: 99, allowedLayouts: ['template2'], templates: tpls), (layout: 'template2', templateId: 2, changed: 'template'));
    });
    test('edit keeps the saved layout, also when no longer allowed', () {
      expect(layoutChoices(['template1'], 'template2', DocFormMode.edit), ['template1', 'template2']);
      expect(layoutChoices(['template1'], 'template2', DocFormMode.create), ['template1']);
    });
  });

  group('new / duplicate / revise values', () {
    final today = DateTime(2026, 11, 13);
    final ctx = {
      'layouts': {'allowed_layouts': ['template1'], 'default_layout': 'template1', 'line_discount_mode': 'per_line'},
      'new_defaults': {'validity_days': 15, 'payment_details': 'เครดิต 30 วัน', 'tax_type': 'exclude', 'tax_rate': 7},
      'condition_templates': [
        {'id': 'standard', 'is_default': true, 'conditions': [{'th': 'ยืนราคา {validity_days} วัน', 'on': true}], 'payment': []},
      ],
      'templates': [{'id': 1, 'layout_key': 'template1', 'layout_json': {'is_default': true}}],
    };
    test('create: owner me, today, business new-quotation defaults, valid until +validity days, no status', () {
      final v = quotationCreateValues(userId: '1', today: today, ctx: ctx);
      expect(v.containsKey('quotation_status'), isFalse);
      expect([v['smownerid'], v['quote_date'], v['valid_until'], v['payment_details'], v['template_key'], v['template_id']], [1, '2026-11-13', '2026-11-28', 'เครดิต 30 วัน', 'template1', 1]);
      expect((v['document_options'] as Map)['line_discount_mode'], 'per_line');
      expect(((v['document_options'] as Map)['conditions'] as Map)['template_id'], 'standard');
    });
    test('create without business validity days: +30 days', () {
      expect(quotationCreateValues(userId: '1', today: today)['valid_until'], '2026-12-13');
    });
    test('ทำซ้ำ: customer + terms kept; number / status / approval / outcome cleared; today; (Copy)', () {
      final src = {
        'id': 9, 'quotation_no': 'Q-9', 'quotation_status': 'อนุมัติใบเสนอราคา', 'approval_state': 'approved', 'offer_status': 'รอใบสั่งซื้อ',
        'outcome_result': 'Won', 'customer_name': 'บริษัท เอ', 'related_account_id': 5, 'title_th': 'งาน A', 'quote_date': '2026-01-01',
        'validity_days': 10, 'terms': 'เงื่อนไข', 'smownerid': 4, 'grand_total': 99, 'template_key': 'template1', 'template_id': 1,
      };
      final v = quotationDuplicateValues(src, userId: '1', today: today, ctx: ctx);
      for (final k in ['id', 'quotation_no', 'quotation_status', 'approval_state', 'offer_status', 'outcome_result', 'grand_total']) {
        expect(v.containsKey(k), isFalse, reason: k);
      }
      expect([v['customer_name'], v['related_account_id'], v['title_th'], v['quote_date'], v['valid_until'], v['terms_conditions'], v['smownerid']],
          ['บริษัท เอ', 5, 'งาน A (Copy)', '2026-11-13', '2026-11-23', 'เงื่อนไข', 1]);
    });
    test('revise: title / owner kept, next number previewed', () {
      final src = {'id': 9, 'quotation_no': 'Q-9-R1', 'revision_no': 1, 'title_th': 'งาน A', 'smownerid': 4};
      final v = quotationReviseValues(src);
      expect([v['title_th'], v['smownerid'], v.containsKey('quotation_no')], ['งาน A', 4, false]);
      final n = nextRevisionNo(src, [{'revision_no': 2}]);
      expect(n, 3);
      expect(revisionNumberPreview(src, n), 'Q-9-R3');
    });
    test('revise diff: same / changed / added / removed', () {
      final prev = [L({'product_id': 1, 'description': 'A'}), L({'product_id': 2, 'description': 'B'}), L({'line_type': 'text', 'description': 'C'})];
      final cur = [L({'product_id': 1, 'description': 'A'}), L({'product_id': 2, 'description': 'B', 'quantity': 5}), L({'product_id': 9, 'description': 'N'})];
      final d = diffRevisionLines(prev, cur);
      expect(d.changes, [RevisionLineChange.same, RevisionLineChange.changed, RevisionLineChange.added]);
      expect(d.removed.single['description'], 'C');
    });
  });

  group('job rules', () {
    test('prefill from a case = the server createJobFromCase body', () {
      final v = jobPrefillFrom('case', {'id': 12, 'case_name': 'แอร์ไม่เย็น', 'case_priority': 'High', 'related_account_id': 5, 'related_contact_id': 7, 'account_name': 'บริษัท เอ', 'due_datetime': '2026-11-20 17:00:00', 'smownerid': 3});
      expect(v, {
        'job_name': 'Request — แอร์ไม่เย็น', 'job_type': 'request', 'job_priority': 'High', 'source': 'case', 'related_case_id': 12,
        'related_account_id': 5, 'related_contact_id': 7, 'customer_name': 'บริษัท เอ', 'due_datetime': '2026-11-20 17:00:00',
        'deliverable_template': 'request_report', 'smownerid': 3,
      });
      expect(jobParentOf(v), 'case');
    });
    test('prefill from a contract / quotation', () {
      expect(jobPrefillFrom('service_contract', {'id': 4, 'contract_no': 'SC-4', 'end_date': '2027-01-01'})['job_name'], 'Service — SC-4');
      final q = jobPrefillFrom('quotation', {'id': 9, 'quotation_no': 'Q-9', 'customer_name': 'บริษัท เอ', 'po_reference': 'PO1'}, linesSummary: '• กล้อง × 2 ตัว');
      expect([q['job_name'], q['related_quotation_id'], q['description']], ['Q-9 — บริษัท เอ', 9, 'อ้างอิงใบเสนอราคา Q-9 · PO: PO1\n\n• กล้อง × 2 ตัว']);
      expect(quotationLinesSummary([{'line_type': 'product', 'description': '<b>กล้อง</b>', 'quantity': 2, 'unit': 'ตัว'}, {'line_type': 'text', 'description': 'หมายเหตุ'}]), '• กล้อง × 2 ตัว\nหมายเหตุ');
    });
    test('ทำซ้ำ job: customer / place / people / details copied; owner = me (web); dates, status, signatures cleared', () {
      final v = jobDuplicateValues({
        'id': 1, 'job_no': 'JOB-1', 'job_status': 'Completed', 'job_name': 'ล้างแอร์', 'related_account_id': 5, 'site_address_snapshot': 'กทม',
        'description': 'ล้าง 3 เครื่อง', 'plan_start': '2026-11-01 09:00:00', 'plan_end': '2026-11-01 11:00:00', 'actual_start': 'x', 'smownerid': 3,
        'engineer_user_id': 4, 'customer_signature': 'sig', 'related_activity_id': 9, 'acknowledgement_note': 'รับทราบ',
      }, userId: '7');
      expect([v['job_name'], v['related_account_id'], v['site_address_snapshot'], v['description'], v['smownerid'], v['engineer_user_id']],
          ['ล้างแอร์ (Copy)', 5, 'กทม', 'ล้าง 3 เครื่อง', 7, 4]);
      for (final k in ['id', 'job_no', 'job_status', 'plan_start', 'plan_end', 'actual_start', 'customer_signature', 'related_activity_id', 'acknowledgement_note']) {
        expect(v.containsKey(k), isFalse, reason: k);
      }
    });
    test('quick slots: พรุ่งนี้เช้า 09:00–11:00, จันทร์หน้า', () {
      final s = jobQuickSlots(DateTime(2026, 11, 13, 15, 20)); // Friday afternoon
      final m = {for (final x in s) x.key: x};
      expect(m.containsKey('today_pm'), isFalse);
      expect([m['tomorrow_am']!.start, m['tomorrow_am']!.end], [DateTime(2026, 11, 14, 9), DateTime(2026, 11, 14, 11)]);
      expect(m['next_monday']!.start, DateTime(2026, 11, 16, 9));
      expect(wallDateTime(m['in1h']!.start), '2026-11-13T16:00:00');
    });
  });
}

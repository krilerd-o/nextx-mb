import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/doc_form/doc_form_rules.dart';
import 'package:nextx_mobile/core/doc_form/job_form_rules.dart';
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/screens/doc_form/job_pickers.dart';

import 'support/r86_quote_fake.dart' show fakeAccounts;
import 'support/r89_job_fake.dart';

void main() {
  group('scheduler (Bangkok wall clock)', () {
    test('one Thai line: day, Buddhist year, start–end; several days; English', () {
      final s = DateTime(2026, 11, 20, 9), e = DateTime(2026, 11, 20, 12);
      expect(jobWhenSummary(s, e), 'ศ. 20 พ.ย. 2569 · 09:00–12:00');
      expect(jobWhenSummary(s, null), 'ศ. 20 พ.ย. 2569 · 09:00');
      expect(jobWhenSummary(s, DateTime(2026, 11, 21, 12)), 'ศ. 20 พ.ย. 09:00 – ส. 21 พ.ย. 2569 12:00');
      expect(jobWhenSummary(DateTime(2026, 12, 31, 22), DateTime(2027, 1, 1, 2)), 'พฤ. 31 ธ.ค. 2569 22:00 – ศ. 1 ม.ค. 2570 02:00');
      expect(jobWhenSummary(s, e, en: true), 'Fri 20 Nov 2026 · 09:00–12:00');
      expect(jobWhenSummary(null, e), '');
      expect(jobDayLabel(DateTime(2026, 11, 22)), 'อา. 22 พ.ย. 2569');
    });

    test('length text, moving the start keeps the length, a new day keeps the time', () {
      expect(jobDurationText(const Duration(hours: 3)), '3 ชม.');
      expect(jobDurationText(const Duration(minutes: 90)), '1 ชม. 30 นาที');
      expect(jobDurationText(const Duration(minutes: 45)), '45 นาที');
      expect(jobDurationText(const Duration(hours: 26)), '1 วัน 2 ชม.');
      expect(jobDurationText(Duration.zero), '');
      final m = jobMoveStart(DateTime(2026, 11, 20, 9), DateTime(2026, 11, 20, 12), DateTime(2026, 11, 21, 13));
      expect([m.start, m.end], [DateTime(2026, 11, 21, 13), DateTime(2026, 11, 21, 16)]);
      final first = jobMoveStart(null, null, DateTime(2026, 11, 20, 9));
      expect(first.end, DateTime(2026, 11, 20, 11), reason: 'default 2 hours');
      final bad = jobMoveStart(DateTime(2026, 11, 20, 9), DateTime(2026, 11, 20, 8), DateTime(2026, 11, 20, 10));
      expect(bad.end, DateTime(2026, 11, 20, 12), reason: 'an end before the start is not a length');
      expect(jobOnDay(DateTime(2026, 11, 20, 14, 30), DateTime(2026, 12, 1)), DateTime(2026, 12, 1, 14, 30));
      expect(jobOnDay(null, DateTime(2026, 12, 1)), DateTime(2026, 12, 1, 9));
      expect(jobAtTime(DateTime(2026, 12, 1, 9), 13, 15), DateTime(2026, 12, 1, 13, 15));
      expect(wallDateTime(DateTime(2026, 12, 1, 13, 15)), '2026-12-01T13:15:00', reason: 'no zone: the server stores Bangkok wall clock');
    });

    test('quick slots and due choices from Thai now (a UTC device clock is shifted +7)', () {
      // 23:30 UTC on the 13th is 06:30 on the 14th in Bangkok.
      final now = toThai(DateTime.utc(2026, 11, 13, 23, 30));
      expect(now, DateTime(2026, 11, 14, 6, 30));
      final slots = {for (final s in jobQuickSlots(now)) s.key: s};
      expect(slots['tomorrow_am']!.start, DateTime(2026, 11, 15, 9));
      expect(slots['today_pm']!.start, DateTime(2026, 11, 14, 13));
      expect(slots['next_monday']!.start, DateTime(2026, 11, 16, 9));
      final due = {for (final d in jobDueQuick(now, planEnd: DateTime(2026, 11, 15, 12))) d.key: d.at};
      expect(due, {
        'plan_end': DateTime(2026, 11, 15, 12),
        'today': DateTime(2026, 11, 14, 17),
        'tomorrow': DateTime(2026, 11, 15, 17),
        'd3': DateTime(2026, 11, 17, 17),
        'd7': DateTime(2026, 11, 21, 17),
      });
      expect(jobDueQuick(DateTime(2026, 11, 14, 18)).map((d) => d.key), isNot(contains('today')), reason: 'after 17:00 no "today"');
    });
  });

  group('technicians', () {
    test('who is free: overlaps clash, same-day appointments counted, cancelled ignored', () {
      final a = technicianAvailability(fakeActivities, DateTime(2026, 11, 20, 9), DateTime(2026, 11, 20, 12));
      expect([a['3']!.clashes, a['3']!.free], [1, false]);
      expect([a['4']!.clashes, a['4']!.sameDay, a['4']!.free], [0, 1, true]);
      expect(a.containsKey('2'), isFalse, reason: 'cancelled');
      expect(a.containsKey('1'), isFalse, reason: 'another day');
      final pm = technicianAvailability(fakeActivities, DateTime(2026, 11, 20, 14, 30), DateTime(2026, 11, 20, 16));
      expect([pm['4']!.free, pm['3']!.free], [false, true]);
    });

    test('skill match from {required, candidates}; user names / phones', () {
      final m = technicianSkillMatch({
        'required': [{'skill_id': 1}],
        'candidates': [{'user_id': 4, 'matched_skills': 2, 'required_skills': 2}, {'user_id': 3, 'matched_skills': 1, 'required_skills': 2}],
      });
      expect([m['4'], m['3']], [(matched: 2, required: 2), (matched: 1, required: 2)]);
      expect(technicianSkillMatch({'required': [], 'candidates': []}), isEmpty);
      expect(jobUserName({'first_name': 'เอก', 'last_name': 'ทองดี'}), 'เอก ทองดี');
      expect(jobUserName({'label': 'วิภา'}), 'วิภา');
      expect(userPhoneOf({'phone_work': '02'}), '02');
    });
  });

  group('links, labels, site', () {
    test('case / contract cards: number · title, customer, status, due / end', () {
      final c = jobLinkView('case', fakeCases.first);
      expect([c.heading, c.customer, c.status, c.extra, c.closed], ['CS-0012 · แอร์ไม่เย็น ห้องประชุม 3', 'บริษัท สยามเทค โซลูชั่น จำกัด', 'เปิดเคส', 'กำหนด 20/11/2569', false]);
      expect(jobLinkView('case', fakeCases[2]).closed, isTrue);
      final k = jobLinkView('service_contract', fakeContracts[1]);
      expect([k.heading, k.status, k.extra, k.closed], ['SC-2025-008 · MA เครือข่าย 2025', 'หมดอายุ', 'สิ้นสุด 31/12/2568', true]);
    });

    test('linking fills only the blanks', () {
      final p = jobLinkPatch('case', fakeCases.first, {'job_name': 'ของฉัน'});
      expect(p, {'related_case_id': 12, 'related_account_id': 5, 'customer_name': 'บริษัท สยามเทค โซลูชั่น จำกัด', 'related_contact_id': 71, 'due_datetime': '2026-11-20 17:00:00'});
      final q = jobLinkPatch('service_contract', fakeContracts.first, {'related_account_id': 6, 'due_datetime': 'x'});
      expect(q, {'related_contract_id': 4, 'job_name': 'Service — MA ระบบแอร์รายปี 2026'});
    });

    test('field labels: the column notes are never shown; job_category is the report work category', () {
      expect(jobFieldLabel('site_address_snapshot'), 'ที่อยู่หน้างาน');
      expect(jobFieldLabel('location_name_snapshot'), 'ชื่อสถานที่');
      expect(jobFieldLabel('job_category'), 'ลักษณะงาน');
      expect(jobFieldLabel('job_code'), 'รหัสอ้างอิงงาน');
      expect(kJobFieldLabels.values.where((l) => l.contains('snapshot') || l.contains('(เอกสาร)')), isEmpty);
      final pl = {for (final e in realJobPicklists.entries) e.key: [for (final o in e.value as List) Map<String, dynamic>.from(o as Map)]};
      expect(jobChoices('job_category', pl, kJobCategoryFallback).map((c) => c.label).first, 'ติดตั้ง');
      expect(jobChoices('job_category', pl, kJobCategoryFallback, en: true).map((c) => c.label).first, 'Installation');
      expect(jobChoices('job_type', const {}, kJobTypeFallback).first.help, contains('งานบริการ'));
      // The real schema: report fields fold into one group of the last step; sign-off / cycle counters are not asked.
      final s = DocFormSchema(module: 'job', fields: realJobFields);
      final names = {for (final e in s.extra) e.field['name']: (e.step, e.group)};
      expect(names['problem_found'], (3, kJobReportGroup));
      expect(names['cf_gate_code'], (1, 'สถานที่หน้างาน'));
      for (final n in ['job_category', 'job_code', 'in_warranty', 'assign_group', 'salesperson_name', 'warranty_cycle_index', 'acknowledgement_note', 'technician_signed_by_name']) {
        expect(names.containsKey(n), isFalse, reason: n);
      }
    });

    test('site address: pin coordinates appended / read back; account address sets; Thai parts', () {
      final a = siteAddressWithPin('99 พระราม 9', 13.75, 100.5);
      expect(a, '99 พระราม 9 (13.750000,100.500000)');
      expect(siteAddressWithPin(a, 14, 101), '99 พระราม 9 (14.000000,101.000000)', reason: 'one pin, replaced');
      expect(siteCoordsOf(a), (lat: 13.75, lng: 100.5));
      expect(siteAddressText(a), '99 พระราม 9');
      expect(siteCoordsOf('ไม่มีพิกัด'), isNull);
      expect(composeThaiAddress(line: '1/2', subdistrict: 'คลองตัน', district: 'คลองเตย', province: 'กรุงเทพมหานคร', postal: '10110'), '1/2 คลองตัน คลองเตย กรุงเทพมหานคร 10110');
      final sets = accountSiteAddresses({
        ...fakeAccounts.first,
        'bill_address_line1': '1 สาทร', 'bill_address_district': 'สาทร', 'bill_address_province': 'กรุงเทพมหานคร',
      });
      expect(sets, [('ที่อยู่หลักของลูกค้า', '99/9 ถนนพระราม 9 ห้วยขวาง กรุงเทพมหานคร'), ('ที่อยู่ออกบิล', '1 สาทร สาทร กรุงเทพมหานคร')]);
    });
  });
}

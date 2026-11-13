import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/i18n_en.dart';
import 'package:nextx_mobile/core/menu_groups.dart';
import 'package:nextx_mobile/core/shell_tabs.dart';

void main() {
  test('bottom-bar tab is "ผู้มุ่งหวัง" (the web\'s nav.lead), not "ลีด/ดีล"', () {
    final t = shellTabById('leads')!;
    expect(t.label, 'ผู้มุ่งหวัง');
    // The tab opens the lead list only.
    expect(t.anyMenu, ['lead']);
    for (final def in shellTabCatalog) {
      expect(def.label, isNot(contains('ลีด')), reason: def.id);
      expect(def.description, isNot(contains('ลีด')), reason: def.id);
    }
    for (final r in workRoles) {
      expect(r.description, isNot(contains('ลีด')), reason: r.id);
    }
    // Deal stays "ดีล" — it genuinely is a deal.
    final sales = kMenuGroups.firstWhere((g) => g.id == 'sales');
    expect(sales.sections.first.items.firstWhere((i) => i.id == 'deal').title, 'ดีล');
  });

  test('menu names follow the NEXTX web labels (th.js nav.*)', () {
    final titles = {
      for (final g in kMenuGroups)
        for (final s in g.sections)
          for (final i in s.items) i.id: i.title,
    };
    // id → web label
    const web = {
      'workspace': 'เวิร์กสเปซ', // nav.workspace
      'approvals': 'รออนุมัติของฉัน', // nav.approvals
      'calendar': 'ปฏิทิน', // nav.calendar
      'lead': 'ผู้มุ่งหวัง', // nav.lead
      'account': 'บัญชีลูกค้า', // nav.account
      'contact': 'ผู้ติดต่อ', // nav.contact
      'deal': 'ดีล', // nav.deal
      'quotation': 'ใบเสนอราคา', // nav.quotation
      'case': 'เคส', // nav.case
      'job': 'ใบสั่งงาน', // nav.job
      'inspection': 'ใบตรวจรับ', // nav.inspection
      'service-contract': 'สัญญาบริการ', // nav.serviceContract
      'mail': 'กล่องจดหมาย', // nav.mailbox
      'call-log': 'บันทึกการโทร', // nav.callLog
      'chat': 'แชททีม', // nav.communityChat
      'comm-ai': 'ประวัติ AI การสนทนา', // nav.commAiHistory
      'comm-ai-insights': 'แดชบอร์ดไอแซค การสื่อสาร', // nav.commAiInsights (ISAAC → ไอแซค in Thai)
      'hr': 'HR', // nav.hrDashboard
      'attendance': 'ลงเวลาเข้า-ออก', // nav.attendance
      'leave': 'ขอลา', // nav.leaveRequest
      'attendance-report': 'รายงานลงเวลา', // nav.attendanceReport
      'product': 'สินค้า',
      'service-item': 'บริการ',
      'asset': 'สินทรัพย์',
      'service-location': 'พื้นที่บริการ',
      'skill': 'ทักษะ',
      'files': 'จัดการไฟล์', // nav.fileManager
    };
    for (final e in web.entries) {
      expect(titles[e.key], e.value, reason: e.key);
    }
    // Group titles = web rail titles.
    expect([for (final g in kMenuGroups) g.title], ['งานของฉัน', 'ลูกค้า', 'งานขาย', 'งานบริการ', 'สื่อสาร', 'ไอแซคเอไอ', 'แอปอื่น']);
  });

  test('every renamed label has an English string', () {
    final labels = <String>{
      for (final t in shellTabCatalog) ...[t.label, t.description],
      for (final r in workRoles) r.description,
      for (final g in kMenuGroups)
        for (final s in g.sections)
          for (final i in s.items) i.title,
    };
    for (final l in labels) {
      if (!RegExp(r'[฀-๿]').hasMatch(l)) continue;
      expect(enStrings.containsKey(l), isTrue, reason: l);
    }
    expect(enStrings.containsKey('ลีด/ดีล'), isFalse);
  });
}

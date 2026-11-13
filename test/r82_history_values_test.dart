// R82 — history values: JSON-quoted dates show as Thai date/time (Asia/Bangkok),
// signature image paths read as "ลงลายเซ็น…", never a raw path.
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/history_events.dart';
import 'package:nextx_mobile/core/i18n.dart';

HistoryLine change(String field, String label, Object? from, Object? to, {String module = 'job'}) => describeHistoryEvent(
      {'type': 'field_change', 'field_name': field, 'field_label_th': label, 'old_value': from, 'new_value': to},
      module: module,
    );

void main() {
  tearDown(() => L10n.set('th'));

  test('a JSON-quoted UTC instant shows as a Thai date and Bangkok time', () {
    final l = change('technician_signed_at', 'เวลาเซ็นช่าง', null, '"2026-11-13T11:48:36.000Z"');
    expect(l.title, 'แก้ไข เวลาเซ็นช่าง');
    expect(l.detail, '— → 13/11/2569 18:48');
    expect(l.detail, isNot(contains('"')));
    expect(l.detail, isNot(contains('T11')));
  });

  test('plain quoted text loses the quotes', () {
    expect(change('technician_signer_name', 'ชื่อผู้เซ็น (ช่าง)', null, '"Krilerd Oit"').detail, '— → Krilerd Oit');
  });

  test('signature image path: "ลงลายเซ็นช่าง", no path; changed / removed too', () {
    final added = change('technician_signature', 'ลายเซ็นช่าง', null, 'signatures/sig_2_1794570515772.png');
    expect(added.title, 'ลงลายเซ็นช่าง');
    expect(added.kind, HistoryKind.sign);
    expect(added.detail, isNull);
    expect(change('customer_signature', 'ลายเซ็นลูกค้า', 'signatures/a.png', 'signatures/b.png').title, 'เปลี่ยนลายเซ็นลูกค้า');
    final removed = change('customer_signature', 'ลายเซ็นลูกค้า', 'signatures/a.png', '');
    expect(removed.title, 'ลบลายเซ็นลูกค้า');
    expect(removed.kind, HistoryKind.delete);
  });

  test('other uploaded files show the file name, not the folder', () {
    expect(change('attachment', 'ไฟล์แนบ', null, 'uploads/jobs/37/report final.pdf').detail, isNot(contains('uploads/')));
    expect(change('cover', 'รูปปก', null, 'covers/7/p.jpg').detail, '— → ไฟล์ p.jpg');
  });

  test('English', () {
    L10n.set('en');
    expect(change('technician_signed_at', 'เวลาเซ็นช่าง', null, '"2026-11-13T11:48:36.000Z"').detail, '— → 13/11/2026 18:48');
    expect(change('technician_signature', 'ลายเซ็นช่าง', null, 'signatures/s.png').title, startsWith('Added '));
  });
}

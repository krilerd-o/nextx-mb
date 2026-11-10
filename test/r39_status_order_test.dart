import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_parts.dart';

void main() {
  const opts = [
    (value: 'Active', label: 'ใช้งาน'),
    (value: 'Inactive', label: 'ไม่ใช้งาน'),
    (value: 'Draft', label: 'ฉบับร่าง'),
    (value: 'Discontinued', label: 'เลิกผลิต'),
  ];
  test('product / service: draft first, others keep their order', () {
    for (final m in ['product', 'service']) {
      expect(orderStatusOptions(m, opts).map((o) => o.value), ['Draft', 'Active', 'Inactive', 'Discontinued']);
    }
  });
  test('other modules unchanged', () {
    expect(orderStatusOptions('deal', opts).map((o) => o.value), ['Active', 'Inactive', 'Draft', 'Discontinued']);
  });
}

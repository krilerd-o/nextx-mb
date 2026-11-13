import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/home_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('saved order is kept; new sections slot in; hidden respected', () async {
    SharedPreferences.setMockInitialValues({
      'nx_home_layout_u1': '{"order":["sales","today","quick"],"hidden":["ai"]}',
    });
    final h = HomeLayout.instance;
    await h.load('u1');
    // ไอแซคแนะนำ (id `ai`) goes on top once; the rest keeps the saved order.
    expect(h.order.take(2), ['ai', 'sales']);
    expect(h.order.toSet(), HomeLayout.defaultOrder.toSet());
    await h.save('u1', ['pending', ...HomeLayout.defaultOrder.where((k) => k != 'pending')], {});
    await h.load('u2'); // another user: defaults
    expect(h.order, HomeLayout.defaultOrder);
  });

  test('default Home order: ไอแซคแนะนำ · ลงเวลา · งานวันนี้ · งานค้าง · ทางลัด · เปิดล่าสุด · ยอดขาย · เคส · ภาพรวม', () {
    expect(HomeLayout.defaultOrder.take(9), [
      'ai',
      'today',
      'work',
      'pending',
      'quick',
      'recent',
      'sales',
      'cases',
      'stats',
    ]);
    expect(HomeLayout.sections.keys.toSet(), HomeLayout.defaultOrder.toSet());
    expect(
      [for (final k in HomeLayout.defaultOrder.take(9)) HomeLayout.sections[k]!.$1],
      ['ไอแซคแนะนำ', 'ลงเวลา', 'งานวันนี้', 'งานค้าง', 'ทางลัด', 'เปิดล่าสุด', 'ยอดขาย', 'เคส', 'ภาพรวม'],
    );
  });
}

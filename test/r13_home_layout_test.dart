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
    expect(h.order.first, 'sales');
    expect(h.order.toSet(), HomeLayout.defaultOrder.toSet());
    expect(h.visibleOrder.contains('ai'), isFalse);
    await h.save('u1', ['pending', ...HomeLayout.defaultOrder.where((k) => k != 'pending')], {});
    await h.load('u2'); // another user: defaults
    expect(h.order, HomeLayout.defaultOrder);
  });
}

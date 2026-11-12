import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/session_state.dart';

void main() {
  test('menus null after loading = unrestricted (same as the web: no Package / no role limit)', () {
    const s = SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true);
    expect(s.canAccess('lead'), isTrue);
    expect(s.canAccess('hr-dashboard'), isTrue);
  });

  test('a list limits to its keys; an empty list allows nothing', () {
    const only = SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true, menuKeys: ['lead']);
    expect(only.canAccess('lead'), isTrue);
    expect(only.canAccess('case'), isFalse);
    const none = SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true, menuKeys: []);
    expect(none.canAccess('lead'), isFalse);
  });

  test('before menus load nothing gated shows; superadmin sees everything', () {
    const loading = SessionState(accessToken: 't', userId: '1', businessId: '1');
    expect(loading.canAccess('lead'), isFalse);
    const sa = SessionState(accessToken: 't', userId: '1', businessId: '1', isSuperadmin: true, menuKeys: []);
    expect(sa.canAccess('case'), isTrue);
  });
}

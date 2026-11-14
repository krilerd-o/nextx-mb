import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/widgets/nx_app_header.dart';

import 'support/fake_api.dart';

Future<AppConfig> _config(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final config = AppConfig();
  // Let the constructor's saved-settings load finish first (it would reset the picture).
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  config.debugOverrideSession(const SessionState(accessToken: 't', userId: '7', businessId: '1', displayName: 'QA User', menusLoaded: true));
  config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({}));
  return config;
}

void main() {
  testWidgets('avatar URL is built like the web (uploads path, absolute URL kept, empty = none)', (tester) async {
    final c = await _config(tester);
    expect(c.profileAvatarUrl, isNull);
    expect(c.profileAvatarImage, isNull);

    c.debugSetProfileImagename('avatars/a b.png');
    expect(c.profileAvatarUrl, endsWith('/uploads/avatars/a%20b.png'));
    // Disk-cached network provider (was a plain NetworkImage), the same object on every read.
    expect(c.profileAvatarImage, isA<CachedNetworkImageProvider>());
    expect(identical(c.profileAvatarImage, c.profileAvatarImage), isTrue, reason: 'memoized: no new image key per rebuild');

    c.debugSetProfileImagename('/uploads/avatars/x.jpg');
    expect(c.profileAvatarUrl, endsWith('/uploads/avatars/x.jpg'));
    expect(c.profileAvatarUrl, isNot(contains('uploads/uploads')));

    c.debugSetProfileImagename('https://cdn.example.com/avatars/7/x.jpg');
    expect(c.profileAvatarUrl, 'https://cdn.example.com/avatars/7/x.jpg');

    c.debugSetProfileImagename('null');
    expect(c.profileAvatarUrl, isNull);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('header / Home avatar shows the server picture instead of initials', (tester) async {
    final c = await _config(tester);
    c.debugSetProfileImagename('avatars/me.png');
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: c,
      child: const MaterialApp(home: Scaffold(body: Center(child: NxHubAvatar(size: 46, ring: true)))),
    ));
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    // Decoded at the shown size (46 × dpr), not the photo's full resolution.
    final sized = avatar.backgroundImage! as ResizeImage;
    expect(sized.width, (46 * tester.view.devicePixelRatio).round());
    expect((sized.imageProvider as CachedNetworkImageProvider).url, endsWith('/uploads/avatars/me.png'));
    expect(avatar.child, isNull, reason: 'no initials when there is a picture');

    c.debugSetProfileImagename(null);
    await tester.pump();
    expect(tester.widget<CircleAvatar>(find.byType(CircleAvatar)).child, isNotNull, reason: 'initials without a picture');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}

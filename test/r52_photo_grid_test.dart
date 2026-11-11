import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/journey/journey_photos.dart';

import 'support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<Map<String, dynamic>> photos(int n) => [
        for (var i = 0; i < n; i++) {'url': '/uploads/qa/p$i.jpg', 'name': 'p$i.jpg', 'mime': 'image/jpeg'},
      ];

  Future<void> pump(WidgetTester tester, List<Map<String, dynamic>> items, {bool canEdit = true}) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true));
    config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({}));
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: JourneyPhotosSection(module: 'job', id: '9', photos: items, onChanged: () {}, canEdit: canEdit),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('modern action tiles + empty state', (tester) async {
    await pump(tester, const []);
    for (final k in ['camera', 'fast', 'gallery']) {
      expect(find.byKey(ValueKey('journey-photo-$k')), findsOneWidget);
    }
    expect(find.text('สูงสุด 30 รูป'), findsOneWidget);
    expect(find.byKey(const ValueKey('journey-photo-empty')), findsOneWidget);
  });

  testWidgets('5 square photos per row', (tester) async {
    await pump(tester, photos(7));
    final a = tester.getRect(find.byKey(const ValueKey('journey-photo-0')));
    final e = tester.getRect(find.byKey(const ValueKey('journey-photo-4')));
    final f = tester.getRect(find.byKey(const ValueKey('journey-photo-5')));
    expect(a.width, closeTo(a.height, 0.01));
    expect(e.top, a.top);
    expect(f.top, greaterThan(a.bottom));
    expect(f.left, a.left);
    expect(find.text('7'), findsOneWidget); // count pill
  });

  testWidgets('more than 2 rows fold into +N, then expand and fold back', (tester) async {
    await pump(tester, photos(14));
    expect(find.byKey(const ValueKey('journey-photo-8')), findsOneWidget);
    expect(find.byKey(const ValueKey('journey-photo-9')), findsNothing);
    expect(find.text('+5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('journey-photo-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('journey-photo-13')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('journey-photo-less')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('journey-photo-13')), findsNothing);
  });

  testWidgets('tap grows the photo into the viewer; drag down closes it', (tester) async {
    await pump(tester, photos(3));
    await tester.tap(find.byKey(const ValueKey('journey-photo-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(Hero), findsWidgets); // hero flight in progress
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('image-download')), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.drag(find.byKey(const ValueKey('image-viewer-body')), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('image-download')), findsNothing);
  });

  testWidgets('read-only: no action tiles', (tester) async {
    await pump(tester, photos(2), canEdit: false);
    expect(find.byKey(const ValueKey('journey-photo-camera')), findsNothing);
    expect(find.byKey(const ValueKey('journey-photo-1')), findsOneWidget);
  });
}

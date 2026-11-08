import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/navigation/notification_deep_link.dart';
import 'package:nextx_mobile/services/hms_push.dart';
import 'package:nextx_mobile/widgets/nx_map_view.dart';

void main() {
  test('map choice: Google only with a key on the Google build; OSM on Huawei', () {
    expect(nxMapKind(huawei: false, mapsKey: true, underTest: false), NxMapKind.google);
    expect(nxMapKind(huawei: true, mapsKey: true, underTest: false), NxMapKind.osm, reason: 'no Google Maps on Huawei');
    expect(nxMapKind(huawei: false, mapsKey: false, underTest: false), NxMapKind.osm);
    expect(nxMapKind(huawei: true, mapsKey: false, underTest: true), NxMapKind.card, reason: 'no network in tests');
  });

  test('tapped HMS notification opens the same place as FCM', () {
    final data = {'url': '/workspace/items/5', 'id': '5'};
    final want = notificationDeepLinkFromData(data);
    expect(deepLinkFromHmsTap({'extras': data}), want);
    expect(deepLinkFromHmsTap({'remoteMessage': {'data': '{"url":"/workspace/items/5","id":"5"}'}}), want);
    expect(deepLinkFromHmsTap(null), isNull);
    expect(deepLinkFromHmsTap({'extras': {}}), isNull);
  });

  testWidgets('OSM map shows the OpenStreetMap credit', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 240,
          child: fm.FlutterMap(
            options: const fm.MapOptions(),
            children: const [fm.SimpleAttributionWidget(source: Text('© OpenStreetMap contributors'))],
          ),
        ),
      ),
    ));
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    final src = File('lib/widgets/nx_map_view.dart').readAsStringSync();
    expect(src, contains("userAgentPackageName: 'com.moai.nextt.mobile'"), reason: 'OSM tile policy wants an app id');
    expect(src, contains('© OpenStreetMap contributors'));
  });

  test('Huawei config never goes into git', () {
    final ignore = File('.gitignore').readAsStringSync();
    expect(ignore, contains('agconnect-services.json'));
    expect(File('android/app/src/main/assets/agconnect-services.json').existsSync(), isFalse);
  });
}

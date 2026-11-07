import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'core/detail_fields_pref.dart';
import 'package:provider/provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'core/app_alice.dart';
import 'core/app_config.dart';
import 'core/effects.dart';
import 'core/app_version.dart';
import 'core/error_reporting.dart';
import 'services/api_client.dart';
import 'services/device_push_service.dart';
import 'app.dart';

void main() {
  ErrorReporting.runGuarded(() async {
    await AppVersion.load();
    if (!kIsWeb) Effects.setCoreCounter(() => Platform.numberOfProcessors);
    await Effects.init();
    await DetailFieldsPref.load();
    await _initDeviceHeaders();
    await initFirebasePush();
    initAppAlice();
    runApp(
      ChangeNotifierProvider(
        create: (_) => AppConfig(),
        child: const NextXMobileApp(),
      ),
    );
  });
}

/// Device name / platform / version for the server's device list.
Future<void> _initDeviceHeaders() async {
  var name = '';
  var platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
  try {
    final info = DeviceInfoPlugin();
    if (kIsWeb) {
      final w = await info.webBrowserInfo;
      name = w.browserName.name;
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      final a = await info.androidInfo;
      name = '${a.manufacturer} ${a.model}'.trim();
      platform = 'android';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final i = await info.iosInfo;
      name = i.name.isNotEmpty ? i.name : i.utsname.machine;
      platform = 'ios';
    }
  } catch (_) {}
  ApiClient.deviceHeaders = {
    if (name.isNotEmpty) 'X-Device-Name': Uri.encodeComponent(name),
    'X-Device-Platform': platform,
    'X-App-Version': AppVersion.value,
  };
}

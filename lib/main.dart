import 'dart:async';
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
import 'services/calls/call_setup.dart';
import 'services/hms_push.dart';
import 'widgets/nx_overlay_panel.dart' show NxTapTracker;

void main() {
  ErrorReporting.runGuarded(() async {
    if (!kIsWeb) Effects.setCoreCounter(() => Platform.numberOfProcessors);
    // Independent startup reads side by side (each was awaited in turn before).
    final device = _readDevice();
    await Future.wait([
      AppVersion.load(),
      DetailFieldsPref.load(),
      device.then((d) => Effects.init(specs: d.specs)),
    ]);
    _applyDeviceHeaders(await device);
    initAppAlice();
    // Voice / video calls (WebRTC + CallKit / full-screen incoming call).
    initCalls();
    // Menus grow out of the button that opened them (see showNxBlurPanel).
    NxTapTracker.ensure();
    runApp(
      ChangeNotifierProvider(
        create: (_) => AppConfig(),
        child: const NextXMobileApp(),
      ),
    );
    // Push SDKs after the first frame: Firebase / HMS start-up is not needed to draw the
    // app. A notification that launched the app is still handled: its location goes to
    // PushNavigation, which the router listens to, and DevicePushService.sync waits for
    // this same init before asking for a token.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(initFirebasePush());
      unawaited(HmsPush.init());
    });
  });
}

class _Device {
  const _Device({this.name = '', required this.platform, this.specs});
  final String name;
  final String platform;
  final DeviceSpecs? specs;
}

/// Device name / platform for the server's device list, and the specs the
/// "auto" effects level looks at (RAM, Android version) — one platform call.
Future<_Device> _readDevice() async {
  var name = '';
  var platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
  DeviceSpecs? specs;
  int cores() {
    try {
      return kIsWeb ? 0 : Platform.numberOfProcessors;
    } catch (_) {
      return 0;
    }
  }

  try {
    final info = DeviceInfoPlugin();
    if (kIsWeb) {
      final w = await info.webBrowserInfo;
      name = w.browserName.name;
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      final a = await info.androidInfo;
      name = '${a.manufacturer} ${a.model}'.trim();
      platform = 'android';
      specs = DeviceSpecs(cores: cores(), ramMb: a.physicalRamSize, androidSdk: a.version.sdkInt, lowRam: a.isLowRamDevice);
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final i = await info.iosInfo;
      name = i.name.isNotEmpty ? i.name : i.utsname.machine;
      platform = 'ios';
      specs = DeviceSpecs(cores: cores(), ramMb: i.physicalRamSize);
    }
  } catch (_) {}
  return _Device(name: name, platform: platform, specs: specs);
}

void _applyDeviceHeaders(_Device d) {
  ApiClient.deviceHeaders = {
    if (d.name.isNotEmpty) 'X-Device-Name': Uri.encodeComponent(d.name),
    'X-Device-Platform': d.platform,
    'X-App-Version': AppVersion.value,
  };
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app_alice.dart';
import 'core/app_config.dart';
import 'core/app_version.dart';
import 'core/error_reporting.dart';
import 'services/device_push_service.dart';
import 'app.dart';

void main() {
  ErrorReporting.runGuarded(() async {
    await AppVersion.load();
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

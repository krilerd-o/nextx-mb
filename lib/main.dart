import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app_alice.dart';
import 'core/app_config.dart';
import 'services/device_push_service.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initFirebasePush();
  initAppAlice();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppConfig(),
      child: const NextXMobileApp(),
    ),
  );
}

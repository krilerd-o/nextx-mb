import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/app.dart';
import 'package:nextx_mobile/core/app_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('NextXMobileApp builds', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppConfig(),
        child: const NextXMobileApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

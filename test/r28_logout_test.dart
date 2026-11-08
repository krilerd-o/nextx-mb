import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/widgets/nx_logout.dart';

void main() {
  Future<AppConfig> pump(WidgetTester tester, Brightness b) async {
    SharedPreferences.setMockInitialValues({});
    final config = AppConfig();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: NxLogoutButton(onPressed: () async {
                final ok = await confirmNxLogout(context, config);
                if (context.mounted) (ScaffoldMessenger.of(context)..hideCurrentSnackBar()).showSnackBar(SnackBar(content: Text('result=$ok')));
              }),
            ),
          ),
        ),
      ),
    ));
    return config;
  }

  testWidgets('dark theme: readable light red, not the dark error colour', (tester) async {
    await pump(tester, Brightness.dark);
    final ctx = tester.element(find.byKey(const ValueKey('nx-logout-button')));
    expect(nxDangerColor(ctx), const Color(0xFFFF8A8A));
    expect(find.text('ออกจากระบบ'), findsOneWidget);
  });

  testWidgets('tap → confirm dialog says data stays and you can sign back in; cancel keeps you in', (tester) async {
    await pump(tester, Brightness.light);
    await tester.tap(find.byKey(const ValueKey('nx-logout-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nx-logout-dialog')), findsOneWidget);
    expect(find.text('ออกจากระบบใช่ไหม?'), findsOneWidget);
    expect(find.textContaining('กลับมาเข้าสู่ระบบได้อีกครั้ง'), findsOneWidget);
    expect(find.textContaining('ไม่มีอะไรถูกลบ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nx-logout-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('result=false'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nx-logout-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nx-logout-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('result=true'), findsOneWidget);
  });
}

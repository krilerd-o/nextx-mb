import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/entity_list_screen.dart';
import 'package:nextx_mobile/widgets/nx_tip_banner.dart';

import 'support/fake_api.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NxTipBanner colours', () {
    for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
      testWidgets('$name: readable text on the banner', (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: const Scaffold(body: NxTipBanner(key: ValueKey('tip'), text: 'กดค้างที่รายการเพื่อดูคำสั่ง')),
        ));
        final text = tester.widget<Text>(find.text('กดค้างที่รายการเพื่อดูคำสั่ง'));
        final fg = text.style!.color!;
        final bg = NxTipBanner.background(theme);
        expect(fg, theme.colorScheme.onSurface);
        // WCAG AA for normal text.
        expect(_contrast(fg, bg), greaterThan(4.5), reason: '$name contrast');
        if (theme.brightness == Brightness.light) {
          expect(fg.computeLuminance(), lessThan(0.2), reason: 'light theme must not use white text');
        } else {
          expect(fg.computeLuminance(), greaterThan(0.5));
        }
      });
    }

    test('light theme onPrimaryContainer is dark (was white on a pale container)', () {
      final cs = AppTheme.light.colorScheme;
      expect(_contrast(cs.onPrimaryContainer, cs.primaryContainer), greaterThan(4.5));
      final dark = AppTheme.dark.colorScheme;
      expect(_contrast(dark.onPrimaryContainer, dark.primaryContainer), greaterThan(3));
    });
  });

  testWidgets('entity list tip is full width — same width as the list cards', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const row = {'id': 5, 'lead_no': 'LD-1', 'lead_name': '[QA] ลูกค้า R65', 'lead_status': 'New'};
    final adapter = FakeNextxAdapter({
      'GET /api/modules': [],
      'GET /api/customviews': {'list': [], 'default_id': null},
      'GET /api/fields/lead': {
        'list': [
          {'name': 'lead_name', 'label_th': 'ชื่อ'},
        ],
      },
      'GET /api/entity/lead': {'list': [row], 'total': 1},
      'GET /api/customviews/meta': {'users': [], 'date_fields': [], 'period_presets': []},
    });
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(theme: AppTheme.light, home: const EntityListScreen(module: 'lead', title: '[QA] รายการ')),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final tip = find.byKey(const ValueKey('crm-row-hint'));
    expect(tip, findsOneWidget);
    expect(tester.widget(tip), isA<NxTipBanner>());
    final card = find.byKey(const ValueKey('row-lead-5'));
    expect(card, findsOneWidget);
    final tipRect = tester.getRect(tip);
    final cardRect = tester.getRect(card);
    expect(tipRect.left, cardRect.left);
    expect(tipRect.width, cardRect.width);
  });
}

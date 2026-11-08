import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/auth_redirect.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/ui_font.dart';
import 'package:nextx_mobile/screens/workspace/task_detail_screen.dart' show taskDateOnly;
import 'package:nextx_mobile/widgets/fields/field_ui_type.dart';
import 'package:nextx_mobile/widgets/fields/nx_entity_form.dart';
import 'package:nextx_mobile/widgets/nx_appearance_controls.dart';
import 'package:nextx_mobile/widgets/nx_ui_scale.dart';
import 'package:nextx_mobile/widgets/nx_workspace_switcher.dart';

import 'support/fake_api.dart';

Future<AppConfig> _config(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final config = AppConfig();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  return config;
}

void main() {
  group('fonts like the web', () {
    test('6 fonts, default Google Sans, Thai fallback', () {
      expect(kUiFonts.map((f) => f.id), [
        'google_sans', 'ibm_plex_sans_thai', 'noto_sans_thai', 'sarabun', 'bai_jamjuree', 'maitree',
      ]);
      expect(resolveUiFontId(null), 'google_sans');
      expect(resolveUiFontId('nope'), 'google_sans');
      expect(uiFontFallback('GoogleSans').first, 'IBMPlexSansThai');
      final t = AppTheme.themed(brightness: Brightness.light, family: 'Sarabun');
      expect(t.textTheme.bodyMedium?.fontFamily, 'Sarabun');
      expect(t.textTheme.titleLarge?.fontFamily, 'Sarabun');
    });

    testWidgets('picking a font applies it and is kept on this device', (tester) async {
      final config = await _config(tester);
      expect(config.uiFontId, 'google_sans');
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: config,
        child: MaterialApp(
          home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => showUiFontPicker(c), child: const Text('open')))),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ui-font-sarabun')));
      await tester.pump();
      expect(config.uiFontId, 'sarabun');
      expect(config.uiFontFamily, 'Sarabun');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ui_font'), 'sarabun');
      await tester.pump(const Duration(minutes: 2));
    });
  });

  group('screen scale', () {
    test('steps and default 95%', () {
      expect(kUiScales, [0.9, 0.95, 1.0, 1.05, 1.1]);
      expect(resolveUiScale(null), 0.95);
      expect(resolveUiScale(0.33), 0.95);
      expect(NxUiScale.densityFor(0.9), lessThan(0));
      expect(NxUiScale.densityFor(1.1), greaterThan(0));
    });

    testWidgets('scales text on top of the phone setting', (tester) async {
      late double seen;
      await tester.pumpWidget(MaterialApp(
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.2)),
          child: NxUiScale(scale: 0.9, child: child!),
        ),
        home: Builder(builder: (c) {
          seen = MediaQuery.textScalerOf(c).scale(10);
          return const SizedBox();
        }),
      ));
      expect(seen, closeTo(10 * 1.2 * 0.9, 0.001));
    });

    testWidgets('slider changes the scale', (tester) async {
      final config = await _config(tester);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: config,
        child: const MaterialApp(home: Scaffold(body: Padding(padding: EdgeInsets.all(16), child: NxUiScaleControl()))),
      ));
      final slider = find.byKey(const ValueKey('ui-scale-slider'));
      await tester.tapAt(tester.getTopRight(slider) - const Offset(30, -20));
      await tester.pump();
      expect(config.uiScale, greaterThan(0.95));
      await tester.tap(find.byKey(const ValueKey('ui-scale-reset')));
      await tester.pump();
      expect(config.uiScale, 0.95);
      await tester.pump(const Duration(minutes: 2));
    });
  });

  group('Google sign-in deep link', () {
    testWidgets('the same link is handled once (no endless loop)', (tester) async {
      final config = await _config(tester);
      final r = parseAuthRedirect('moainext://app/login?merge_intent=abc')!;
      var notifies = 0;
      config.addListener(() => notifies++);
      for (var i = 0; i < 5; i++) {
        config.handleAuthDeepLink(r);
        await tester.pump();
      }
      expect(config.takePendingGoogleMerge(), 'abc');
      final before = notifies;
      config.handleAuthDeepLink(r);
      await tester.pump();
      expect(notifies, before, reason: 'a repeat of the same link must do nothing');
      expect(config.hasPendingGoogleMerge, isFalse);
      await tester.pump(const Duration(minutes: 2));
    });
  });

  group('switch business inside the sheet', () {
    testWidgets('change business → back returns; nothing is cleared, no logout', (tester) async {
      final config = await _config(tester);
      config.debugOverrideSession(const SessionState(
        accessToken: 't', userId: '2', businessId: '1', businessName: '[QA] One', packageCode: 'crm', menusLoaded: true,
      ));
      config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({
        'GET /api/businesses/1/packages': [
          {'id': 11, 'code': 'crm', 'name': 'CRM', 'enabled': true},
          {'id': 12, 'code': 'fsm', 'name': 'FSM', 'enabled': true},
        ],
        'GET /api/businesses/2/packages': [
          {'id': 21, 'code': 'crm', 'name': 'CRM', 'enabled': true},
          {'id': 22, 'code': 'hr', 'name': 'HR', 'enabled': true},
        ],
        'GET /api/me/businesses': [
          {'id': 1, 'business_name': '[QA] One'},
          {'id': 2, 'business_name': '[QA] Two'},
        ],
      }));
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: config,
        child: const MaterialApp(home: Scaffold(body: Center(child: NxWorkspaceSwitcher()))),
      ));
      await tester.tap(find.text('[QA] One · CRM'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pkg-change-business')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('biz-2')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('biz-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pkg-hr')), findsOneWidget);
      // Still the old business while only browsing.
      expect(config.session.businessId, '1');
      await tester.tap(find.byKey(const ValueKey('pkg-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('biz-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pkg-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pkg-fsm')), findsOneWidget);
      expect(config.isLoggedIn, isTrue);
      expect(config.session.businessId, '1');
      expect(config.session.packageCode, 'crm');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 2));
    });
  });

  group('dates and birthday in forms', () {
    test('birthday / legacy date fields are date pickers', () {
      expect(resolveFieldUiType({'name': 'birthdate'}), FieldUiType.date);
      expect(resolveFieldUiType({'name': 'contact_person_birthdate', 'type': 'text'}), FieldUiType.date);
      expect(resolveFieldUiType({'name': 'x', 'uitype': 5}), FieldUiType.date);
      expect(resolveFieldUiType({'name': 'x', 'uitype': '70'}), FieldUiType.dateTime);
      expect(resolveFieldUiType({'name': 'x', 'typeofdata': 'D~O'}), FieldUiType.date);
      expect(resolveFieldUiType({'name': 'firstname'}), FieldUiType.text);
      expect(isBirthdayFieldName('lastname'), isFalse);
    });

    test('edit / duplicate values in Thai time', () {
      final fields = [
        {'name': 'birthdate', 'type': 'date'},
        {'name': 'lead_datetime', 'type': 'datetime'},
        {'name': 'open_date', 'type': 'date'},
      ];
      final v = <String, dynamic>{
        'birthdate': '1990-11-09T17:00:00.000Z',
        'lead_datetime': '2026-11-08T03:30:00.000Z',
        'open_date': '2026-11-10',
      };
      normalizeFormDates(fields, v);
      expect(v['birthdate'], '1990-11-10');
      expect(v['open_date'], '2026-11-10');
      // *_datetime is a wall-clock column: the digits already are Thai time.
      expect(v['lead_datetime'], '2026-11-08T03:30:00');
      expect(collectEntityPayload(fields, v)['birthdate'], '1990-11-10');
    });

    test('workspace dates use the Thai day', () {
      expect(taskDateOnly('2026-11-05T17:00:00.000Z'), '2026-11-06');
      expect(taskDateOnly('2026-11-06T00:00:00.000Z'), '2026-11-06');
      expect(taskDateOnly('2026-11-06'), '2026-11-06');
      expect(taskDateOnly(''), isNull);
    });
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/ai_consent.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/i18n.dart';
import 'package:nextx_mobile/core/legal_links.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/auth/login_screen.dart';
import 'package:nextx_mobile/screens/profile/privacy_ai_screen.dart';
import 'package:nextx_mobile/widgets/ai_consent_gate.dart';

import 'support/fake_api.dart';

const _session = SessionState(accessToken: 't', userId: '7', businessId: '1', displayName: 'QA', menusLoaded: true, menuKeys: ['lead']);

Future<(AppConfig, FakeNextxAdapter)> _pump(WidgetTester tester, Widget home, {Map<String, dynamic> replies = const {}, SessionState? session = _session}) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig();
  if (session != null) config.debugOverrideSession(session);
  final adapter = FakeNextxAdapter(replies);
  config.apiClient.debugSetHttpAdapter(adapter);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: home)));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  if (session != null) config.debugOverrideSession(session);
  await tester.pump();
  return (config, adapter);
}

void main() {
  final opened = <Uri>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AiConsent.debugAssumeGranted = false;
    AiConsent.instance.debugReset();
    opened.clear();
    legalLauncher = (u) async {
      opened.add(u);
      return true;
    };
  });
  tearDown(() => AiConsent.debugAssumeGranted = true);

  test('legal pages: one fixed site, English adds ?lang=en', () {
    expect(legalUri(LegalPage.privacy).toString(), 'https://moainext.moai-crm.com/privacy');
    expect(legalUri(LegalPage.accountDeletion).toString(), 'https://moainext.moai-crm.com/account-deletion');
    L10n.locale.value = 'en';
    addTearDown(() => L10n.locale.value = 'th');
    expect(legalUri(LegalPage.terms).toString(), 'https://moainext.moai-crm.com/terms?lang=en');
  });

  testWidgets('AI screens: consent page first; "allow" opens the screen and is remembered per user', (tester) async {
    await _pump(tester, const AiConsentGate(child: Text('AI SCREEN')));
    expect(find.byKey(const ValueKey('ai-consent-page')), findsOneWidget);
    expect(find.text('AI SCREEN'), findsNothing);
    expect(find.textContaining('OpenAI, Anthropic'), findsOneWidget, reason: 'says who receives the data');
    await tester.tap(find.byKey(const ValueKey('ai-consent-privacy')));
    expect(opened.single.path, '/privacy');
    await tester.tap(find.byKey(const ValueKey('ai-consent-accept')));
    await tester.pumpAndSettle();
    expect(find.text('AI SCREEN'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ai_consent_v1_7'), startsWith('granted@'));
    // Another user on the same phone is asked again.
    AiConsent.instance.debugReset();
    expect(await AiConsent.instance.isGranted('8'), isFalse);
    expect(await AiConsent.instance.isGranted('7'), isTrue);
  });

  testWidgets('AI screens: "not now" keeps AI off and goes back', (tester) async {
    await _pump(tester, Builder(builder: (context) {
      return Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AiConsentGate(child: Text('AI SCREEN')))),
          child: const Text('open'),
        ),
      );
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-consent-decline')));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.text('AI SCREEN'), findsNothing);
    expect(await AiConsent.instance.isGranted('7'), isFalse);
  });

  testWidgets('ensureAiConsent asks in a sheet once; afterwards it does not ask again', (tester) async {
    final results = <bool>[];
    await _pump(tester, Builder(builder: (context) {
      return Scaffold(body: TextButton(onPressed: () async => results.add(await ensureAiConsent(context)), child: const Text('ask')));
    }));
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-consent-accept')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-consent-accept')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-consent-accept')), findsNothing);
    expect(results, [true, true]);
  });

  testWidgets('Profile → ความเป็นส่วนตัวและ AI: switch, documents, delete my meeting data / recordings', (tester) async {
    final (_, api) = await _pump(tester, const PrivacyAiScreen(), replies: {
      'DELETE /api/ai/minutes/me/data': {'meetings': 2, 'lines': 5, 'chat': 1},
      'DELETE /api/comm-ai/me/notebook-recordings': {'recordings': 3},
    });
    await tester.pumpAndSettle();
    final sw = find.byKey(const ValueKey('privacy-ai-switch'));
    expect(tester.widget<Switch>(sw).value, isFalse);
    await tester.tap(sw);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-consent-accept')));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(sw).value, isTrue);
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(sw).value, isFalse, reason: 'turning it off needs no confirmation');

    for (final k in ['privacy-open-policy', 'privacy-open-terms', 'privacy-open-deletion']) {
      await tester.tap(find.byKey(ValueKey(k)));
    }
    expect(opened.map((u) => u.path), ['/privacy', '/terms', '/account-deletion']);

    await tester.tap(find.byKey(const ValueKey('privacy-delete-meetings')));
    await tester.pumpAndSettle();
    expect(api.callKeys.where((k) => k.startsWith('DELETE')), isEmpty, reason: 'asks first');
    await tester.tap(find.byKey(const ValueKey('delete-confirm')));
    await tester.pumpAndSettle();
    expect(api.callKeys, contains('DELETE /api/ai/minutes/me/data'));
    await tester.tap(find.byKey(const ValueKey('privacy-delete-recordings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-confirm')));
    await tester.pumpAndSettle();
    expect(api.callKeys, contains('DELETE /api/comm-ai/me/notebook-recordings'));
    expect(find.text('ลบบันทึกเสียงแล้ว 3 รายการ'), findsOneWidget);
  });

  testWidgets('sign-in screen links the privacy policy and terms', (tester) async {
    await _pump(tester, const LoginScreen(), session: null);
    await tester.ensureVisible(find.byKey(const ValueKey('login-privacy')));
    await tester.tap(find.byKey(const ValueKey('login-privacy')));
    await tester.tap(find.byKey(const ValueKey('login-terms')));
    expect(opened.map((u) => u.path), ['/privacy', '/terms']);
  });

  test('iOS asks for location only while in use (no "always" keys; geolocator\'s always request compiled out)', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('NSLocationWhenInUseUsageDescription'));
    expect(plist, isNot(contains('NSLocationAlways')));
    for (final f in ['ios/Runner/th.lproj/InfoPlist.strings', 'ios/Runner/en.lproj/InfoPlist.strings']) {
      expect(File(f).readAsStringSync(), isNot(contains('NSLocationAlways')), reason: f);
    }
    expect(File('ios/Podfile').readAsStringSync(), contains('BYPASS_PERMISSION_LOCATION_ALWAYS=1'));
  });
}

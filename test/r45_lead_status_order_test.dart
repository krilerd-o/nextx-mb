import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_parts.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';

import 'support/fake_api.dart';

/// Picklist as it comes from nextx_qa (raw order, legacy aliases mixed in).
const _raw = [
  (value: 'New', label: 'ใหม่'),
  (value: 'Contacted', label: 'ติดต่อแล้ว'),
  (value: 'Qualified', label: 'มีศักยภาพ'),
  (value: 'Unqualified', label: 'ไม่มีศักยภาพ'),
  (value: 'Converted', label: 'แปลงเป็นลูกค้าแล้ว'),
  (value: 'Potentials', label: 'มีโอกาส'),
  (value: 'No Potentials', label: 'ไม่มีโอกาส'),
  (value: 'Wait for Convert', label: 'รอแปลง'),
  (value: 'Case', label: 'เคส'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lead steps follow the web funnel, aliases merged, Converted last', () {
    final o = orderStatusOptions('lead', _raw, current: 'New');
    expect(o.map((e) => e.value), ['New', 'Contacted', 'Qualified', 'Unqualified', 'Converted']);
    expect(o.map((e) => e.label), ['ใหม่', 'ติดต่อแล้ว', 'มีศักยภาพ', 'ไม่มีศักยภาพ', 'แปลงเป็นลูกค้าแล้ว']);
  });

  test('picklist order does not matter; Converted is added when missing', () {
    final shuffled = [_raw[4], _raw[2], _raw[0], _raw[3], _raw[1]];
    expect(orderStatusOptions('lead', shuffled).map((e) => e.value), kLeadStatusFunnel);
    final noConverted = [_raw[0], _raw[1]];
    expect(orderStatusOptions('lead', noConverted).last.value, 'Converted');
  });

  test('legacy current values map onto the standard step', () {
    expect(canonicalLeadStatus('Potentials'), 'Qualified');
    expect(canonicalLeadStatus('Wait for Convert'), 'Contacted');
    expect(canonicalLeadStatus('แปลงแล้ว'), 'Converted');
    expect(statusCurrent('lead', 'No Potentials'), 'Unqualified');
    expect(statusCurrent('deal', 'No Potentials'), 'No Potentials');
    expect(isLeadConvertedStatus('converted'), isTrue);
  });

  test('other modules keep their order (product: draft first)', () {
    const p = [(value: 'Active', label: 'ใช้งาน'), (value: 'Draft', label: 'ฉบับร่าง')];
    expect(orderStatusOptions('product', p).first.value, 'Draft');
    const d = [(value: 'B', label: 'B'), (value: 'A', label: 'A')];
    expect(orderStatusOptions('deal', d).map((e) => e.value), ['B', 'A']);
  });

  Future<void> pumpLead(WidgetTester tester, Map<String, Object?> lead) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final adapter = FakeNextxAdapter({
      'GET /api/entity/lead/9': lead,
      'GET /api/entity/lead/9/comments': {'list': []},
      'GET /api/entity/lead/9/tags': {'list': []},
      'GET /api/tags': {'list': []},
      'GET /api/users': {'list': []},
      'GET /api/fields/lead': {
        'list': [
          {'name': 'lead_name', 'label_th': 'ชื่อ'},
          {'name': 'lead_status', 'label_th': 'สถานะ', 'uitype': '15'},
        ],
        'picklists': {
          'lead_status': [for (final o in _raw) {'value': o.value, 'label': o.label}],
        },
      },
    });
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(home: EntityDetailScreen(key: UniqueKey(), module: 'lead', row: const {'id': 9})),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('converted lead: Converted is the last step and current, all before it passed', (tester) async {
    await pumpLead(tester, {'id': 9, 'lead_name': '[QA] R45', 'lead_status': 'Converted', 'convert_account_id': 31});
    final steps = tester.widget<EntityStatusStepper>(find.byType(EntityStatusStepper));
    expect(steps.options.map((e) => e.value), kLeadStatusFunnel);
    expect(steps.current, 'Converted');
    expect(steps.onSelect, isNull, reason: 'converted lead is read-only');
    for (final v in ['New', 'Contacted', 'Qualified', 'Unqualified']) {
      expect(find.byKey(ValueKey('step-done-$v')), findsOneWidget, reason: v);
    }
  });

  testWidgets('legacy "Potentials" shows as the Qualified step', (tester) async {
    await pumpLead(tester, {'id': 9, 'lead_name': '[QA] R45', 'lead_status': 'Potentials'});
    final steps = tester.widget<EntityStatusStepper>(find.byType(EntityStatusStepper));
    expect(steps.options.map((e) => e.value), kLeadStatusFunnel);
    expect(steps.current, 'Qualified');
    expect(find.byKey(const ValueKey('step-done-Contacted')), findsOneWidget);
  });
}

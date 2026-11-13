import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_list_screen.dart';
import 'package:nextx_mobile/widgets/nx_confirm_sheet.dart';

import 'support/fake_api.dart';

/// R66 — confirm before every status change, and after swiping list cards.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> launches;

  setUp(() {
    launches = [];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'), (c) async {
      launches.add(c);
      return true;
    });
  });

  Future<void> settle(WidgetTester tester, [int frames = 14]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('showStatusChangeConfirm', () {
    Future<Future<NxStatusConfirm?>> open(WidgetTester tester, {bool requireReason = false, String to = 'ผ่านเกณฑ์'}) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }))));
      final f = showStatusChangeConfirm(
        ctx,
        recordTitle: '[QA] ลูกค้า R66',
        from: 'ใหม่',
        fromColor: Colors.grey,
        to: to,
        toColor: const Color(0xFF16A34A),
        impact: '[QA] ผลกระทบ',
        requireReason: requireReason,
        reasons: requireReason ? const ['ราคาสูง', 'ไม่ตรงความต้องการ'] : const [],
      );
      await settle(tester);
      return f;
    }

    testWidgets('shows record, current → new chips and the impact; cancel returns null', (tester) async {
      final f = await open(tester);
      expect(find.text('เปลี่ยนสถานะ?'), findsOneWidget);
      expect(find.text('[QA] ลูกค้า R66'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('status-from')), matching: find.text('ใหม่')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('status-to')), matching: find.text('ผ่านเกณฑ์')), findsOneWidget);
      expect(find.text('[QA] ผลกระทบ'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('status-confirm-cancel')));
      await settle(tester);
      expect(await f, isNull);
      expect(find.text('เปลี่ยนสถานะ?'), findsNothing);
    });

    testWidgets('confirm button takes the new status colour; red for destructive', (tester) async {
      var f = await open(tester);
      Color? bg(WidgetTester t) => t.widget<FilledButton>(find.byKey(const ValueKey('status-confirm-ok'))).style?.backgroundColor?.resolve({});
      expect(bg(tester), const Color(0xFF16A34A));
      await tester.tap(find.byKey(const ValueKey('status-confirm-ok')));
      await settle(tester);
      expect(await f, isNotNull);

      f = await open(tester, to: 'Closed Lost');
      expect(bg(tester), kNxDangerRed);
      await tester.tap(find.byKey(const ValueKey('status-confirm-cancel')));
      await settle(tester);
      expect(await f, isNull);
    });

    testWidgets('required reason: confirm is off until a reason chip is picked', (tester) async {
      final f = await open(tester, requireReason: true, to: 'แพ้');
      FilledButton ok() => tester.widget<FilledButton>(find.byKey(const ValueKey('status-confirm-ok')));
      expect(ok().onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('status-reason-1')));
      await settle(tester, 4);
      expect(ok().onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('status-confirm-ok')));
      await settle(tester);
      expect((await f)?.note, 'ไม่ตรงความต้องการ');
    });
  });

  group('list (lead)', () {
    Map<String, Object?> schema() => {
          'list': [
            {'name': 'lead_name', 'label_th': 'ชื่อ'},
            {'name': 'lead_status', 'label_th': 'สถานะ', 'uitype': '15'},
          ],
          'picklists': {
            'lead_status': [
              {'value': 'New', 'label': '[QA] ใหม่'},
              {'value': 'Qualified', 'label': '[QA] ผ่านเกณฑ์'},
            ],
          },
        };

    const lead = {
      'id': 5,
      'lead_no': 'LD-R66',
      'lead_name': '[QA] ลูกค้า R66',
      'lead_status': 'New',
      'mobile_1st': '0811111111',
      'phone': '022222222',
    };

    Future<FakeNextxAdapter> pumpList(WidgetTester tester, {Map<String, dynamic> row = lead}) async {
      SharedPreferences.setMockInitialValues({'nx_crm_row_actions_hint_v1': true});
      final adapter = FakeNextxAdapter({
        'GET /api/modules': [],
        'GET /api/customviews': {'list': [], 'default_id': null},
        'GET /api/customviews/meta': {'users': [], 'date_fields': [], 'period_presets': []},
        'GET /api/fields/lead': schema(),
        'GET /api/entity/lead': {'list': [row], 'total': 1},
        'GET /api/entity/lead/5': row,
        'PUT /api/entity/lead/5': {'id': 5},
        'DELETE /api/entity/lead/5': {'ok': true},
      });
      final config = AppConfig();
      config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead']));
      config.apiClient.debugSetHttpAdapter(adapter);
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: config,
        child: const MaterialApp(home: EntityListScreen(module: 'lead', title: '[QA] รายการ')),
      ));
      await settle(tester, 12);
      return adapter;
    }

    List<String> puts(FakeNextxAdapter a) => [for (final c in a.calls) if (c.method == 'PUT') '${c.data}'];

    testWidgets('status from the long-press menu: cancel keeps it, confirm saves + snackbar', (tester) async {
      final a = await pumpList(tester);
      Future<void> pick() async {
        await tester.longPress(find.textContaining('[QA] ลูกค้า R66').first);
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('row-act-status')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('status-opt-Qualified')));
        await settle(tester);
      }

      await pick();
      expect(find.text('เปลี่ยนสถานะ?'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('status-to')), matching: find.text('[QA] ผ่านเกณฑ์')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('status-confirm-cancel')));
      await settle(tester);
      expect(puts(a), isEmpty);

      await pick();
      await tester.tap(find.byKey(const ValueKey('status-confirm-ok')));
      await settle(tester);
      expect(puts(a), ['{lead_status: Qualified}']);
      expect(find.textContaining('เปลี่ยนสถานะแล้ว'), findsOneWidget);
      expect(find.text('เลิกทำ'), findsOneWidget);
    });

    testWidgets('swipe right = call: asks first, lets the user pick a number; cancel snaps back', (tester) async {
      final a = await pumpList(tester);
      final card = find.textContaining('[QA] ลูกค้า R66').first;
      await tester.fling(card, const Offset(400, 0), 1500);
      await settle(tester);
      expect(find.text('โทรหา [QA] ลูกค้า R66?'), findsOneWidget);
      expect(find.text('0811111111'), findsOneWidget);
      expect(find.text('022222222'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('status-confirm-cancel')));
      await settle(tester, 20);
      expect(launches, isEmpty);
      expect(find.byKey(const ValueKey('row-lead-5')), findsOneWidget, reason: 'the card is back');
      expect(a.callKeys.where((k) => k.startsWith('DELETE')), isEmpty);

      await tester.fling(find.textContaining('[QA] ลูกค้า R66').first, const Offset(400, 0), 1500);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('call-number-1')));
      await settle(tester, 4);
      await tester.tap(find.byKey(const ValueKey('call-confirm')));
      await settle(tester, 20);
      expect(launches, hasLength(1));
      expect('${launches.single.arguments}', contains('tel:022222222'));
      expect(find.textContaining('[QA] ลูกค้า R66'), findsWidgets, reason: 'calling never removes the card');
    });

    testWidgets('swipe left = delete: red sheet with what is lost; cancel keeps the card, confirm deletes', (tester) async {
      final a = await pumpList(tester);
      await tester.fling(find.textContaining('[QA] ลูกค้า R66').first, const Offset(-400, 0), 1500);
      await settle(tester);
      expect(find.text('ลบ [QA] ลูกค้า R66?'), findsOneWidget);
      expect(find.byKey(const ValueKey('delete-confirm-loses')), findsOneWidget);
      expect(find.text('คอมเม้นท์และไฟล์แนบ'), findsOneWidget);
      final del = tester.widget<FilledButton>(find.byKey(const ValueKey('delete-confirm')));
      expect(del.style?.backgroundColor?.resolve({}), kNxDangerRed);
      await tester.tap(find.byKey(const ValueKey('status-confirm-cancel')));
      await settle(tester, 20);
      expect(find.byKey(const ValueKey('row-lead-5')), findsOneWidget, reason: 'the card snaps back');

      await tester.fling(find.textContaining('[QA] ลูกค้า R66').first, const Offset(-400, 0), 1500);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('delete-confirm')));
      await settle(tester, 20);
      expect(find.byKey(const ValueKey('row-lead-5')), findsNothing, reason: 'hidden while the undo window is open');
      await tester.pump(const Duration(seconds: 6));
      await settle(tester);
      expect(a.callKeys, contains('DELETE /api/entity/lead/5'));
    });

    testWidgets('one number: the call sheet just shows it', (tester) async {
      await pumpList(tester, row: {...lead}..remove('phone'));
      await tester.fling(find.textContaining('[QA] ลูกค้า R66').first, const Offset(400, 0), 1500);
      await settle(tester);
      expect(find.text('0811111111'), findsOneWidget);
      expect(find.text('เลือกเบอร์ที่จะโทร'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('call-confirm')));
      await settle(tester, 20);
      expect('${launches.single.arguments}', contains('tel:0811111111'));
    });
  });

  group('detail', () {
    Future<FakeNextxAdapter> pumpDetail(WidgetTester tester, String module, Map<String, dynamic> row, Map<String, Object?> fields) async {
      SharedPreferences.setMockInitialValues({});
      final id = row['id'];
      final adapter = FakeNextxAdapter({
        'GET /api/entity/$module/$id': row,
        'GET /api/entity/$module/$id/comments': {'list': []},
        'GET /api/entity/$module/$id/tags': {'list': []},
        'GET /api/tags': {'list': []},
        'GET /api/fields/$module': fields,
        'PUT /api/entity/$module/$id': {'id': id},
      });
      final config = AppConfig();
      config.debugOverrideSession(SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true, menuKeys: [module]));
      config.apiClient.debugSetHttpAdapter(adapter);
      tester.view.physicalSize = const Size(420, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: config,
        child: MaterialApp(home: EntityDetailScreen(module: module, row: {'id': id})),
      ));
      await settle(tester, 12);
      return adapter;
    }

    testWidgets('lead stepper: cancel leaves the step, confirm saves', (tester) async {
      final a = await pumpDetail(tester, 'lead', {'id': 5, 'lead_name': '[QA] ลูกค้า R66', 'lead_status': 'New'}, {
        'fields': [
          {'name': 'lead_name', 'label_th': 'ชื่อ'},
          {'name': 'lead_status', 'label_th': 'สถานะ', 'uitype': 'picklist'},
        ],
        'picklists': {
          'lead_status': [
            {'value': 'New', 'label': 'ใหม่'},
            {'value': 'Qualified', 'label': 'ผ่านเกณฑ์'},
          ],
        },
      });
      await tester.tap(find.byKey(const ValueKey('step-Qualified')));
      await settle(tester);
      expect(find.text('เปลี่ยนสถานะ?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('status-confirm-cancel')));
      await settle(tester);
      expect(a.calls.where((c) => c.method == 'PUT'), isEmpty);
      expect(find.byKey(const ValueKey('step-done-Qualified')), findsNothing, reason: 'still on the old step');

      await tester.tap(find.byKey(const ValueKey('step-Qualified')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('status-confirm-ok')));
      await settle(tester);
      final put = a.calls.where((c) => c.method == 'PUT').toList();
      expect(put, hasLength(1));
      expect(put.single.data, {'lead_status': 'Qualified'});
      expect(find.textContaining('เปลี่ยนสถานะแล้ว'), findsOneWidget);
    });

    testWidgets('deal "ปิดแพ้": red confirm, reason required (chips) and sent as closed_reason', (tester) async {
      final a = await pumpDetail(tester, 'deal', {'id': 7, 'deal_name': '[QA] ดีล R66', 'deal_stage': 'Negotiation'}, {
        'fields': [
          {'name': 'deal_name', 'label_th': 'ชื่อดีล'},
          {'name': 'deal_stage', 'label_th': 'สถานะ', 'uitype': 'picklist'},
        ],
        'picklists': {
          'deal_stage': [
            for (final s in const ['Qualification', 'Value Proposition', 'Proposal Sent', 'Negotiation', 'Closed Won', 'Closed Lost']) {'value': s, 'label': s},
          ],
        },
      });
      await tester.tap(find.byKey(const ValueKey('deal-close-lost')));
      await settle(tester);
      expect(find.text('นับเป็นดีลที่แพ้ · ความน่าจะเป็น 0%'), findsOneWidget);
      final ok = tester.widget<FilledButton>(find.byKey(const ValueKey('status-confirm-ok')));
      expect(ok.onPressed, isNull, reason: 'a reason is required');
      expect(ok.style?.backgroundColor?.resolve({}), kNxDangerRed);
      await tester.tap(find.byKey(const ValueKey('status-reason-0')));
      await settle(tester, 4);
      await tester.tap(find.byKey(const ValueKey('status-confirm-ok')));
      await settle(tester);
      final put = a.calls.where((c) => c.method == 'PUT').single;
      expect(put.data, {'deal_stage': 'Closed Lost', 'probability': 0, 'closed_reason': 'ราคาสูงกว่าคู่แข่ง'});
    });
  });
}

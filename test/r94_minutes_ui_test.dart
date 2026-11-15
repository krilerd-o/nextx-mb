// ไอแซคบันทึกประชุม (AI Minute Meeting) screens: home (list / search / filters / actions), meeting detail
// (summary, tasks, transcript edit, translation, ask), share (link options / e-mail), room settings, join.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/isaac_menu.dart';
import 'package:nextx_mobile/core/minutes/minutes.dart';
import 'package:nextx_mobile/core/navigation/app_routes.dart';
import 'package:nextx_mobile/core/navigation/route_access.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/minutes/minute_detail_screen.dart';
import 'package:nextx_mobile/screens/minutes/minute_join_sheet.dart';
import 'package:nextx_mobile/screens/minutes/minute_record_flow.dart';
import 'package:nextx_mobile/screens/minutes/minute_room_create_screen.dart';
import 'package:nextx_mobile/screens/minutes/minute_share_sheet.dart';
import 'package:nextx_mobile/screens/minutes/minutes_home_screen.dart';

import 'support/fake_api.dart';

const _member = SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['ai-minute-meeting']);

Map<String, dynamic> _json(RequestOptions o) => o.data is Map ? Map<String, dynamic>.from(o.data as Map) : (o.data is String ? jsonDecode(o.data as String) as Map<String, dynamic> : <String, dynamic>{});

final _meeting = {
  'id': 7,
  'title': '[QA] ประชุมทีมขาย',
  'source': 'record',
  'status': 'ready',
  'locale': 'th',
  'duration_ms': 125000,
  'started_at': '2026-11-15T03:00:00Z',
  'speakers': {'Speaker 1': 'คุณเอ'},
  'features': {'translate': []},
};

Map<String, Object?> _base() => {
  'GET /api/ai/minutes/config': {'rooms': true, 'languages': [], 'templates': []},
  'GET /api/ai/minutes': {
    'items': [
      _meeting,
      {'id': 8, 'title': '[QA] ไฟล์สัมมนา', 'source': 'upload', 'status': 'processing', 'progress': 40, 'stage': 'transcribe'},
    ],
  },
  'GET /api/ai/minutes/7': {
    'item': _meeting,
    'segments': [
      {'seq': 1, 'start_ms': 0, 'text': 'เริ่มประชุมเรื่องงบ', 'speaker': 'Speaker 1'},
      {'seq': 2, 'start_ms': 65000, 'text': 'ส่งใบเสนอราคาวันศุกร์', 'speaker': 'Speaker 2'},
    ],
    'summaries': [
      {
        'id': 1,
        'template': 'sales',
        'headline': 'ตกลงงบไตรมาสสาม',
        'key_points': ['งบ 1 ล้าน [1:05]'],
        'decisions': ['ใช้ผู้ขายรายเดิม'],
        'action_items': [{'text': 'ส่งใบเสนอราคา', 'owner': 'คุณเอ', 'due': '2026-11-20'}],
        'open_questions': ['ส่วนลดเท่าไร'],
        'chapters': [{'at_ms': 65000, 'title': 'ใบเสนอราคา'}],
      },
    ],
    'translations': [],
    'room': null,
  },
  'POST /api/ai/minutes/7/actions/create-tasks': {'results': [{'index': 0, 'activity_id': 91, 'owner_id': 2, 'owner_matched': true}]},
  'POST /api/ai/minutes/7/translate': {'started': true, 'lang': 'en'},
  'POST /api/ai/minutes/7/ask': {'answer': 'คุณเอรับไปส่งใบเสนอราคา [1:05]', 'refs': [{'at': '1:05', 'at_ms': 65000}]},
  'PATCH /api/ai/minutes/7/segments/1': {'segment': {'seq': 1}},
  'PATCH /api/ai/minutes/7': {'item': _meeting},
  'GET /api/ai/minutes/7/share/links': {'items': [], 'base_url': ''},
  'POST /api/ai/minutes/7/share/links': {'token': 'tok', 'url': 'https://crm/minutes/s/tok', 'expires_at': '2026-11-22T00:00:00Z'},
  'POST /api/ai/minutes/7/share/email': {'sent': true, 'to': ['a@x.com']},
  'POST /api/ai/minutes/rooms': {
    'room': {'id': 3, 'meeting_id': 12, 'code': 'abc-defg-hij', 'link': 'https://crm/m/abc-defg-hij', 'settings': {}},
    'item': {'id': 12, 'title': '[QA] ห้องประชุม'},
  },
};

Future<FakeNextxAdapter> _pump(WidgetTester tester, Widget screen, {Map<String, Object?> extra = const {}}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig()..debugOverrideSession(_member);
  final adapter = FakeNextxAdapter({..._base(), ...extra});
  config.apiClient.debugSetHttpAdapter(adapter);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: screen)));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return adapter;
}

Future<void> _settle(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  testWidgets('home: actions, meetings with status, search inside meetings, source filter', (tester) async {
    final a = await _pump(tester, const MinutesHomeScreen());
    for (final k in ['record', 'video', 'upload', 'room', 'join']) {
      expect(find.byKey(ValueKey('minutes-action-$k')), findsOneWidget);
    }
    expect(find.text('[QA] ประชุมทีมขาย'), findsOneWidget);
    expect(find.textContaining('กำลังถอดข้อความ 40%'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('minutes-search')), 'ใบเสนอราคา');
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester, 3);
    expect(a.calls.lastWhere((c) => c.path == '/api/ai/minutes').queryParameters['q'], 'ใบเสนอราคา');
    await tester.tap(find.byKey(const ValueKey('minutes-filter-upload')));
    await _settle(tester, 3);
    expect(a.calls.lastWhere((c) => c.path == '/api/ai/minutes').queryParameters['source'], 'upload');
  });

  testWidgets('home: rooms off on this server → room buttons explain instead of opening', (tester) async {
    await _pump(tester, const MinutesHomeScreen(), extra: {'GET /api/ai/minutes/config': {'rooms': false}});
    await tester.tap(find.byKey(const ValueKey('minutes-action-room')));
    await tester.pump();
    expect(find.text('ผู้ดูแลยังไม่ได้เปิดใช้ห้องประชุม'), findsOneWidget);
  });

  testWidgets('detail: minutes by section, tasks to CRM, transcript with names, translate, ask ISAAC', (tester) async {
    final a = await _pump(tester, const MinuteDetailScreen(meetingId: '7'));
    expect(find.text('ตกลงงบไตรมาสสาม'), findsOneWidget);
    expect(find.text('ใช้ผู้ขายรายเดิม'), findsOneWidget);
    expect(find.text('ใบเสนอราคา'), findsOneWidget, reason: 'chapter');
    await tester.scrollUntilVisible(find.byKey(const ValueKey('minute-create-tasks')), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byKey(const ValueKey('minute-create-tasks')));
    await _settle(tester, 4);
    expect(a.callKeys, contains('POST /api/ai/minutes/7/actions/create-tasks'));
    expect(find.text('สร้างงานแล้ว 1 รายการ'), findsOneWidget);

    await tester.tap(find.text('ถอดข้อความ'));
    await tester.pumpAndSettle();
    expect(find.text('คุณเอ'), findsOneWidget, reason: 'renamed speaker');
    expect(find.text('Speaker 2'), findsOneWidget);
    await tester.longPress(find.byKey(const ValueKey('minute-line-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('minute-edit-text')), 'เริ่มประชุมเรื่องงบประมาณ');
    await tester.tap(find.text('บันทึก'));
    await _settle(tester, 4);
    expect(_json(a.calls.lastWhere((c) => c.path == '/api/ai/minutes/7/segments/1'))['text'], 'เริ่มประชุมเรื่องงบประมาณ');

    await tester.tap(find.text('แปล'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('minute-tr-make-en')));
    await _settle(tester, 4);
    expect(_json(a.calls.lastWhere((c) => c.path == '/api/ai/minutes/7/translate'))['lang'], 'en');

    await tester.tap(find.text('ถามไอแซค'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('minute-ask-input')), 'ใครส่งใบเสนอราคา');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _settle(tester, 4);
    expect(_json(a.calls.lastWhere((c) => c.path == '/api/ai/minutes/7/ask'))['question'], 'ใครส่งใบเสนอราคา');
    expect(find.textContaining('คุณเอรับไปส่งใบเสนอราคา'), findsOneWidget);
  });

  testWidgets('share: link with expiry, password, what to show and who; e-mail', (tester) async {
    final a = await _pump(tester, Scaffold(body: SingleChildScrollView(child: MinuteSharePanel(meeting: MinuteMeeting.fromJson(_meeting)))));
    await tester.tap(find.text('ลิงก์'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('minute-share-inc-transcript')));
    await tester.tap(find.byKey(const ValueKey('minute-link-days-30')));
    await tester.enterText(find.byKey(const ValueKey('minute-link-password')), 'pw');
    await tester.enterText(find.byKey(const ValueKey('minute-link-allowed')), '@acme.com');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('minute-link-create')));
    await tester.tap(find.byKey(const ValueKey('minute-link-create')));
    await _settle(tester, 4);
    final body = _json(a.calls.lastWhere((c) => c.path == '/api/ai/minutes/7/share/links' && c.method == 'POST'));
    expect(body['days'], 30);
    expect(body['password'], 'pw');
    expect(body['include'], containsAll(['summary', 'actions', 'transcript']));
    expect(body['allowed_emails'], '@acme.com');
    expect(find.text('https://crm/minutes/s/tok'), findsOneWidget);

    await tester.tap(find.text('อีเมล'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('minute-email-to')), 'a@x.com');
    await tester.ensureVisible(find.byKey(const ValueKey('minute-email-send')));
    await tester.tap(find.byKey(const ValueKey('minute-email-send')));
    await _settle(tester, 4);
    expect(_json(a.calls.lastWhere((c) => c.path == '/api/ai/minutes/7/share/email'))['to'], ['a@x.com']);
  });

  testWidgets('room settings: what is sent, then link + code to share', (tester) async {
    final a = await _pump(tester, const MinuteRoomCreateScreen());
    await tester.enterText(find.byKey(const ValueKey('room-title')), '[QA] ห้องประชุม');
    await tester.tap(find.text('เฉพาะที่เชิญ').first);
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('room-allowed')), '@partner.com');
    await tester.enterText(find.byKey(const ValueKey('room-password')), '1234');
    await tester.scrollUntilVisible(find.byKey(const ValueKey('room-rec-video')), 250, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    await tester.ensureVisible(find.byKey(const ValueKey('room-rec-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('room-rec-video')));
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('room-create-go')), 250, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    await tester.ensureVisible(find.byKey(const ValueKey('room-create-go')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('room-create-go')));
    await _settle(tester, 4);
    final body = _json(a.calls.lastWhere((c) => c.path == '/api/ai/minutes/rooms'));
    final s = body['settings'] as Map;
    expect(body['title'], '[QA] ห้องประชุม');
    expect(s['access'], 'invited');
    expect(s['allowed_emails'], '@partner.com');
    expect(s['password'], '1234');
    expect(s['waiting_room'], isTrue);
    expect(s['max_participants'], 50);
    expect((s['ai'] as Map)['record'], 'video');
    expect((s['ai'] as Map)['translate_langs'], ['en']);
    expect(find.byKey(const ValueKey('room-created')), findsOneWidget);
    expect(find.text('abc-defg-hij'), findsOneWidget);
  });

  testWidgets('finish sheet: summarise later skips e-mail / tasks', (tester) async {
    await _pump(tester, const SizedBox());
    MinuteFinish? got;
    final ctx = tester.element(find.byType(SizedBox));
    showMinuteFinishSheet(ctx, translate: const ['en']).then((v) => got = v);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('minute-finish-panel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('minute-finish-later')));
    await tester.pump();
    expect(find.byKey(const ValueKey('minute-finish-email')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('minute-finish-go')));
    await tester.pumpAndSettle();
    expect(got?.summarizeNow, isFalse);
    expect(got?.toStopBody()['summary_mode'], 'later');
    expect(got?.translate, ['en']);
  });

  test('room codes from codes and links; routes; menu + access', () {
    expect(roomCodeFrom('ABC-defg-hij'), 'abc-defg-hij');
    expect(roomCodeFrom('https://crm.example.com/m/xyz-abcd-efg?x=1'), 'xyz-abcd-efg');
    expect(roomCodeFrom('hello'), isNull);
    expect(AppRoutes.aiMinute('7'), '/ai-minutes/7');
    expect(AppRoutes.minuteRoomLink('abc-defg-hij'), '/m/abc-defg-hij');
    expect(isaacItemFor('/ai-minutes/7')?.key, 'ai-minute-meeting');
    expect(isaacItemFor('/ai-minutes')?.key, 'ai-minute-meeting');
    const access = IsaacAccess(aiChat: true);
    expect(access.visible(IsaacMenu.minuteMeeting, _member), isTrue);
    expect(access.visible(IsaacMenu.minuteMeeting, const SessionState(accessToken: 't', userId: '3', businessId: '1', menusLoaded: true, menuKeys: ['lead'])), isFalse);
    expect(IsaacMenu.all.indexOf(IsaacMenu.minuteMeeting), lessThan(IsaacMenu.all.indexOf(IsaacMenu.minuteAuto)));
  });
}

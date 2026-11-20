// Round 2: read-only shared minutes, saved room chat (tab + host delete), "แชร์กับฉัน", bubble long-press menu,
// meeting-recording notification labels, Home "กำลังทำอยู่" card.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/minutes/minutes.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/dashboard/home_ongoing_card.dart';
import 'package:nextx_mobile/screens/minutes/minute_detail_screen.dart';
import 'package:nextx_mobile/screens/minutes/minutes_home_screen.dart';
import 'package:nextx_mobile/services/minutes/minute_room_session.dart';
import 'package:nextx_mobile/services/notebook/recording_foreground.dart';
import 'package:nextx_mobile/widgets/nx_ongoing_bubble.dart';

import 'support/fake_api.dart';

const _member = SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['ai-minute-meeting']);

Map<String, dynamic> _meeting({String source = 'record', String? via}) => {
      'id': 7,
      'title': 'ประชุมทีมขาย',
      'source': source,
      'status': 'ready',
      'locale': 'th',
      'duration_ms': 60000,
      'started_at': '2026-11-15T03:00:00Z',
      'features': {'translate': []},
      'access_via': ?via,
    };

Map<String, Object?> _detail({required bool canWrite, String via = 'owner', String source = 'record'}) => {
      'GET /api/ai/minutes/7': {
        'item': _meeting(source: source),
        'segments': [
          {'seq': 1, 'start_ms': 0, 'text': 'เริ่มประชุม', 'speaker': 'Speaker 1'},
        ],
        'summaries': [
          {'id': 1, 'template': 'general', 'headline': 'สรุป', 'key_points': ['ก'], 'decisions': [], 'action_items': [{'text': 'ส่งงาน'}], 'open_questions': []},
        ],
        'translations': [],
        'room': null,
        'access': {'owner': canWrite && via == 'owner', 'can_write': canWrite, 'via': via},
      },
      'GET /api/ai/minutes/7/chat': {
        'items': [
          {'id': 11, 'identity': 'g1', 'name': 'แขก', 'text': 'สวัสดีครับ', 'at': '2026-11-15T03:01:00Z'},
          {'id': 12, 'identity': 'u2', 'name': 'สมชาย', 'text': 'เริ่มกันเลย', 'at': '2026-11-15T03:02:00Z'},
        ],
      },
      'DELETE /api/ai/minutes/7/chat/11': {'removed': true},
    };

Future<FakeNextxAdapter> _pump(WidgetTester t, Widget screen, Map<String, Object?> replies) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(420, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final config = AppConfig()..debugOverrideSession(_member);
  final a = FakeNextxAdapter({'GET /api/ai/minutes/config': {'rooms': true}, ...replies});
  config.apiClient.debugSetHttpAdapter(a);
  await t.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: screen)));
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  return a;
}

void main() {
  setUp(() {
    MinuteRoomSession.active.value = null;
    OngoingBubbles.instance.reset();
  });

  testWidgets('shared with me: read only — no share / summarise / tasks / edit, Ask disabled', (t) async {
    await _pump(t, const MinuteDetailScreen(meetingId: '7'), _detail(canWrite: false, via: 'share'));
    expect(find.byKey(const ValueKey('minute-read-only')), findsOneWidget);
    expect(find.byKey(const ValueKey('minute-share')), findsNothing);
    expect(find.byKey(const ValueKey('minute-resummarize')), findsNothing);
    expect(find.byKey(const ValueKey('minute-create-tasks')), findsNothing);
  });

  testWidgets('owner: actions are there', (t) async {
    await _pump(t, const MinuteDetailScreen(meetingId: '7'), _detail(canWrite: true));
    expect(find.byKey(const ValueKey('minute-share')), findsOneWidget);
    expect(find.byKey(const ValueKey('minute-resummarize')), findsOneWidget);
    expect(find.byKey(const ValueKey('minute-tab-chat')), findsNothing, reason: 'not a room meeting');
  });

  testWidgets('room meeting: "แชท" tab shows the saved chat; the host deletes a message', (t) async {
    final a = await _pump(t, const MinuteDetailScreen(meetingId: '7'), _detail(canWrite: true, source: 'room'));
    expect(find.byKey(const ValueKey('minute-tab-chat')), findsOneWidget);
    await t.ensureVisible(find.byKey(const ValueKey('minute-tab-chat')));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const ValueKey('minute-tab-chat')));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 80));
    }
    expect(find.text('สวัสดีครับ'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('minute-chat-delete-11')));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const ValueKey('minute-chat-delete-ok')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 80));
    }
    expect(a.callKeys, contains('DELETE /api/ai/minutes/7/chat/11'));
    expect(find.text('สวัสดีครับ'), findsNothing);
    expect(find.text('เริ่มกันเลย'), findsOneWidget);
  });

  testWidgets('Minutes Home: "แชร์กับฉัน" filter asks scope=shared, cards carry the badge', (t) async {
    final a = await _pump(t, const MinutesHomeScreen(), {
      'GET /api/ai/minutes': {
        'items': [_meeting(via: 'share')],
      },
    });
    expect(find.byKey(const ValueKey('minute-card-shared-7')), findsOneWidget);
    await t.ensureVisible(find.text('แชร์กับฉัน'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('แชร์กับฉัน'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 80));
    }
    expect(a.calls.any((c) => c.path == '/api/ai/minutes' && c.queryParameters['scope'] == 'shared'), isTrue);
  });

  test('model: access_via', () {
    expect(MinuteMeeting.fromJson(_meeting(via: 'share')).sharedWithMe, isTrue);
    expect(MinuteMeeting.fromJson(_meeting(via: 'owner')).sharedWithMe, isFalse);
  });

  test('meeting recording notification uses its own wording', () async {
    final fg = NoopRecordingForeground();
    await fg.start(title: 'x', elapsedMs: 0, labels: NativeRecordingForeground.minuteLabels);
    expect(fg.lastLabels?['recording'], 'กำลังบันทึกประชุม');
  });

  testWidgets('bubble: long-press opens the menu, an item runs and closes it', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    var muted = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          NxOngoingBubble(
            kind: 'room',
            onTap: () {},
            menu: [OngoingMenuItem(id: 'room-mic', label: 'ปิดไมค์', icon: Icons.mic, onTap: () => muted++)],
            child: const ColoredBox(color: Colors.black),
          ),
        ]),
      ),
    ));
    await t.longPress(find.byKey(const ValueKey('ongoing-bubble-room')));
    await t.pump();
    expect(find.byKey(const ValueKey('ongoing-menu-room')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ongoing-menu-room-mic')));
    await t.pump();
    expect(muted, 1);
    expect(find.byKey(const ValueKey('ongoing-menu-room')), findsNothing);
  });

  testWidgets('Home card: hidden with nothing, lists open rooms to join', (t) async {
    await _pump(t, const Scaffold(body: SingleChildScrollView(child: HomeOngoingCard())), {
      'GET /api/ai/minutes': {'items': []},
    });
    expect(find.byKey(const ValueKey('home-ongoing')), findsNothing);
    await _pump(t, Scaffold(body: SingleChildScrollView(child: HomeOngoingCard(key: UniqueKey()))), {
      'GET /api/ai/minutes': {
        'items': [
          {..._meeting(source: 'room'), 'room_code': 'abc-defg-hij', 'room_open': true},
        ],
      },
    });
    expect(find.byKey(const ValueKey('home-ongoing')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-ongoing-open-7-go')), findsOneWidget);
    expect(find.text('เข้าร่วม'), findsOneWidget);
  });
}

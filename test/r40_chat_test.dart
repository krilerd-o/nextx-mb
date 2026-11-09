import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/chat_format.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/chat/chat_home_screen.dart';
import 'package:nextx_mobile/screens/chat/chat_room_screen.dart';
import 'package:nextx_mobile/screens/chat/room/chat_call_hooks.dart';

import 'support/fake_api.dart';

Future<AppConfig> _pump(WidgetTester tester, Widget screen, FakeNextxAdapter adapter, {Size size = const Size(430, 932)}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig();
  config.debugOverrideSession(const SessionState(accessToken: 't', userId: '3', businessId: '1'));
  config.apiClient.debugSetHttpAdapter(adapter);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(theme: AppTheme.light, home: screen)));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return config;
}

final _now = DateTime.now().toUtc();
String _ago(Duration d) => _now.subtract(d).toIso8601String();

final _rooms = [
  {
    'id': 1,
    'name': 'แชทกับ [QA] Google Tester',
    'room_type': 'dm',
    'display_name': '[QA] Second',
    'peer': {'id': 2, 'name': '[QA] Second'},
    'unread_count': 2,
    'last_message_at': _ago(const Duration(minutes: 5)),
    'last_message': {'id': 9, 'user_id': 2, 'body': '[QA] สวัสดีครับ', 'sender_name': '[QA] Second', 'created_at': _ago(const Duration(minutes: 5))},
  },
  {
    'id': 2,
    'name': '[QA] ทีมโทรกลุ่ม',
    'room_type': 'channel',
    'member_count': 3,
    'unread_count': 0,
    'muted': true,
    'last_message_at': _ago(const Duration(hours: 1)),
    'last_message': {'id': 8, 'user_id': 3, 'body': '', 'attachment_kind': 'image', 'sender_name': '[QA] Google Tester'},
  },
  {
    'id': 3,
    'name': '[QA] ติดดาว',
    'room_type': 'channel',
    'starred': true,
    'unread_count': 0,
    'last_message_at': _ago(const Duration(days: 3)),
    'last_message': {'id': 7, 'user_id': 4, 'kind': 'call', 'call': {'media': 'video', 'status': 'missed', 'caller_id': 4, 'missed_ids': [3]}, 'sender_name': '[QA] Third'},
  },
];

Map<String, dynamic> _msg(int id, int user, String body, {Map<String, dynamic> extra = const {}}) => {
      'id': id,
      'room_id': 1,
      'user_id': user,
      'first_name': user == 3 ? '[QA] Google' : '[QA]',
      'last_name': user == 3 ? 'Tester' : 'Second',
      'body': body,
      'created_at': _ago(Duration(minutes: 30 - id)),
      'attachments': <Map<String, dynamic>>[],
      ...extra,
    };

final _messages = [
  _msg(1, 2, '[QA] ข้อความแรก **สำคัญ**'),
  _msg(2, 3, '[QA] ตอบกลับนะ', extra: {
    'reply_to_id': 1,
    'reply_to': {'id': 1, 'user_id': 2, 'sender_name': '[QA] Second', 'body': '[QA] ข้อความแรก'},
  }),
  _msg(3, 2, '[QA] ส่งต่อมา', extra: {
    'forwarded_from': {'room_id': 5, 'message_id': 77, 'user_name': '[QA] Third'},
  }),
  _msg(4, 2, '', extra: {
    'attachments': [
      {'id': 1, 'file_name': 'voice-1.m4a', 'file_path': 'chat/voice-1.m4a', 'mime_type': 'audio/mp4', 'file_size': 2000},
      {'id': 2, 'file_name': 'สัญญา.pdf', 'file_path': 'chat/a.pdf', 'mime_type': 'application/pdf', 'file_size': 120000},
    ],
  }),
  _msg(5, 3, '📹 วิดีโอคอล · 1:05', extra: {
    'kind': 'call',
    'call': {'media': 'video', 'status': 'completed', 'duration_s': 65, 'caller_id': 3},
  }),
  _msg(6, 2, '[QA] ข้อความที่ถูกลบ', extra: {'deleted_at': _ago(const Duration(minutes: 1))}),
];

FakeNextxAdapter _roomApi() => FakeNextxAdapter({
      'GET /api/chat/rooms/1/messages': {'list': _messages, 'read_receipts': {}},
      'GET /api/chat/rooms/1/pins': {'list': []},
      'GET /api/chat/rooms/1/members': {
        'list': [
          {'user_id': 2, 'first_name': '[QA]', 'last_name': 'Second'},
          {'user_id': 3, 'first_name': '[QA] Google', 'last_name': 'Tester'},
          {'user_id': 4, 'first_name': '[QA]', 'last_name': 'Third'},
        ],
      },
      'POST /api/chat/rooms/1/read': {'ok': true},
      'POST /api/chat/rooms/1/messages': {'id': 50, 'room_id': 1, 'user_id': 3, 'body': 'x', 'created_at': _now.toIso8601String()},
      'GET /api/chat/rooms': _rooms,
      'POST /api/chat/rooms/1/messages/1/forward': {'sent': [{'room_id': 2, 'message_id': 99}], 'skipped': []},
      'DELETE /api/chat/rooms/1/messages/2': {'ok': true},
      'GET /api/chat/unfurl': {},
    });

Map<String, dynamic> _json(FakeNextxAdapter a, String key) {
  final c = a.calls.lastWhere((c) => '${c.method.toUpperCase()} ${c.path}' == key);
  final d = c.data;
  return d is String ? jsonDecode(d) as Map<String, dynamic> : Map<String, dynamic>.from(d as Map);
}

void main() {
  group('chat_format', () {
    test('room title uses the other person for DMs', () {
      expect(chatRoomTitle(_rooms[0]), '[QA] Second');
      expect(chatRoomTitle({'name': 'แชทกับ X', 'room_type': 'dm', 'peer': {'name': 'Y'}}), 'Y');
      expect(chatRoomTitle(_rooms[1]), '[QA] ทีมโทรกลุ่ม');
    });

    test('preview: sender in groups, "คุณ" for mine, file kind, missed call', () {
      expect(chatRoomPreview(_rooms[0], '3'), '[QA] สวัสดีครับ');
      expect(chatRoomPreview(_rooms[1], '3'), 'คุณ: 📷 รูปภาพ');
      expect(chatRoomPreview(_rooms[2], '3'), '[QA] Third: 📹 สายที่ไม่ได้รับ');
    });

    test('call labels per viewer', () {
      final c = {'media': 'audio', 'status': 'cancelled', 'caller_id': 3, 'missed_ids': [2]};
      expect(chatCallLabel(c, '3').title, 'โทรด้วยเสียง');
      expect(chatCallLabel(c, '3').detail, 'ยกเลิก');
      expect(chatCallLabel(c, '2').missed, isTrue);
      expect(chatCallLabel({'media': 'video', 'status': 'completed', 'duration_s': 3725}, '3').detail, '1:02:05');
    });

    test('sort: starred first, then newest', () {
      expect(chatSortRooms(_rooms).map((r) => r['id']), [3, 1, 2]);
    });

    test('mentions, markdown and links', () {
      final enc = chatEncodeMentions('สวัสดี @[QA] Second และ @Ann', {'[QA] Second': '2', 'Ann': '9'});
      expect(enc.body, 'สวัสดี @[2:[QA] Second] และ @[9:Ann]');
      expect(enc.ids..sort(), [2, 9]);
      expect(chatPlainText('<p>a</p>@[2:Bo] <b>x</b>'), 'a\n@Bo x');
      expect(chatMarkdownToHtml('**b** _i_ `c` <x>'), '<b>b</b> <i>i</i> <b>c</b> &lt;x&gt;');
      expect(chatLinks('ดู https://moai.co.th/a. ด้วย'), ['https://moai.co.th/a']);
      expect(chatAttachmentKind('audio/webm'), 'audio');
      expect(chatAttachmentKind(null, 'clip.MOV'), 'video');
    });
  });

  testWidgets('chat list: peer name, preview, time, unread, muted, starred on top, one search', (tester) async {
    await _pump(tester, const ChatHomeScreen(), _roomApi());
    expect(find.text('[QA] Second'), findsOneWidget);
    expect(find.text('แชทกับ [QA] Google Tester'), findsNothing);
    expect(find.text('[QA] สวัสดีครับ'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-unread-1')), findsOneWidget);
    expect(find.text('คุณ: 📷 รูปภาพ'), findsOneWidget);
    // starred room is first
    final y3 = tester.getTopLeft(find.byKey(const ValueKey('chat-room-3'))).dy;
    final y1 = tester.getTopLeft(find.byKey(const ValueKey('chat-room-1'))).dy;
    expect(y3, lessThan(y1));
    // header has a single "new chat" action (search lives in the toolbar)
    expect(find.byTooltip('แชทใหม่'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('room: every message type renders; long press → reply sends reply_to_id', (tester) async {
    final api = _roomApi();
    await _pump(tester, const ChatRoomScreen(room: {'id': 1, 'room_type': 'dm', 'display_name': '[QA] Second'}), api);
    expect(find.text('[QA] Second'), findsWidgets);
    expect(find.byKey(const ValueKey('chat-reply-quote')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-forwarded')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-voice-play')), findsOneWidget);
    expect(find.text('สัญญา.pdf'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-call-log-5')), findsOneWidget);
    expect(find.text('ข้อความนี้ถูกลบแล้ว'), findsOneWidget);

    await tester.longPress(find.textContaining('ข้อความแรก', findRichText: true).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-act-forward')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-react-👍')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-act-reply')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ตอบกลับ [QA] Second'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('chat-input')), '[QA] รับทราบ');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();
    final body = _json(api, 'POST /api/chat/rooms/1/messages');
    expect(body['reply_to_id'], 1);
    expect(body['body'], '[QA] รับทราบ');
  });

  testWidgets('room: @mention autocomplete encodes the mention and its id', (tester) async {
    final api = _roomApi();
    await _pump(tester, const ChatRoomScreen(room: {'id': 1, 'name': '[QA] กลุ่ม'}), api);
    await tester.enterText(find.byKey(const ValueKey('chat-input')), 'สวัสดี @Th');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-mention-list')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-mention-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();
    final body = _json(api, 'POST /api/chat/rooms/1/messages');
    expect(body['body'], 'สวัสดี @[4:[QA] Third]');
    expect(body['mention_user_ids'], [4]);
  });

  testWidgets('room: forward to another room; delete asks first', (tester) async {
    final api = _roomApi();
    await _pump(tester, const ChatRoomScreen(room: {'id': 1, 'room_type': 'dm', 'display_name': '[QA] Second'}), api);
    await tester.longPress(find.textContaining('ข้อความแรก', findRichText: true).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-act-forward')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-forward-room-2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-forward-send')));
    await tester.pumpAndSettle();
    expect(_json(api, 'POST /api/chat/rooms/1/messages/1/forward')['room_ids'], [2]);
    expect(find.text('ส่งต่อแล้ว 1 ห้อง'), findsOneWidget);

    await tester.longPress(find.text('[QA] ตอบกลับนะ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-act-delete')));
    await tester.pumpAndSettle();
    expect(api.callKeys.where((k) => k.startsWith('DELETE')), isEmpty);
    await tester.tap(find.byKey(const ValueKey('chat-delete-confirm')));
    await tester.pumpAndSettle();
    expect(api.callKeys, contains('DELETE /api/chat/rooms/1/messages/2'));
    expect(find.text('ข้อความนี้ถูกลบแล้ว'), findsNWidgets(2));
  });

  testWidgets('call buttons appear only when calls are available', (tester) async {
    await _pump(tester, const ChatRoomScreen(room: {'id': 1, 'room_type': 'dm', 'display_name': '[QA] Second'}), _roomApi());
    expect(find.byKey(const ValueKey('chat-call-voice')), findsNothing);
    var called = '';
    ChatCallHooks.start = (ctx, room, {required video, userIds}) async => called = 'video=$video room=${room['id']}';
    addTearDown(() => ChatCallHooks.start = null);
    await _pump(tester, const ChatRoomScreen(room: {'id': 1, 'room_type': 'dm', 'display_name': '[QA] Second'}), _roomApi());
    await tester.tap(find.byKey(const ValueKey('chat-call-video')));
    await tester.pump();
    expect(called, 'video=true room=1');
  });
}

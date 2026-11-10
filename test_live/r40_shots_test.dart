// Manual tools (not part of `flutter test`); they use the same test-only hooks as test/.
// ignore_for_file: invalid_use_of_visible_for_testing_member

// Screenshots of the new chat / call screens (manual, not CI): flutter test test_live/r40_shots_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/calls/call_overlay.dart';
import 'package:nextx_mobile/screens/chat/chat_home_screen.dart';
import 'package:nextx_mobile/screens/chat/chat_room_screen.dart';
import 'package:nextx_mobile/services/calls/call_service.dart';

import '../test/r40_call_test.dart' show FakeSignaling, FakeMedia;
import '../test/support/fake_api.dart';

final _out = Platform.environment['SHOTS_DIR'] ?? '/tmp';

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
}

Future<void> _shot(WidgetTester tester, String name) async {
  final ro = tester.firstRenderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  await tester.runAsync(() async {
    final img = await ro.toImage(pixelRatio: 2);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Widget _app(Widget child, AppConfig config, {bool dark = false}) => ChangeNotifierProvider.value(
      value: config,
      child: RepaintBoundary(
        key: const ValueKey('shot'),
        child: MaterialApp(theme: dark ? AppTheme.dark : AppTheme.light, debugShowCheckedModeBanner: false, home: child),
      ),
    );

String _ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();

void main() {
  setUpAll(() async {
    final pc = '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/lucide_icons_flutter-4.0.1/assets/build_font';
    await _font('GoogleSans', ['assets/fonts/GoogleSans-Regular.ttf', 'assets/fonts/GoogleSans-Medium.ttf', 'assets/fonts/GoogleSans-SemiBold.ttf', 'assets/fonts/GoogleSans-Bold.ttf']);
    await _font('IBMPlexSansThai', ['assets/fonts/IBMPlexSansThai-Regular.ttf', 'assets/fonts/IBMPlexSansThai-Medium.ttf', 'assets/fonts/IBMPlexSansThai-SemiBold.ttf', 'assets/fonts/IBMPlexSansThai-Bold.ttf']);
    await _font('packages/lucide_icons_flutter/Lucide300', ['$pc/LucideVariable-w300.ttf']);
    await _font('packages/lucide_icons_flutter/Lucide500', ['$pc/LucideVariable-w500.ttf']);
  });

  Future<AppConfig> cfg(WidgetTester tester, Map<String, Object?> replies) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    final c = AppConfig();
    // Let the stored-settings load finish first, or it replaces the session below.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    c.debugOverrideSession(const SessionState(accessToken: 't', userId: '3', businessId: '1'));
    c.apiClient.debugSetHttpAdapter(FakeNextxAdapter(replies));
    return c;
  }

  final rooms = [
    {'id': 3, 'name': '[QA] ทีมขาย', 'room_type': 'channel', 'starred': true, 'member_count': 4, 'unread_count': 0, 'last_message_at': _ago(const Duration(minutes: 2)), 'last_message': {'id': 1, 'user_id': 4, 'body': 'ปิดดีลลูกค้า ABC ได้แล้วครับ 🎉', 'sender_name': '[QA] Third'}},
    {'id': 1, 'name': 'แชทกับ X', 'room_type': 'dm', 'display_name': '[QA] Second', 'unread_count': 3, 'last_message_at': _ago(const Duration(minutes: 12)), 'last_message': {'id': 2, 'user_id': 2, 'body': 'พรุ่งนี้ประชุมกี่โมงครับ', 'sender_name': '[QA] Second'}},
    {'id': 4, 'name': '[QA] ฝ่ายบริการ', 'room_type': 'channel', 'member_count': 8, 'unread_count': 0, 'muted': true, 'last_message_at': _ago(const Duration(hours: 3)), 'last_message': {'id': 3, 'user_id': 3, 'body': '', 'attachment_kind': 'image'}},
    {'id': 5, 'name': 'x', 'room_type': 'dm', 'display_name': '[QA] Third', 'unread_count': 0, 'last_message_at': _ago(const Duration(days: 1)), 'last_message': {'id': 4, 'user_id': 4, 'kind': 'call', 'call': {'media': 'video', 'status': 'missed', 'caller_id': 4, 'missed_ids': [3]}}},
    {'id': 6, 'name': '[QA] โครงการ NEXTX', 'room_type': 'channel', 'member_count': 12, 'unread_count': 0, 'last_message_at': _ago(const Duration(days: 4)), 'last_message': {'id': 5, 'user_id': 2, 'body': '', 'attachment_kind': 'audio', 'sender_name': '[QA] Second'}},
  ];
  Map<String, dynamic> m(int id, int user, String body, [Map<String, dynamic> extra = const {}]) => {
        'id': id, 'room_id': 1, 'user_id': user,
        'first_name': user == 3 ? '[QA] Google' : '[QA]', 'last_name': user == 3 ? 'Tester' : 'Second',
        'body': body, 'created_at': _ago(Duration(minutes: 40 - id)), 'attachments': <Map<String, dynamic>>[], ...extra,
      };
  final messages = [
    m(1, 2, 'สวัสดีครับ วันนี้ส่ง **ใบเสนอราคา** ให้ลูกค้าแล้วนะครับ'),
    m(2, 2, 'รบกวนตรวจไฟล์แนบด้วยครับ', {'attachments': [{'file_name': 'ใบเสนอราคา-QA.pdf', 'file_path': 'chat/q.pdf', 'mime_type': 'application/pdf', 'file_size': 245000}]}),
    m(3, 3, 'ได้เลยครับ เดี๋ยวดูให้', {'reply_to_id': 1, 'reply_to': {'id': 1, 'sender_name': '[QA] Second', 'body': 'สวัสดีครับ วันนี้ส่ง ใบเสนอราคา ให้ลูกค้าแล้วนะครับ'}, 'reaction_summary': [{'emoji': '👍', 'count': 1, 'me': false}]}),
    m(4, 2, '', {'attachments': [{'file_name': 'voice.m4a', 'file_path': 'chat/v.m4a', 'mime_type': 'audio/mp4', 'file_size': 30000}]}),
    m(5, 3, 'ส่งต่อจากกลุ่มฝ่ายขายครับ', {'forwarded_from': {'user_name': '[QA] Third'}}),
    m(6, 3, '', {'kind': 'call', 'call': {'media': 'video', 'status': 'completed', 'duration_s': 312, 'caller_id': 3}}),
    m(7, 2, 'ขอบคุณครับ @[3:[QA] Google Tester] 🙏', {'edited_at': _ago(const Duration(minutes: 1))}),
  ];

  testWidgets('shots', (tester) async {
    final c = await cfg(tester, {
      'GET /api/chat/rooms': rooms,
      'GET /api/chat/rooms/1/messages': {'list': messages, 'read_receipts': {'7': [{'user_id': 2}]}},
      'GET /api/chat/rooms/1/pins': {'list': []},
      'GET /api/chat/rooms/1/members': {'list': []},
      'POST /api/chat/rooms/1/read': {'ok': true},
      'GET /api/chat/unfurl': {},
    });
    for (final dark in [false, true]) {
      await tester.pumpWidget(_app(const ChatHomeScreen(), c, dark: dark));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      await _shot(tester, 'app_chat_list${dark ? '_dark' : ''}');
      await tester.pumpWidget(_app(const ChatRoomScreen(room: {'id': 1, 'room_type': 'dm', 'display_name': '[QA] Second'}), c, dark: dark));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      await _shot(tester, 'app_chat_room${dark ? '_dark' : ''}');
    }
    // long press menu
    await tester.pumpWidget(_app(const ChatRoomScreen(room: {'id': 1, 'room_type': 'dm', 'display_name': '[QA] Second'}), c));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.longPress(find.textContaining('ใบเสนอราคา ให้', findRichText: true).first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await _shot(tester, 'app_chat_actions');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));

    // calls
    final sig = FakeSignaling();
    final svc = CallService(signaling: sig, media: () => FakeMedia(), myUserId: '3');
    await tester.pumpWidget(_app(Stack(children: [const Scaffold(), Positioned.fill(child: CallOverlay(service: svc))]), c));
    sig.push('rtc:ring', {'call_id': 'x', 'media': 'video', 'caller_id': 2, 'caller_name': '[QA] Second', 'room_name': '[QA] Second', 'group': false});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, 'app_call_incoming');
    await svc.decline();
    sig.acks['rtc:start'] = {'ok': true, 'call': {'call_id': 'g', 'media': 'video', 'group': true, 'room_name': '[QA] ทีมขาย', 'caller_id': 3, 'invitees': []}};
    await svc.start(roomId: '3', roomTitle: '[QA] ทีมขาย', video: true);
    sig.push('rtc:joined', {'call_id': 'g', 'user_id': 2, 'socket_id': 's2', 'name': '[QA] Second', 'audio': true});
    sig.push('rtc:joined', {'call_id': 'g', 'user_id': 4, 'socket_id': 's4', 'name': '[QA] Third', 'audio': false});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, 'app_call_group');
    await svc.hangUp();
    await tester.pump(const Duration(seconds: 5));
  });
}

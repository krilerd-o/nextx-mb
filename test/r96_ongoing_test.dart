// A meeting room keeps going after its screen closes (bubble, rejoin), saved room chat, the shared
// floating bubble (× to hide), and the call / room entry in the notification bar (fake channel).
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:nextx_mobile/screens/minutes/minute_room_screen.dart';
import 'package:nextx_mobile/screens/ongoing/ongoing_overlay.dart';
import 'package:nextx_mobile/services/minutes/minute_room_session.dart';
import 'package:nextx_mobile/services/ongoing/ongoing_activities.dart';
import 'package:nextx_mobile/services/ongoing/ongoing_binder.dart';
import 'package:nextx_mobile/services/ongoing/ongoing_notification.dart';
import 'package:nextx_mobile/services/realtime_service.dart';
import 'package:nextx_mobile/widgets/nx_ongoing_bubble.dart';

import 'support/recorder_fakes.dart';

class _Rt implements RealtimeService {
  final _ctrl = StreamController<RealtimeEvent>.broadcast();
  final acks = <(String, Map<String, dynamic>)>[];
  Map<String, dynamic> join = {
    'ok': true,
    'captions': false,
    'transcribe': false,
    'langs': [],
    'chat_enabled': true,
    'chat': [
      {'id': 1, 'identity': 'g-2', 'name': 'บี', 'text': 'มาแล้วครับ', 'at': '2026-11-19T03:00:00Z'},
    ],
  };
  Map<String, dynamic> chatAnswer = {'ok': true, 'item': {'id': 2, 'identity': 'u1', 'name': 'สมชาย', 'text': 'เริ่มกันเลย', 'at': '2026-11-19T03:01:00Z'}};
  void push(String type, Map<String, dynamic> d) => _ctrl.add(RealtimeEvent(type, d));
  @override
  Stream<RealtimeEvent> get events => _ctrl.stream;
  @override
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> data, {Duration timeout = const Duration(seconds: 10)}) async {
    acks.add((event, data));
    if (event == 'minute:room_join') return join;
    if (event == 'minute:chat_send') return chatAnswer;
    return {'ok': true};
  }

  @override
  void emit(String event, Map<String, dynamic> data) {}
  @override
  void emitRoomAudio(Uint8List pcm) {}
  @override
  bool get connected => true;
  @override
  void addListener(VoidCallback l) {}
  @override
  void removeListener(VoidCallback l) {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Media extends RoomMedia {
  bool mic = true;
  bool cam = false;
  bool disconnected = false;
  final sent = <Map<String, dynamic>>[];
  final data0 = StreamController<(String, String, Map<String, dynamic>)>.broadcast();
  @override
  Future<void> connect(String url, String token, {required bool micOn, required bool camOn}) async {
    mic = micOn;
    cam = camOn;
  }

  @override
  Future<void> disconnect() async => disconnected = true;
  @override
  Future<void> setMic(bool on) async {
    mic = on;
    notifyListeners();
  }

  @override
  Future<void> setCamera(bool on) async {
    cam = on;
    notifyListeners();
  }

  @override
  Future<void> flipCamera() async {}
  @override
  Future<void> setScreenShare(bool on) async {}
  @override
  bool get micOn => mic;
  @override
  bool get camOn => cam;
  @override
  bool get screenOn => false;
  @override
  List<lk.Participant> get participants => const [];
  @override
  lk.Participant? get speaker => null;
  @override
  String? get localAudioTrackId => null;
  @override
  Future<void> sendData(Map<String, dynamic> data, {String topic = 'chat'}) async => sent.add(data);
  @override
  Stream<(String, String, Map<String, dynamic>)> get data => data0.stream;
}

MinuteRoomSession _session(_Rt rt, _Media media, {String role = 'host'}) => MinuteRoomSession(
      meetingId: '5',
      roomCode: 'abc-defg-hij',
      ticket: 'T',
      identity: 'u1',
      role: role,
      name: 'สมชาย',
      media: media,
      realtime: rt,
      boardMode: 'off',
      mic: FakePausableMic.new,
    )..title = 'ประชุมทีมขาย';

Future<void> _idle([int ms = 5]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MinuteRoomSession.active.value = null;
    OngoingBubbles.instance.reset();
  });

  group('room session', () {
    test('saved chat: history on join, sent over the socket, no LiveKit copies, refusals explained', () async {
      final rt = _Rt();
      final media = _Media();
      final s = _session(rt, media);
      await s.start(url: 'wss://x', token: 't', micOn: true);
      expect(MinuteRoomSession.active.value, s);
      expect(s.serverChat, isTrue);
      expect([for (final m in s.chat.value) m.text], ['มาแล้วครับ']);
      expect(await s.sendChat('  เริ่มกันเลย '), isTrue);
      expect(rt.acks.last.$1, 'minute:chat_send');
      expect(rt.acks.last.$2, {'ticket': 'T', 'text': 'เริ่มกันเลย'});
      expect(media.sent, isEmpty, reason: 'not via LiveKit');
      expect(s.chat.value.last.mine, isTrue);
      rt.push('minute:chat', {'room_id': 3, 'item': {'id': 3, 'identity': 'g-2', 'name': 'บี', 'text': 'โอเค'}});
      rt.push('minute:chat', {'room_id': 3, 'item': {'id': 3, 'identity': 'g-2', 'name': 'บี', 'text': 'โอเค'}});
      media.data0.add(('บี', 'chat', {'type': 'chat', 'text': 'ซ้ำ', 'name': 'บี'}));
      await _idle();
      expect([for (final m in s.chat.value) m.text], ['มาแล้วครับ', 'เริ่มกันเลย', 'โอเค']);
      rt.chatAnswer = {'ok': false, 'error': 'chat_off'};
      expect(await s.sendChat('x'), isFalse);
      expect(s.error, 'ผู้จัดปิดแชทในห้องนี้');
      await s.close();
    });

    test('start once; close: media off, no longer active; removed by the host closes it', () async {
      final rt = _Rt();
      final media = _Media();
      final s = _session(rt, media);
      await s.start(url: 'wss://x', token: 't');
      await s.start(url: 'wss://x', token: 't');
      expect(rt.acks.where((a) => a.$1 == 'minute:room_join'), hasLength(1));
      expect(ongoingActivities().map((a) => a.kind), contains('room'));
      rt.push('minute:room_removed', {'room_id': 3, 'identity': 'someone-else'});
      await _idle();
      expect(s.closed, isFalse);
      rt.push('minute:room_removed', {'room_id': 3, 'identity': 'u1'});
      await _idle(20);
      expect(s.closed, isTrue);
      expect(s.closedReason, 'removed');
      expect(media.disconnected, isTrue);
      expect(MinuteRoomSession.active.value, isNull);
      expect(ongoingActivities().map((a) => a.kind), isNot(contains('room')));
    });
  });

  group('notification bar (fake channel)', () {
    test('room: shown with the right buttons state, mute / open / leave from the notification, gone after', () async {
      final fake = FakeOngoingNotifier();
      MinuteRoomSession? opened;
      MinuteRoomSession? left;
      final b = OngoingSessionsBinder(
        notifier: fake,
        callKit: RoomCallKit(enabled: false),
        leaveRoom: (r) async {
          left = r;
          await r.close();
        },
      )..bind();
      OngoingSessionsBinder.openRoom = (r) => opened = r;
      final media = _Media();
      final s = _session(_Rt(), media);
      await s.start(url: 'wss://x', token: 't', micOn: true);
      await _idle();
      expect(fake.current['room']?.title, 'ประชุมทีมขาย');
      expect(fake.current['room']?.micOn, isTrue);
      expect(fake.current['room']?.toMap()['labels'], OngoingNotice.roomLabels);
      expect(fake.pip, isEmpty, reason: 'no video → no Picture-in-Picture');

      fake.tap('room', 'mute');
      await _idle();
      expect(media.mic, isFalse);
      expect(fake.current['room']?.micOn, isFalse, reason: 'button flips to เปิดไมค์');
      fake.tap('room', 'mute'); // already muted: nothing
      await _idle();
      expect(media.mic, isFalse);
      fake.tap('room', 'unmute');
      await _idle();
      expect(media.mic, isTrue);

      await media.setCamera(true);
      await _idle();
      expect(fake.pip, [true], reason: 'camera on → PiP when leaving the app');

      fake.tap('room', 'open');
      await _idle();
      expect(opened, s);

      fake.tap('room', 'hangup');
      await _idle(20);
      expect(left, s);
      expect(fake.current.containsKey('room'), isFalse);
      expect(fake.pip.last, isFalse);
      b.dispose();
      OngoingSessionsBinder.openRoom = null;
    });

    test('notice equality and labels', () {
      final at = DateTime(2026, 11, 19, 10);
      expect(OngoingNotice(kind: 'call', title: 'a', startedAt: at), OngoingNotice(kind: 'call', title: 'a', startedAt: at));
      expect(OngoingNotice(kind: 'call', title: 'a', micOn: false, startedAt: at) == OngoingNotice(kind: 'call', title: 'a', startedAt: at), isFalse);
      final m = OngoingNotice(kind: 'call', title: 'x', startedAt: at).toMap();
      expect(m['startedAt'], at.millisecondsSinceEpoch);
      expect((m['labels'] as Map)['hangup'], 'วางสาย');
    });

    test('native channel: calls only on Android, actions and PiP come back', () async {
      const ch = MethodChannel('test/ongoing');
      final sent = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (c) async {
        sent.add(c);
        return null;
      });
      final n = NativeOngoingNotifier(channel: ch, android: true);
      await n.show(const OngoingNotice(kind: 'room', title: 'r'));
      await n.setPip(enabled: true);
      await n.hide('room');
      expect(sent.map((c) => c.method), ['show', 'pip', 'hide']);
      expect((sent.first.arguments as Map)['kind'], 'room');
      final got = <(String, String)>[];
      final sub = n.actions.listen(got.add);
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'test/ongoing',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('action', {'kind': 'call', 'action': 'hangup'})),
        (_) {},
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'test/ongoing',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('pip', true)),
        (_) {},
      );
      await _idle();
      expect(got, [('call', 'hangup')]);
      expect(n.inPip.value, isTrue);
      await sub.cancel();
      final ios = NativeOngoingNotifier(channel: ch, android: false);
      sent.clear();
      await ios.show(const OngoingNotice(kind: 'room', title: 'r'));
      expect(sent, isEmpty, reason: 'iOS: CallKit instead');
    });
  });

  group('floating bubble', () {
    testWidgets('drag onto the × hides it; the pill at the top brings it back', (t) async {
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      var taps = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: OngoingBubbles.instance,
            builder: (_, _) => Stack(children: [
              if (!OngoingBubbles.instance.isHidden('room'))
                NxOngoingBubble(kind: 'room', onTap: () => taps++, child: const ColoredBox(color: Colors.black))
              else
                const NxOngoingRestorePill(kind: 'room', label: 'กำลังประชุม'),
            ]),
          ),
        ),
      ));
      final bubble = find.byKey(const ValueKey('ongoing-bubble-room'));
      await t.tap(bubble);
      expect(taps, 1);
      // Start dragging: the × appears at the bottom.
      final g = await t.startGesture(t.getCenter(bubble));
      await g.moveBy(const Offset(0, -30));
      await t.pump();
      expect(find.byKey(const ValueKey('ongoing-dismiss-zone')), findsOneWidget);
      final zone = t.getCenter(find.byKey(const ValueKey('ongoing-dismiss-zone')));
      await g.moveTo(zone);
      await t.pump();
      await g.up();
      await t.pump();
      expect(OngoingBubbles.instance.isHidden('room'), isTrue);
      expect(bubble, findsNothing);
      await t.tap(find.byKey(const ValueKey('ongoing-restore-room')));
      await t.pump();
      expect(OngoingBubbles.instance.isHidden('room'), isFalse);
      expect(bubble, findsOneWidget);
    });

    test('snap to the nearer edge, clamp inside the safe area', () {
      const screen = Size(390, 844);
      const pad = EdgeInsets.only(top: 47, bottom: 34);
      expect(snapOngoingBubble(const Offset(40, 300), screen, pad).dx, 8);
      expect(snapOngoingBubble(const Offset(300, 300), screen, pad).dx, 390 - kOngoingBubbleSize.width - 8);
      expect(clampOngoingBubble(const Offset(-50, -50), screen, pad), const Offset(8, 55));
    });
  });

  group('room screen', () {
    testWidgets('back / ย่อ only minimises → bubble; tap the bubble → back in the same room; leave closes it', (t) async {
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final rt = _Rt();
      final media = _Media();
      final s = _session(rt, media, role: 'member');
      final navKey = GlobalKey<NavigatorState>();
      final pip = ValueNotifier<bool>(false);
      await t.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        builder: (context, child) => Stack(children: [?child, Positioned.fill(child: OngoingSessionsOverlay(navigatorKey: navKey, pip: pip))]),
        home: const Scaffold(body: Text('home')),
      ));
      MinuteRoomSession.active.value = s;
      unawaited(reopenMinuteRoom(navKey.currentState!, s..url = 'wss://x'..token = 't'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('minute-room')), findsOneWidget);
      expect(s.started, isTrue);
      expect(s.screenOpen, isTrue);
      expect(find.byKey(const ValueKey('room-bubble')), findsNothing, reason: 'no bubble over its own screen');

      await t.tap(find.byKey(const ValueKey('room-minimise')));
      await t.pump();
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(navKey.currentState!.canPop(), isFalse);
      expect(find.byKey(const ValueKey('minute-room')), findsNothing);
      expect(s.closed, isFalse, reason: 'still in the meeting');
      expect(media.disconnected, isFalse);
      expect(MinuteRoomSession.active.value, s);
      expect(find.byKey(const ValueKey('room-bubble')), findsOneWidget);

      // Mic from the bubble.
      await t.tap(find.byKey(const ValueKey('room-bubble-mic')));
      await t.pump();
      expect(media.mic, isTrue);

      // PiP: only the compact room view.
      pip.value = true;
      await t.pump();
      expect(find.byKey(const ValueKey('room-pip')), findsOneWidget);
      pip.value = false;
      await t.pump();

      await t.tap(find.byKey(const ValueKey('ongoing-bubble-room')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('minute-room')), findsOneWidget);
      expect(rt.acks.where((a) => a.$1 == 'minute:room_join'), hasLength(1), reason: 'same session, not joined again');

      // Closed from elsewhere (removed / signed out): the screen goes away by itself.
      await t.runAsync(() => s.close().timeout(const Duration(seconds: 3)));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(s.closed, isTrue);
      expect(MinuteRoomSession.active.value, isNull);
      expect(media.disconnected, isTrue);
      expect(find.byKey(const ValueKey('minute-room')), findsNothing);
      expect(find.byKey(const ValueKey('room-bubble')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 500));
    });
  });
}

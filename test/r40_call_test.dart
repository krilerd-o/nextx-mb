import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/screens/calls/call_overlay.dart';
import 'package:nextx_mobile/services/calls/call_media.dart';
import 'package:nextx_mobile/services/calls/call_service.dart';
import 'package:nextx_mobile/services/realtime_service.dart';

class FakeSignaling implements CallSignaling {
  final _ctrl = StreamController<RealtimeEvent>.broadcast();
  final emitted = <(String, Map<String, dynamic>)>[];
  final acks = <String, Map<String, dynamic>>{};
  @override
  Stream<RealtimeEvent> get events => _ctrl.stream;
  @override
  String? socketId = 'sA';
  @override
  bool connected = true;
  @override
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> data) async {
    emitted.add((event, data));
    return acks[event] ?? {'ok': false, 'error': 'server_error'};
  }

  @override
  void emit(String event, Map<String, dynamic> data) => emitted.add((event, data));
  void push(String type, Map<String, dynamic> data) => _ctrl.add(RealtimeEvent(type, data));
  List<Map<String, dynamic>> sent(String event) => [for (final e in emitted) if (e.$1 == event) e.$2];
}

class FakePeer extends CallPeer {
  final log = <String>[];
  bool _remote = false;
  String state = 'stable';
  @override
  Future<void> addLocalTracks() async => log.add('addLocal');
  @override
  Future<void> attachLocalToOffered() async => log.add('attach');
  @override
  Future<Map<String, dynamic>> createOffer({bool iceRestart = false}) async {
    log.add('offer');
    state = 'have-local-offer';
    return {'type': 'offer', 'sdp': 'o'};
  }

  @override
  Future<Map<String, dynamic>> createAnswer() async {
    log.add('answer');
    state = 'stable';
    return {'type': 'answer', 'sdp': 'a'};
  }

  @override
  Future<void> setRemote(Map<String, dynamic> d) async {
    log.add('remote:${d['type']}');
    _remote = true;
    if (d['type'] == 'answer') state = 'stable';
  }

  @override
  Future<void> rollback() async => log.add('rollback');
  @override
  Future<void> addCandidate(Map<String, dynamic> c) async => log.add('ice');
  @override
  bool get hasRemoteDescription => _remote;
  @override
  String get signalingState => state;
  @override
  Future<void> sendVideo() async => log.add('sendVideo');
  @override
  Future<void> close() async => log.add('close');
}

class FakeMedia implements CallMedia {
  final peers = <FakePeer>[];
  var opened = false;
  var closed = false;
  bool? lastVideo;
  var muted = false;
  @override
  Future<bool> openLocal({required bool video}) async {
    opened = true;
    lastVideo = video;
    return true;
  }

  @override
  Object? get localStream => null;
  @override
  bool get hasVideo => lastVideo == true;
  @override
  Future<void> setMuted(bool m) async => muted = m;
  @override
  Future<bool> setVideo(bool on) async => on;
  @override
  Future<void> switchCamera() async {}
  @override
  Future<void> setSpeaker(bool on) async {}
  bool? lastRelayOnly;
  @override
  Future<CallPeer> createPeer(List<Map<String, dynamic>> iceServers, {bool relayOnly = false}) async {
    lastRelayOnly = relayOnly;
    final p = FakePeer();
    peers.add(p);
    return p;
  }

  @override
  Future<void> closeLocal() async => closed = true;
}

const _callId = '7b2f5d7e-1111-4c4c-9a9a-123456789abc';

Map<String, dynamic> _call({String state = 'ringing', bool group = false, String media = 'video'}) => {
      'call_id': _callId,
      'chat_room_id': 1,
      'room_name': group ? '[QA] ทีมโทรกลุ่ม' : '[QA] Google Tester',
      'group': group,
      'media': media,
      'state': state,
      'caller_id': 3,
      'caller_name': '[QA] Google Tester',
      'invitees': [
        {'user_id': 2, 'name': '[QA] Second', 'status': 'ringing'},
      ],
      'peers': [],
    };

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeSignaling sig;
  late FakeMedia media;
  late CallService svc;

  setUp(() {
    sig = FakeSignaling();
    media = FakeMedia();
    svc = CallService(signaling: sig, media: () => media, myUserId: '3');
  });

  test('outgoing: start → ringing; the callee joins → active; their offer gets an answer', () async {
    sig.acks['rtc:start'] = {
      'ok': true,
      'call': _call(),
      'ice': {'ice_servers': [{'urls': ['turn:t.qa:3478'], 'username': 'u', 'credential': 'c'}], 'turn': true, 'ice_transport_policy': 'relay'},
    };
    final code = await svc.start(roomId: '1', roomTitle: '[QA] Second', video: true);
    expect(code, isNull);
    expect(svc.phase, CallPhase.outgoing);
    expect(media.opened, isTrue);
    expect(sig.sent('rtc:start').single['media'], 'video');
    expect(svc.title, '[QA] Second');

    sig.push('rtc:joined', {'call_id': _callId, 'user_id': 2, 'socket_id': 'sB', 'name': '[QA] Second', 'audio': true, 'video': true});
    await _flush();
    expect(svc.phase, CallPhase.active);
    expect(svc.participants.keys, ['sB']);
    expect(media.peers.single.log, isEmpty); // existing side waits for the newcomer's offer
    expect(media.lastRelayOnly, isTrue); // Settings → การโทร "ผ่าน TURN เสมอ"

    sig.push('rtc:signal', {'call_id': _callId, 'from_socket_id': 'sB', 'from_user_id': 2, 'data': {'type': 'offer', 'sdp': 'o'}});
    await _flush();
    await _flush();
    expect(media.peers.single.log, ['remote:offer', 'attach', 'answer']);
    final answer = sig.sent('rtc:signal').last;
    expect(answer['to_socket_id'], 'sB');
    expect((answer['data'] as Map)['type'], 'answer');

    await svc.hangUp();
    expect(sig.sent('rtc:leave').single['call_id'], _callId);
    expect(media.closed, isTrue);
    expect(svc.phase, CallPhase.idle);
  });

  test('incoming: ring → accept → offers to everyone already in the call', () async {
    sig.push('rtc:ring', {..._call(group: true), 'caller_id': 4, 'caller_name': '[QA] Third'});
    await _flush();
    expect(svc.phase, CallPhase.incoming);
    expect(svc.title, '[QA] ทีมโทรกลุ่ม');
    sig.acks['rtc:accept'] = {
      'ok': true,
      'call': {..._call(group: true, state: 'active'), 'caller_id': 4},
      'peers': [
        {'user_id': 4, 'socket_id': 'sC', 'name': '[QA] Third'},
        {'user_id': 2, 'socket_id': 'sB', 'name': '[QA] Second'},
      ],
      'ice': {'ice_servers': []},
    };
    await svc.accept();
    await _flush();
    expect(svc.phase, CallPhase.active);
    expect(svc.participants.length, 2);
    for (final p in media.peers) {
      expect(p.log, containsAllInOrder(['addLocal', 'offer']));
    }
    expect(sig.sent('rtc:signal').where((s) => (s['data'] as Map)['type'] == 'offer').map((s) => s['to_socket_id']).toSet(), {'sC', 'sB'});

    // ICE before the answer is queued, then applied
    sig.push('rtc:signal', {'call_id': _callId, 'from_socket_id': 'sC', 'data': {'type': 'candidate', 'candidate': {'candidate': 'c1'}}});
    await _flush();
    expect(media.peers.first.log.contains('ice'), isFalse);
    sig.push('rtc:signal', {'call_id': _callId, 'from_socket_id': 'sC', 'data': {'type': 'answer', 'sdp': 'a'}});
    await _flush();
    await _flush();
    expect(media.peers.first.log, containsAllInOrder(['remote:answer', 'ice']));

    // someone leaves; mute is announced
    sig.push('rtc:left', {'call_id': _callId, 'user_id': 2, 'socket_id': 'sB'});
    await _flush();
    expect(svc.participants.keys, ['sC']);
    await svc.toggleMute();
    expect(media.muted, isTrue);
    expect(sig.sent('rtc:media').last['audio'], false);
  });

  test('decline, cancelled ring → missed notice, busy and too_many', () async {
    sig.push('rtc:ring', {..._call(), 'caller_id': 4});
    await _flush();
    await svc.decline();
    expect(sig.sent('rtc:decline').single['call_id'], _callId);
    expect(svc.phase, CallPhase.idle);

    sig.push('rtc:ring', {..._call(), 'caller_id': 4});
    await _flush();
    sig.push('rtc:ring_stop', {'call_id': _callId, 'reason': 'cancelled'});
    await _flush();
    expect(svc.incoming, isNull);
    expect(svc.notice, 'สายที่ไม่ได้รับ');

    sig.acks['rtc:start'] = {'ok': false, 'error': 'too_many', 'max': 4};
    expect(await svc.start(roomId: '9', roomTitle: 'ใหญ่', video: false), 'too_many');
    expect(svc.error, isNull); // the chat shows a picker instead of an error
    expect(svc.phase, CallPhase.idle);

    sig.acks['rtc:start'] = {'ok': true, 'call': _call(), 'busy': true};
    expect(await svc.start(roomId: '1', roomTitle: 'x', video: false), isNull);
    expect(svc.phase, CallPhase.idle);
    expect(svc.notice, 'สายไม่ว่าง');
  });

  test('caller sees "declined" when the 1:1 call ends that way', () async {
    sig.acks['rtc:start'] = {'ok': true, 'call': _call()};
    await svc.start(roomId: '1', roomTitle: 'x', video: false);
    sig.push('rtc:ended', {'call_id': _callId, 'reason': 'declined'});
    await _flush();
    await _flush();
    expect(svc.phase, CallPhase.idle);
    expect(svc.notice, 'ปลายสายปฏิเสธสาย');
  });

  testWidgets('overlay: incoming screen accept / decline buttons', (tester) async {
    sig.push('rtc:ring', {..._call(), 'caller_id': 4, 'caller_name': '[QA] Third'});
    await tester.pumpWidget(MaterialApp(home: Stack(children: [const SizedBox.expand(), Positioned.fill(child: CallOverlay(service: svc))])));
    await tester.pump();
    expect(find.byKey(const ValueKey('call-incoming')), findsOneWidget);
    expect(find.text('[QA] Third'), findsOneWidget);
    expect(find.byKey(const ValueKey('call-accept-audio')), findsOneWidget); // video call → "audio only"
    await tester.tap(find.byKey(const ValueKey('call-decline')));
    await tester.pump();
    expect(find.byKey(const ValueKey('call-incoming')), findsNothing);
    expect(sig.sent('rtc:decline'), isNotEmpty);
  });

  testWidgets('overlay: active call controls and minimise to a bubble', (tester) async {
    sig.acks['rtc:start'] = {'ok': true, 'call': _call(media: 'audio')};
    await tester.pumpWidget(MaterialApp(home: Stack(children: [const SizedBox.expand(), Positioned.fill(child: CallOverlay(service: svc))])));
    await svc.start(roomId: '1', roomTitle: '[QA] Second', video: false);
    sig.push('rtc:joined', {'call_id': _callId, 'user_id': 2, 'socket_id': 'sB', 'name': '[QA] Second'});
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('call-screen')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('call-mute')));
    await tester.pump();
    expect(svc.muted, isTrue);
    await tester.tap(find.byKey(const ValueKey('call-minimize')));
    await tester.pump();
    expect(find.byKey(const ValueKey('call-bubble')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('call-bubble')));
    await tester.pump();
    expect(find.byKey(const ValueKey('call-screen')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('call-end')));
    await tester.pump();
    expect(find.byKey(const ValueKey('call-screen')), findsNothing);
    await tester.pump(const Duration(seconds: 5)); // notice timers
  });
}

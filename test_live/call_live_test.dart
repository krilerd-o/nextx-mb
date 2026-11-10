// Manual tools (not part of `flutter test`); they use the same test-only hooks as test/.
// ignore_for_file: invalid_use_of_visible_for_testing_member

// Live check against a local NEXTX backend (not part of CI): the app's CallService over a real socket.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/services/calls/call_service.dart';
import 'package:nextx_mobile/services/realtime_service.dart';

import '../test/r40_call_test.dart' show FakeMedia;

void main() {
  test('app ↔ server rtc protocol', () async {
    HttpOverrides.global = null; // real network
    final token = File(Platform.environment['QA_TOKEN_FILE']!).readAsStringSync().trim();
    final rt = RealtimeService.instance;
    rt.connect(baseUrl: 'http://127.0.0.1:4000', token: token, businessId: '1');
    for (var i = 0; i < 40 && !rt.connected; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(rt.connected, isTrue);
    final media = FakeMedia();
    final svc = CallService(media: () => media, myUserId: '3');
    final code = await svc.start(roomId: '1', roomTitle: '[QA] Second', video: true);
    // ignore: avoid_print
    print('[A] start code=$code phase=${svc.phase} id=${svc.callId}');
    expect(code, isNull);
    for (var i = 0; i < 50 && svc.phase != CallPhase.active; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print('[A] phase=${svc.phase} participants=${svc.participants.keys}');
    expect(svc.phase, CallPhase.active);
    for (var i = 0; i < 30 && (media.peers.isEmpty || !media.peers.first.log.contains('answer')); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print('[A] peer log=${media.peers.first.log}');
    expect(media.peers.first.log, containsAllInOrder(['remote:offer', 'attach', 'answer']));
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await svc.hangUp();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    rt.disconnect();
  });
}

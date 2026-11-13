// ISAAC Notebook recordings (phase 2): entry, consent, recorder screen, floating bubble, processing
// card, ready toast → summary, recording source view, permission and older servers.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/comm_ai/comm_ai_widgets.dart' show CommAiSummaryView;
import 'package:nextx_mobile/screens/notebook/notebook_note_viewer.dart';
import 'package:nextx_mobile/screens/notebook/notebook_recorder_overlay.dart';
import 'package:nextx_mobile/screens/notebook/notebook_recorder_ui.dart';
import 'package:nextx_mobile/screens/notebook/notebook_recording_view.dart';
import 'package:nextx_mobile/screens/notebook/notebook_screen.dart';
import 'package:nextx_mobile/services/audio/pcm.dart';
import 'package:nextx_mobile/services/audio/recording_upload_queue.dart';
import 'package:nextx_mobile/services/calls/call_service.dart';
import 'package:nextx_mobile/services/calls/live_transcription.dart' show CommAiDevice;
import 'package:nextx_mobile/services/notebook/notebook_controller.dart';
import 'package:nextx_mobile/services/notebook/notebook_recorder.dart';
import 'package:nextx_mobile/services/notebook/recording_foreground.dart';
import 'package:nextx_mobile/services/realtime_service.dart';
import 'package:nextx_mobile/widgets/nx_audio_player_card.dart';

import 'support/fake_api.dart';
import 'support/notebook_fixtures.dart';
import 'support/recorder_fakes.dart';
import 'support/recording_fixtures.dart';

const _me = SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['ai-assistant']);

Map<String, Object?> _replies({bool recordings = true, bool withRecording = false}) => {
      'GET /api/ai/notebooks/3': {'item': withRecording ? nbDetailWithRecording() : nbDetail(withConversation: true)},
      'GET /api/ai/notebooks/3/guide': nbGuide(),
      'GET /api/ai/conversations/9': {'id': 9, 'messages': []},
      'GET /api/ai/jobs-status': {'enabled': false},
      if (recordings) ...{
        'GET /api/ai/notebooks/3/recordings': {'items': withRecording ? [nbRecording()] : <Object>[]},
        'POST /api/ai/notebooks/3/recordings': {'item': {'id': 77, 'notebook_id': 3, 'title': 'x', 'status': 'recording', 'started_at': '2026-11-13T10:00:00Z', 'locale': 'th'}},
        'POST /api/ai/notebooks/3/recordings/77/parts': {'received': true, 'part': 0},
        'POST /api/ai/notebooks/3/recordings/77/pause': {'status': 'paused'},
        'POST /api/ai/notebooks/3/recordings/77/resume': {'status': 'recording'},
        'POST /api/ai/notebooks/3/recordings/77/stop': {'status': 'processing'},
        'GET /api/ai/notebooks/3/recordings/77': {'item': nbRecording(id: 77, status: 'processing')},
        'GET /api/ai/notebooks/3/recordings/16': {'item': nbRecording()},
      },
    };

Future<void> settle(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Real file I/O (closing the WAV part, queueing the stop) only moves on between pumps.
Future<void> settleUntil(WidgetTester tester, bool Function() done, {int max = 80}) async {
  for (var i = 0; i < max && !done(); i++) {
    await settle(tester, 1);
  }
  await settle(tester, 2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late FakeNotebookTransport t;
  late FakePausableMic mic;
  late NoopRecordingForeground fg;
  late RecordingUploadQueue q;
  late NotebookRecorder r;
  late FakeNextxAdapter adapter;
  late AppConfig config;
  final navKey = GlobalKey<NavigatorState>();
  var perm = MicPermission.granted;
  String? opened;

  Future<void> pump(WidgetTester tester, Widget home, Map<String, Object?> replies, {Map<String, Object> prefs = const {}, CallService? call}) async {
    SharedPreferences.setMockInitialValues({CommAiDevice.key: 'app-phone-9', ...prefs});
    CommAiDevice.reset();
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    NotebookController.recordingPollEvery = const Duration(milliseconds: 40);
    tmp = await tester.runAsync(() async => Directory.systemTemp.createTemp('nbui')) as Directory;
    config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    config.debugOverrideSession(_me);
    adapter = FakeNextxAdapter(replies);
    config.apiClient.debugSetHttpAdapter(adapter);
    t = FakeNotebookTransport();
    mic = FakePausableMic();
    fg = NoopRecordingForeground();
    q = RecordingUploadQueue(dir: () async => tmp)..api = config.apiClient;
    RecordingUploadQueue.instance = q;
    perm = MicPermission.granted;
    opened = null;
    r = NotebookRecorder(transport: t, mic: () => mic.stopped ? (mic = FakePausableMic()) : mic, queue: q, foreground: fg, permission: () async => perm)
      ..api = config.apiClient
      ..businessId = '1'
      ..partBytes = kPcmBytesPerSecond;
    if (call != null) r.attachCall(call);
    NotebookRecorder.instance = r;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(
        navigatorKey: navKey,
        builder: (context, child) => Stack(children: [
          child!,
          Positioned.fill(
            child: NotebookRecorderOverlay(
              recorder: r,
              navigatorKey: navKey,
              call: call,
              open: (loc) {
                opened = loc;
                final u = Uri.parse(loc);
                navKey.currentState!.push(MaterialPageRoute<void>(
                  builder: (_) => NotebookScreen(id: u.pathSegments.last, openRecordingId: u.queryParameters['recording'], openNoteId: u.queryParameters['note']),
                ));
              },
            ),
          ),
        ]),
        home: home,
      ),
    ));
    await settle(tester);
  }

  Future<void> done(WidgetTester tester) async {
    // Stopped in the test zone (its WAV chain was started there), pumped until it is done.
    if (r.active) {
      final stopping = r.stop();
      var finished = false;
      stopping.whenComplete(() => finished = true).ignore();
      await settleUntil(tester, () => finished);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      q.dispose();
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('older server (404 on /recordings): the record entry is hidden', (tester) async {
    await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.sources), _replies(recordings: false));
    expect(find.byKey(const ValueKey('notebook-record')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('notebook-add-source')));
    await settle(tester);
    expect(find.byKey(const ValueKey('notebook-add-record')), findsNothing);
    expect(find.byKey(const ValueKey('notebook-add-file')), findsOneWidget);
    await done(tester);
  });

  testWidgets('consent → recorder: live lines, bookmark, pause; minimise → bubble (drag, toggle, expand); stop → processing → source', (tester) async {
    await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.sources), _replies());
    expect(find.byKey(const ValueKey('notebook-record')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notebook-add-source')));
    await settle(tester);
    expect(find.byKey(const ValueKey('notebook-add-record')), findsOneWidget, reason: 'the Phase-1 placeholder is live now');
    await tester.tap(find.byKey(const ValueKey('notebook-add-record')));
    await settle(tester);
    expect(find.byKey(const ValueKey('notebook-record-consent')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notebook-record-remember')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('notebook-record-accept')));
    await settle(tester, 12);
    expect(r.recording, isTrue);
    expect(r.recordingId, '77');
    expect(find.byKey(const ValueKey('notebook-record-screen')), findsOneWidget);
    expect(find.byKey(const ValueKey('notebook-recorder-bubble')), findsNothing, reason: 'hidden while the full screen is open');
    expect(find.byKey(const ValueKey('notebook-record-live-live')), findsOneWidget);
    expect(t.sent('stt:start').single['session_kind'], 'notebook');

    t.push('stt:segment', {'recording_id': 77, 'seq': 1, 'text': 'เริ่มประชุม', 'partial': true, 'start_ms': 0});
    await settle(tester, 2);
    expect(find.text('เริ่มประชุม …'), findsOneWidget, reason: 'partial lines are greyed with …');
    t.push('stt:segment', {'recording_id': 77, 'seq': 1, 'text': 'เริ่มประชุมกันเลยครับ', 'partial': false, 'start_ms': 0});
    await settle(tester, 2);
    expect(find.text('เริ่มประชุมกันเลยครับ'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notebook-record-bookmark')));
    await settle(tester, 2);
    expect(r.bookmarks, hasLength(1));
    expect(find.text('คั่นเวลา (1)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notebook-record-toggle')));
    await settle(tester, 3);
    expect(r.paused, isTrue);
    expect(find.text('อัดต่อ'), findsWidgets);

    // Minimise → floating bubble over the notebook.
    await tester.tap(find.byKey(const ValueKey('notebook-record-minimise')));
    await settle(tester, 6);
    expect(find.byKey(const ValueKey('notebook-record-screen')), findsNothing);
    final bubble = find.byKey(const ValueKey('notebook-recorder-bubble'));
    expect(bubble, findsOneWidget);
    expect(find.byKey(const ValueKey('notebook-recording-live-card')), findsOneWidget, reason: 'the sources list shows the live recording');
    final before = tester.getTopLeft(bubble);
    await tester.drag(bubble, const Offset(-220, 380));
    await tester.pump();
    final after = tester.getTopLeft(bubble);
    expect(after.dx, lessThan(before.dx));
    expect(after.dy, greaterThan(before.dy));
    await tester.drag(bubble, const Offset(-900, 0)); // clamped inside the screen
    await tester.pump();
    expect(tester.getTopLeft(bubble).dx, 8);
    await tester.tap(find.byKey(const ValueKey('notebook-recorder-bubble-toggle')));
    await settle(tester, 3);
    expect(r.recording, isTrue, reason: 'resumed from the bubble');
    await tester.tap(find.byKey(const ValueKey('notebook-recorder-bubble-time')));
    await settle(tester, 6);
    expect(find.byKey(const ValueKey('notebook-record-screen')), findsOneWidget, reason: 'tap → expand');

    // Audio, then stop (confirm) → the processing card.
    mic.feed(1000);
    mic.feed(400);
    await settle(tester, 3);
    await tester.tap(find.byKey(const ValueKey('notebook-record-stop')));
    await settle(tester, 3);
    expect(find.byKey(const ValueKey('notebook-record-stop-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notebook-record-stop-ok')));
    await settleUntil(tester, () => r.phase == RecorderPhase.idle && adapter.callKeys.contains('POST /api/ai/notebooks/3/recordings/77/stop'));
    expect(r.active, isFalse);
    expect(find.byKey(const ValueKey('notebook-record-screen')), findsNothing);
    expect(adapter.callKeys, contains('POST /api/ai/notebooks/3/recordings/77/stop'));
    expect(find.byKey(const ValueKey('notebook-recording-77')), findsOneWidget);
    // "uploading" while the queue still holds the stop / last part, then "processing".
    final processing = find.text('กำลังประมวลผล… ไอแซคกำลังถอดเสียงและสรุป');
    await settleUntil(tester, () => processing.evaluate().isNotEmpty);
    expect(processing, findsOneWidget);

    // The server finishes: the card goes, the recording is a source now.
    adapter.replies['GET /api/ai/notebooks/3/recordings/77'] = {'item': nbRecording(id: 77, status: 'ready', sourceId: 54)};
    adapter.replies['GET /api/ai/notebooks/3'] = {'item': nbDetailWithRecording()};
    await settle(tester, 10);
    expect(find.byKey(const ValueKey('notebook-recording-77')), findsNothing);
    expect(find.byKey(const ValueKey('notebook-source-54')), findsOneWidget);

    // Second time: no consent (remembered).
    await tester.tap(find.byKey(const ValueKey('notebook-record')));
    await settleUntil(tester, () => r.recording, max: 30);
    expect(find.byKey(const ValueKey('notebook-record-consent')), findsNothing);
    expect(r.recording, isTrue);
    await done(tester);
  });

  testWidgets('a call starting pauses the recording and says so; the bubble keeps clear of the call bubble', (tester) async {
    final call = TestCallService();
    await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.sources), _replies(), prefs: {'notebook.recordConsent': true}, call: call);
    await tester.tap(find.byKey(const ValueKey('notebook-record')));
    await settle(tester, 10);
    expect(r.recording, isTrue);
    call.setPhase(CallPhase.active);
    await settle(tester, 3);
    expect(r.paused, isTrue);
    expect(find.byKey(const ValueKey('notebook-record-notice')), findsOneWidget);
    expect(find.text(NotebookRecorder.callNotice), findsOneWidget);
    // Call minimised + recorder minimised: two bubbles, no overlap.
    call.setPhase(CallPhase.active, minimized: true);
    await tester.tap(find.byKey(const ValueKey('notebook-record-minimise')));
    await settle(tester, 6);
    final rect = tester.getRect(find.byKey(const ValueKey('notebook-recorder-bubble')));
    final mq = MediaQueryData.fromView(tester.view);
    expect(rect.overlaps(callBubbleRect(mq.size, mq.padding)), isFalse);
    await tester.tap(find.byKey(const ValueKey('notebook-recorder-bubble-toggle')));
    await settle(tester, 2);
    expect(r.paused, isTrue, reason: 'cannot resume during the call');
    call.setPhase(CallPhase.idle);
    await done(tester);
    call.dispose();
  });

  testWidgets('ready event → toast → "ดูสรุป" opens the structured meeting summary', (tester) async {
    await pump(tester, const Scaffold(body: SizedBox()), _replies(withRecording: true));
    t.push('ai:notebook_recording_ready', {'notebook_id': 3, 'recording_id': 16, 'source_id': 54, 'note_id': 17, 'title': 'ประชุมลูกค้าสาขาบางนา'});
    await settle(tester, 2);
    expect(find.byKey(const ValueKey('notebook-recording-ready-toast')), findsOneWidget);
    expect(find.text('ไอแซคสรุปบันทึกเสียงเสร็จแล้ว'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notebook-recording-ready-open')));
    await settle(tester, 14);
    expect(opened, '/notebook/3?recording=16&note=17');
    expect(find.byType(NotebookNoteScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('notebook-meeting-summary')), findsOneWidget);
    expect(find.byType(CommAiSummaryView), findsOneWidget);
    expect(find.text('ใจความสำคัญ'), findsOneWidget);
    expect(find.byKey(const ValueKey('notebook-meeting-source')), findsOneWidget, reason: 'links back to the recording');
    await done(tester);
  });

  testWidgets('recording source: player + transcript; tap a line or bookmark → seek; ดูสรุป', (tester) async {
    await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.sources), _replies(withRecording: true));
    await tester.tap(find.byKey(const ValueKey('notebook-source-54')));
    await settle(tester, 8);
    expect(find.byType(NotebookRecordingSourceScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('notebook-recording-player')), findsOneWidget);
    expect(find.byKey(const ValueKey('notebook-recording-line-2')), findsOneWidget);
    NxAudioPlayerController ctl() => tester.widget<NxAudioPlayerCard>(find.byKey(const ValueKey('notebook-recording-player'))).controller!;
    await tester.tap(find.byKey(const ValueKey('notebook-recording-line-1')));
    await settle(tester, 2);
    expect(ctl().lastSeekMs, 6000);
    await tester.tap(find.byKey(const ValueKey('notebook-recording-line-2')));
    await settle(tester, 2);
    expect(ctl().lastSeekMs, 10000);
    await tester.tap(find.byKey(const ValueKey('notebook-recording-bookmark-0')));
    await settle(tester, 2);
    expect(ctl().lastSeekMs, 6000);
    await tester.tap(find.byKey(const ValueKey('notebook-recording-summary')));
    await settle(tester, 8);
    expect(find.byType(CommAiSummaryView), findsOneWidget);
    await done(tester);
  });

  testWidgets('microphone refused for good: explain + open Settings', (tester) async {
    var settings = 0;
    openMicSettings = () async {
      settings++;
      return true;
    };
    await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.sources), _replies(), prefs: {'notebook.recordConsent': true});
    perm = MicPermission.permanentlyDenied;
    await tester.tap(find.byKey(const ValueKey('notebook-record')));
    await settle(tester, 6);
    expect(find.byKey(const ValueKey('notebook-mic-permission')), findsOneWidget);
    expect(adapter.callKeys, isNot(contains('POST /api/ai/notebooks/3/recordings')));
    await tester.tap(find.byKey(const ValueKey('notebook-mic-settings')));
    await settle(tester, 2);
    expect(settings, 1);
    expect(r.active, isFalse);
    await done(tester);
  });

  testWidgets('ready socket event reloads the notebook and drops the processing card', (tester) async {
    final replies = _replies();
    replies['GET /api/ai/notebooks/3/recordings'] = {'items': [nbRecording(status: 'processing')]};
    replies['GET /api/ai/notebooks/3/recordings/16'] = {'item': nbRecording(status: 'processing')};
    await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.sources), replies);
    expect(find.byKey(const ValueKey('notebook-recording-16')), findsOneWidget);
    adapter.replies['GET /api/ai/notebooks/3'] = {'item': nbDetailWithRecording()};
    RealtimeService.instance.dispatchForTest('ai:notebook_recording_ready', {'notebook_id': 3, 'recording_id': 16, 'source_id': 54, 'note_id': 17});
    await settle(tester, 6);
    expect(find.byKey(const ValueKey('notebook-recording-16')), findsNothing);
    expect(find.byKey(const ValueKey('notebook-source-54')), findsOneWidget);
    await done(tester);
  });
}

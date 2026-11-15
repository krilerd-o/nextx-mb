// ไอแซคบันทึกประชุม — shared workspace (โน้ต · เช็กลิสต์ · บอร์ด · สเก็ตช์) and pin for everyone.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'package:nextx_mobile/core/minutes/minute_board.dart';
import 'package:nextx_mobile/screens/minutes/minute_room_screen.dart';
import 'package:nextx_mobile/screens/minutes/minute_workspace.dart';
import 'package:nextx_mobile/services/minutes/minute_board_controller.dart';
import 'package:nextx_mobile/services/minutes/minute_room_session.dart';
import 'package:nextx_mobile/services/realtime_service.dart';

class _Rt implements RealtimeService {
  final _ctrl = StreamController<RealtimeEvent>.broadcast();
  final acks = <(String, Map<String, dynamic>)>[];
  final emits = <(String, Map<String, dynamic>)>[];
  Map<String, dynamic> joinAnswer = {
    'ok': true,
    'can_edit': true,
    'me': {'identity': 'u1', 'name': 'สมชาย'},
    'people': [
      {'identity': 'u1', 'name': 'สมชาย'},
      {'identity': 'g-1', 'name': 'แขก'},
    ],
    'items': [
      {'uid': 'col-ideas', 'kind': 'col', 'data': {'title': 'ไอเดีย', 'color': 'yellow'}, 'pos': 1, 'version': 0},
      {'uid': 'col-decided', 'kind': 'col', 'data': {'title': 'ข้อสรุป', 'color': 'green'}, 'pos': 3, 'version': 0},
    ],
  };
  bool up = true;
  final store = <String, Map<String, dynamic>>{};
  void push(String type, Map<String, dynamic> d) => _ctrl.add(RealtimeEvent(type, d));
  List<Map<String, dynamic>> get ops => [for (final a in acks.where((a) => a.$1 == 'minute:board_op')) for (final o in a.$2['ops'] as List) Map<String, dynamic>.from(o as Map)];

  @override
  Stream<RealtimeEvent> get events => _ctrl.stream;
  @override
  bool get connected => up;
  @override
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> data, {Duration timeout = const Duration(seconds: 10)}) async {
    acks.add((event, data));
    if (!up) return {'ok': false, 'error': 'no_socket'};
    if (event == 'minute:board_join') return joinAnswer;
    if (event == 'minute:board_op') {
      // Like the server: fields merge into the stored item, version + 1.
      final out = <Map<String, dynamic>>[];
      for (final o in (data['ops'] as List).cast<Map>()) {
        if (o['t'] != 'put') continue;
        final prev = store[o['uid']];
        final next = {'uid': o['uid'], 'kind': o['kind'], 'data': {...?prev?['data'] as Map?, ...o['data'] as Map}, 'pos': 1, 'version': ((prev?['version'] as int?) ?? 0) + 1};
        store['${o['uid']}'] = next;
        out.add(next);
      }
      return {
        'ok': true,
        'items': out,
        'cleared': [for (final o in (data['ops'] as List).cast<Map>()) if (o['t'] == 'clear') o['page']],
      };
    }
    return {'ok': true};
  }

  @override
  void emit(String event, Map<String, dynamic> data) => emits.add((event, data));
  @override
  void addListener(VoidCallback l) {}
  @override
  void removeListener(VoidCallback l) {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Media extends RoomMedia {
  String? meta;
  final data0 = StreamController<(String, String, Map<String, dynamic>)>.broadcast();
  @override
  Future<void> connect(String url, String token, {required bool micOn, required bool camOn}) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> setMic(bool on) async {}
  @override
  Future<void> setCamera(bool on) async {}
  @override
  Future<void> flipCamera() async {}
  @override
  Future<void> setScreenShare(bool on) async {}
  @override
  bool get micOn => false;
  @override
  bool get camOn => false;
  @override
  bool get screenOn => false;
  @override
  List<lk.Participant> get participants => const [];
  @override
  lk.Participant? get speaker => null;
  @override
  String? get localAudioTrackId => null;
  @override
  Future<void> sendData(Map<String, dynamic> data, {String topic = 'chat'}) async {}
  @override
  Stream<(String, String, Map<String, dynamic>)> get data => data0.stream;
  @override
  String? get roomMetadata => meta;
  void setMeta(String m) {
    meta = m;
    notifyListeners();
  }
}

Future<void> _pumpWs(WidgetTester t, MinuteBoardController c, {int tab = 0, Brightness b = Brightness.light}) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: b, colorSchemeSeed: const Color(0xFF4F46E5)),
      home: Scaffold(body: SafeArea(child: MinuteWorkspace(controller: c, initialTab: tab))),
    ),
  );
  await t.pump();
}

void main() {
  test('board items: optimistic ops, server echoes by version, cleared pages', () {
    var list = <BoardItem>[];
    list = applyBoardOp(list, {'t': 'put', 'kind': 'check', 'uid': 'c1', 'data': {'text': 'ส่งสัญญา'}}, me: 'ก');
    expect(list.single.data, {'done': false, 'text': 'ส่งสัญญา'});
    expect(list.single.pending, isTrue);
    list = applyBoardOp(list, {'t': 'put', 'kind': 'check', 'uid': 'c1', 'data': {'done': true}});
    expect(list.single.data, {'done': true, 'text': 'ส่งสัญญา'});
    list = mergeBoard(list, [BoardItem.fromJson({'uid': 'c1', 'kind': 'check', 'data': {'done': true, 'text': 'ส่งสัญญา'}, 'version': 2})]);
    expect(list.single.pending, isFalse);
    list = mergeBoard(list, [BoardItem.fromJson({'uid': 'c1', 'kind': 'check', 'data': {'text': 'old'}, 'version': 1})]);
    expect(list.single.str('text'), 'ส่งสัญญา', reason: 'an older echo never undoes a newer state');
    list = mergeBoard(list, [
      BoardItem.fromJson({'uid': 's1', 'kind': 'stroke', 'data': {'page': 0, 'pts': [0, 0, 1, 1]}, 'version': 1}),
      BoardItem.fromJson({'uid': 's2', 'kind': 'stroke', 'data': {'page': 2, 'pts': [0, 0, 1, 1]}, 'version': 1}),
    ]);
    expect(sketchPageCount(list), 3);
    list = mergeBoard(list, const [], cleared: [0]);
    expect(list.map((x) => x.uid), ['c1', 's2']);
    list = mergeBoard(list, [BoardItem.fromJson({'uid': 'c1', 'deleted': true, 'version': 9})]);
    expect(list.map((x) => x.uid), ['s2']);
    expect(checklistProgress([
      BoardItem.fromJson({'uid': 'a', 'kind': 'check', 'data': {'text': 'a', 'done': true}}),
      BoardItem.fromJson({'uid': 'b', 'kind': 'check', 'data': {'text': 'b'}}),
      BoardItem.fromJson({'uid': 'c', 'kind': 'check', 'data': {'text': ' '}}),
    ]), (done: 1, total: 2, pct: 50));
    expect(parseCheckInput('ส่งใบเสนอราคา @สมชาย'), ('ส่งใบเสนอราคา', 'สมชาย'));
    expect(parseCheckInput('จองห้อง'), ('จองห้อง', null));
    expect(boardPosBetween(1, 2), 1.5);
    expect(newBoardUid('stk'), matches(RegExp(r'^stk-[a-z0-9]+$')));
  });

  test('sketch geometry and eraser hit test match the web', () {
    expect(simplifyPoints([0, 0, 0.0001, 0.0001, 0.5, 0.5, 0.5001, 0.5, 0.9, 0.9]), [0, 0, 0.5, 0.5, 0.9, 0.9]);
    expect(shapePoints('line', [0.1, 0.1, 0.3, 0.3, 0.5, 0.5]), [0.1, 0.1, 0.5, 0.5]);
    expect(shapePoints('rect', [0, 0, 1, 1]).length, 10);
    expect(shapePoints('ellipse', [0, 0, 1, 1]).length, 74);
    expect(shapePoints('arrow', [0, 0.5, 1, 0.5]).length, 10);
    final list = [
      BoardItem.fromJson({'uid': 'a', 'kind': 'stroke', 'data': {'page': 0, 'tool': 'pen', 'pts': [0.1, 0.1, 0.9, 0.1], 'w': 3}}),
      BoardItem.fromJson({'uid': 'b', 'kind': 'stroke', 'data': {'page': 0, 'tool': 'rect', 'pts': [0.4, 0.4, 0.6, 0.6], 'w': 3}}),
    ];
    expect(strokeAt(list, 0, 0.5, 0.105)?.uid, 'a');
    expect(strokeAt(list, 0, 0.6, 0.5)?.uid, 'b');
    expect(strokeAt(list, 0, 0.5, 0.5), isNull);
    expect(strokeAt(list, 1, 0.5, 0.1), isNull);
  });

  test('stage: host pin > my pin > screen share; absent people ignored', () {
    final present = {'u1', 'u2', 'g3'};
    expect(resolveStage(present: present), isNull);
    expect(resolveStage(presenter: 'g3', present: present), (identity: 'g3', source: 'screen', by: 'share'));
    expect(resolveStage(localPin: const StagePin(identity: 'u2'), presenter: 'g3', present: present), (identity: 'u2', source: 'camera', by: 'me'));
    const host = StagePin(identity: 'u1', source: 'screen');
    expect(resolveStage(stagePin: host, localPin: const StagePin(identity: 'u2'), presenter: 'g3', present: present), (identity: 'u1', source: 'screen', by: 'host'));
    expect(resolveStage(stagePin: host, localPin: const StagePin(identity: 'u2'), override: true, present: present)?.by, 'me');
    expect(resolveStage(stagePin: const StagePin(identity: 'gone'), presenter: 'g3', present: present)?.by, 'share');
    expect(resolveStage(stagePin: const StagePin(source: 'board'), present: present), (identity: null, source: 'board', by: 'host'));
    expect(StagePin.fromJson({'pin': {'identity': 'u1', 'source': 'screen'}, 'by': 'A'})?.by, 'A');
    expect(StagePin.fromJson({'pin': null, 'by': 'A'}), isNull);
    expect(const StagePin(source: 'board').toJson(), {'source': 'board'});
    expect(const StagePin(identity: 'u2', source: 'screen').toJson(name: 'บี'), {'source': 'screen', 'identity': 'u2', 'name': 'บี'});
  });

  test('controller: join (ticket), ops over the socket, remote changes / ink / presence, offline queue', () async {
    final rt = _Rt();
    final c = MinuteBoardController(meetingId: '7', ticket: 'TICKET', realtime: rt);
    await c.start();
    expect(rt.acks.first.$1, 'minute:board_join');
    expect(rt.acks.first.$2, {'meeting_id': 7, 'ticket': 'TICKET'});
    expect(c.status, 'live');
    expect(c.canEdit, isTrue);
    expect(c.people, ['สมชาย', 'แขก']);
    c.put('note', 'note-1', {'title': 'วาระ', 'text': 'งบ Q1'});
    expect(c.items.where((x) => x.kind == 'note').single.pending, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(rt.ops.single, {'t': 'put', 'kind': 'note', 'uid': 'note-1', 'data': {'title': 'วาระ', 'text': 'งบ Q1'}});
    expect(c.items.where((x) => x.kind == 'note').single.pending, isFalse);
    // someone else
    rt.push('minute:board', {
      'meeting_id': 7,
      'items': [
        {'uid': 'stk-9', 'kind': 'sticky', 'data': {'text': 'จากแขก', 'col': 'col-ideas', 'color': 'pink'}, 'version': 1, 'author': 'แขก'},
      ],
      'cleared': [],
    });
    rt.push('minute:board', {'meeting_id': 8, 'items': [{'uid': 'x', 'kind': 'note', 'data': {}, 'version': 1}]});
    rt.push('minute:board_ink', {'meeting_id': 7, 'uid': 'str-live', 'page': 0, 'color': '#ef4444', 'w': 3, 'tool': 'pen', 'pts': [0.1, 0.1, 0.2, 0.2], 'by': {'name': 'แขก'}});
    rt.push('minute:board_ink', {'meeting_id': 7, 'uid': 'str-live', 'page': 0, 'tool': 'pen', 'pts': [0.3, 0.3], 'by': {'name': 'แขก'}});
    rt.push('minute:board_presence', {'meeting_id': 7, 'people': [{'name': 'สมชาย'}]});
    await Future<void>.delayed(Duration.zero);
    expect(c.items.any((x) => x.uid == 'stk-9'), isTrue);
    expect(c.items.any((x) => x.uid == 'x'), isFalse, reason: 'another meeting');
    expect(c.inks['str-live']!.pts, [0.1, 0.1, 0.2, 0.2, 0.3, 0.3]);
    expect(c.people, ['สมชาย']);
    rt.push('minute:board_ink', {'meeting_id': 7, 'uid': 'str-live', 'done': true});
    await Future<void>.delayed(Duration.zero);
    expect(c.inks, isEmpty);
    // live ink out
    c.ink({'uid': 'str-1', 'page': 0, 'pts': [0.5, 0.5]});
    expect(rt.emits.last.$1, 'minute:board_ink');
    expect(rt.emits.last.$2, {'meeting_id': 7, 'uid': 'str-1', 'page': 0, 'pts': [0.5, 0.5]});
    // offline: ops wait, then go on reconnect
    rt.up = false;
    c.put('check', 'chk-1', {'text': 'ส่งสัญญา'});
    await Future<void>.delayed(Duration.zero);
    expect(c.pendingOps, 1);
    expect(c.items.where((x) => x.kind == 'check').single.str('text'), 'ส่งสัญญา', reason: 'shown at once');
    rt.up = true;
    rt.push(RealtimeService.connectedEvent, const {});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.pendingOps, 0);
    expect(rt.ops.last['uid'], 'chk-1');
    c.dispose();
    expect(rt.emits.last.$1, 'minute:board_leave');
    expect(rt.emits.last.$2, {'meeting_id': 7});
  });

  testWidgets('workspace: notes, checklist with @owner and ticks, board vote, sketch stroke + eraser', (t) async {
    final rt = _Rt();
    final c = MinuteBoardController(meetingId: '7', ticket: 'T', realtime: rt);
    await c.start();
    await _pumpWs(t, c);
    expect(find.text('ซิงก์สด'), findsOneWidget);
    expect(find.text('จดโน้ตร่วมกัน'), findsOneWidget);
    // notes
    await t.tap(find.byKey(const ValueKey('ws-add-note')));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('ws-note-text')), '1. งบการตลาด');
    await t.pump(const Duration(milliseconds: 500));
    expect(rt.ops.last['data'], {'text': '1. งบการตลาด'});
    // a remote edit of the note shows up
    final uid = c.items.firstWhere((x) => x.kind == 'note').uid;
    rt.push('minute:board', {'meeting_id': 7, 'items': [{'uid': uid, 'kind': 'note', 'data': {'title': 'วาระ', 'text': '1. งบการตลาด\n2. เปิดตัวสินค้า'}, 'version': 5, 'author': 'สมชาย', 'updated_by': 'แขก'}]});
    await t.pump();
    expect(find.text('1. งบการตลาด'), findsOneWidget, reason: 'while I am typing my text stays');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pump();
    rt.push('minute:board', {'meeting_id': 7, 'items': [{'uid': uid, 'kind': 'note', 'data': {'title': 'วาระ', 'text': '1. งบการตลาด\n2. เปิดตัวสินค้า'}, 'version': 6, 'author': 'สมชาย', 'updated_by': 'แขก'}]});
    await t.pump();
    expect(find.text('1. งบการตลาด\n2. เปิดตัวสินค้า'), findsOneWidget);
    expect(find.textContaining('แก้ล่าสุด แขก'), findsOneWidget);
    // checklist
    await t.tap(find.byKey(const ValueKey('ws-tab-1')));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('ws-check-input')), 'ส่งใบเสนอราคา @สมชาย');
    await t.tap(find.byKey(const ValueKey('ws-check-add')));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('ws-check-input')), 'จองห้อง');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(rt.ops.where((o) => o['kind'] == 'check').first['data'], {'text': 'ส่งใบเสนอราคา', 'assignee': 'สมชาย'});
    expect(find.text('@สมชาย'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ws-check-box')).first);
    await t.pump();
    expect(rt.ops.last['data'], {'done': true});
    expect(find.text('เสร็จแล้ว 1/2'), findsOneWidget);
    // board
    await t.tap(find.byKey(const ValueKey('ws-tab-2')));
    await t.pump();
    expect(find.text('ไอเดีย'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ws-add-sticky-col-ideas')));
    await t.pump();
    final stk = c.items.firstWhere((x) => x.kind == 'sticky');
    expect(stk.str('col'), 'col-ideas');
    await t.tap(find.byKey(ValueKey('ws-vote-${stk.uid}')));
    await t.pump();
    expect(rt.ops.last['data'], {'votes': ['u1']});
    // sketch: draw, then erase it
    await t.tap(find.byKey(const ValueKey('ws-tab-3')));
    await t.pump();
    final canvas = find.byKey(const ValueKey('ws-canvas'));
    final r = t.getRect(canvas);
    final g = await t.startGesture(r.topLeft + Offset(r.width * 0.2, r.height * 0.5));
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(r.topLeft + Offset(r.width * (0.2 + i * 0.05), r.height * 0.5));
      await t.pump(const Duration(milliseconds: 70));
    }
    await g.up();
    await t.pump();
    expect(rt.emits.where((e) => e.$1 == 'minute:board_ink').length, greaterThan(2), reason: 'others see it while I draw');
    final stroke = rt.ops.lastWhere((o) => o['kind'] == 'stroke');
    expect((stroke['data'] as Map)['tool'], 'pen');
    expect(((stroke['data'] as Map)['pts'] as List).length, greaterThanOrEqualTo(4));
    expect(c.items.where((x) => x.kind == 'stroke'), hasLength(1));
    await t.tap(find.byKey(const ValueKey('ws-tool-eraser')));
    await t.pump();
    await t.tapAt(r.topLeft + Offset(r.width * 0.45, r.height * 0.5));
    await t.pump();
    expect(rt.ops.last, {'t': 'del', 'uid': stroke['uid']});
    expect(c.items.where((x) => x.kind == 'stroke'), isEmpty);
    c.dispose();
  });

  testWidgets('read-only guests see the workspace without editing', (t) async {
    final rt = _Rt()..joinAnswer = {..._Rt().joinAnswer, 'can_edit': false};
    final c = MinuteBoardController(meetingId: '7', ticket: 'T', realtime: rt);
    await c.start();
    await _pumpWs(t, c, b: Brightness.dark);
    expect(find.text('ดูอย่างเดียว'), findsOneWidget);
    expect(find.byKey(const ValueKey('ws-add-note')), findsNothing);
    await t.tap(find.byKey(const ValueKey('ws-tab-1')));
    await t.pump();
    expect(find.byKey(const ValueKey('ws-check-input')), findsNothing);
    c.dispose();
  });

  test('room session: pin from the join answer, room metadata and stage messages; my pin and my own view', () async {
    final rt = _Rt();
    final media = _Media();
    final s = MinuteRoomSession(
      meetingId: '5',
      roomCode: 'abc-defg-hij',
      ticket: 'T',
      identity: 'g-1',
      role: 'guest',
      name: 'แขก',
      media: media,
      realtime: rt,
      stage: {'pin': {'identity': 'u1', 'source': 'screen'}, 'by': 'สมชาย'},
      boardMode: 'all',
    );
    expect(s.stagePin?.identity, 'u1');
    expect(s.boardOn, isTrue);
    await s.start(url: 'wss://x', token: 'tok');
    expect(rt.acks.map((a) => a.$1), contains('minute:board_join'));
    s.setStageOverride(true);
    media.setMeta('{"stage":{"pin":{"source":"board"},"by":"สมชาย"}}');
    expect(s.stagePin?.source, 'board');
    expect(s.stageOverride, isFalse, reason: 'a new pin brings everyone back to it');
    media.data0.add(('สมชาย', 'stage', {'type': 'stage', 'stage': {'pin': null, 'by': 'สมชาย'}}));
    await Future<void>.delayed(Duration.zero);
    expect(s.stagePin, isNull);
    s.pinForMe(const StagePin(identity: 'u2'));
    expect(s.localPin?.identity, 'u2');
    final off = MinuteRoomSession(meetingId: '5', roomCode: 'c', ticket: 'T', identity: 'g', role: 'guest', name: 'x', media: _Media(), realtime: _Rt(), boardMode: 'off');
    expect(off.boardOn, isFalse);
    expect(roomInitials('ธนา (ฝ่ายขาย)'), 'ธน');
    expect(roomInitials('Ann Lee [guest]'), 'AL');
    await s.leave();
    s.dispose();
    off.dispose();
  });

  testWidgets('room: the host pinned the board → everyone sees the live sketch on the stage', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final rt = _Rt();
    final s = MinuteRoomSession(
      meetingId: '5',
      roomCode: 'abc-defg-hij',
      ticket: 'T',
      identity: 'g-1',
      role: 'guest',
      name: 'แขก',
      media: _Media(),
      realtime: rt,
      stage: {'pin': {'source': 'board'}, 'by': 'สมชาย'},
    );
    await t.pumpWidget(MaterialApp(home: MinuteRoomScreen(session: s, url: 'wss://x', token: 'tok', title: 'ประชุมทีมขาย')));
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('room-stage-board')), findsOneWidget);
    expect(find.text('ผู้จัดปักหมุดพื้นที่ทำงานให้ทุกคน'), findsOneWidget);
    expect(find.byKey(const ValueKey('stage-my-view')), findsOneWidget, reason: 'guests can switch to their own view');
    expect(find.byKey(const ValueKey('room-workspace')), findsOneWidget);
    // a stroke from the host appears on the stage
    rt.push('minute:board', {'meeting_id': 5, 'items': [{'uid': 'str-1', 'kind': 'stroke', 'data': {'page': 0, 'pts': [0.1, 0.1, 0.9, 0.9], 'color': '#ef4444', 'w': 4}, 'version': 1}]});
    await t.pump();
    expect(s.board.items.where((x) => x.kind == 'stroke'), hasLength(1));
    await t.tap(find.byKey(const ValueKey('stage-my-view')));
    await t.pump();
    expect(find.byKey(const ValueKey('room-stage-board')), findsNothing);
    expect(find.byKey(const ValueKey('stage-back')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('stage-back')));
    await t.pump();
    expect(find.byKey(const ValueKey('room-stage-board')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  });
}

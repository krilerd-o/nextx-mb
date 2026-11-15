import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/minutes/minute_board.dart';
import '../api_client.dart';
import '../realtime_service.dart';

/// Someone else's stroke while they draw (not stored).
class LiveInk {
  const LiveInk({required this.uid, required this.page, required this.color, required this.w, required this.tool, required this.pts, required this.by, required this.at});
  final String uid;
  final int page;
  final String color;
  final double w;
  final String tool;
  final List<double> pts;
  final String by;
  final DateTime at;
}

/// Realtime meeting workspace over Socket.IO (`minute:board_*`); REST when the socket is down
/// (signed-in users). Room guests pass the room ticket.
class MinuteBoardController extends ChangeNotifier {
  MinuteBoardController({required this.meetingId, this.ticket, RealtimeService? realtime, this.api}) : _rt = realtime ?? RealtimeService.instance;

  final String meetingId;
  final String? ticket;
  final ApiClient? api;
  final RealtimeService _rt;

  List<BoardItem> items = const [];
  bool canEdit = false;
  List<String> people = const [];
  String status = 'connecting'; // connecting | live | offline | error
  String? error;
  String? myIdentity;
  String myName = '';
  final inks = <String, LiveInk>{};

  final _queue = <Map<String, dynamic>>[];
  bool _joined = false;
  bool _sending = false;
  bool _disposed = false;
  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _sweep;

  int get _mid => int.tryParse(meetingId) ?? 0;

  Future<void> start() async {
    _sub = _rt.events.listen(_onEvent);
    _rt.addListener(_onConnection);
    if (ticket == null && api != null) {
      // Snapshot first (fast), the socket then keeps it live.
      try {
        final r = await api!.getMinuteBoard(meetingId);
        if (!_joined) {
          items = mergeBoard(items, [for (final j in (r['items'] as List? ?? const [])) BoardItem.fromJson(Map<String, dynamic>.from(j as Map))]);
          canEdit = r['can_edit'] == true;
          _notify();
        }
      } catch (_) {}
    }
    await _join();
  }

  Future<void> _join() async {
    final a = await _rt.emitAck('minute:board_join', {'meeting_id': _mid, 'ticket': ?ticket});
    if (_disposed) return;
    if (a['ok'] != true) {
      _joined = false;
      status = a['error'] == 'no_socket' || a['error'] == 'timeout' ? 'offline' : 'error';
      error = '${a['error'] ?? ''}';
      _notify();
      return;
    }
    _joined = true;
    final fresh = [for (final j in (a['items'] as List? ?? const [])) BoardItem.fromJson(Map<String, dynamic>.from(j as Map))];
    items = mergeBoard(items.where((x) => x.pending).toList(), fresh);
    canEdit = a['can_edit'] == true;
    people = [for (final p in (a['people'] as List? ?? const [])) '${(p as Map)['name'] ?? ''}'];
    final me = a['me'];
    if (me is Map) {
      myIdentity = me['identity'] as String?;
      myName = '${me['name'] ?? ''}';
    }
    status = 'live';
    _notify();
    unawaited(_flush());
  }

  /// Drop live strokes whose author went quiet (left mid-stroke); runs only while there are any.
  void _armSweep() {
    _sweep ??= Timer.periodic(const Duration(seconds: 2), (_) {
      final before = inks.length;
      inks.removeWhere((_, v) => DateTime.now().difference(v.at) > const Duration(seconds: 4));
      if (inks.isEmpty) {
        _sweep?.cancel();
        _sweep = null;
      }
      if (inks.length != before) _notify();
    });
  }

  void _onEvent(RealtimeEvent e) {
    final d = e.data;
    if (e.type == RealtimeService.connectedEvent) {
      unawaited(_join());
      return;
    }
    if ((d['meeting_id'] as num?)?.toInt() != _mid) return;
    switch (e.type) {
      case 'minute:board':
        items = mergeBoard(
          items,
          [for (final j in (d['items'] as List? ?? const [])) BoardItem.fromJson(Map<String, dynamic>.from(j as Map))],
          cleared: [for (final p in (d['cleared'] as List? ?? const [])) (p as num).toInt()],
        );
      case 'minute:board_presence':
        people = [for (final p in (d['people'] as List? ?? const [])) '${(p as Map)['name'] ?? ''}'];
      case 'minute:board_ink':
        final uid = '${d['uid'] ?? ''}';
        if (d['done'] == true) {
          inks.remove(uid);
        } else {
          final pts = [for (final v in (d['pts'] as List? ?? const [])) (v as num).toDouble()];
          final tool = '${d['tool'] ?? 'pen'}';
          final prev = inks[uid];
          inks[uid] = LiveInk(
            uid: uid,
            page: (d['page'] as num?)?.toInt() ?? 0,
            color: '${d['color'] ?? '#111827'}',
            w: (d['w'] as num?)?.toDouble() ?? 3,
            tool: tool,
            pts: kShapeTools.contains(tool) || prev == null ? pts : [...prev.pts, ...pts],
            by: '${(d['by'] as Map?)?['name'] ?? ''}',
            at: DateTime.now(),
          );
          _armSweep();
        }
      default:
        return;
    }
    _notify();
  }

  // ── ops

  void send(List<Map<String, dynamic>> ops) {
    for (final op in ops) {
      items = applyBoardOp(items, op, me: myName, myIdentity: myIdentity);
    }
    _notify();
    _queue.addAll(ops);
    unawaited(_flush());
  }

  void put(String kind, String uid, Map<String, dynamic> data, {double? pos}) => send([
    {'t': 'put', 'kind': kind, 'uid': uid, 'data': data, 'pos': ?pos},
  ]);
  void del(String uid) => send([
    {'t': 'del', 'uid': uid},
  ]);
  void clearPage(int page) => send([
    {'t': 'clear', 'page': page},
  ]);

  void ink(Map<String, dynamic> p) {
    if (_joined) _rt.emit('minute:board_ink', {'meeting_id': _mid, ...p});
  }

  Future<void> _flush() async {
    if (_sending || _queue.isEmpty) return;
    _sending = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final ops = _queue.take(100).toList();
        if (_joined && _rt.connected) {
          final a = await _rt.emitAck('minute:board_op', {'meeting_id': _mid, 'ops': ops});
          if (a['ok'] == true) {
            _queue.removeRange(0, ops.length);
            _applyAnswer(a);
            continue;
          }
          if (a['error'] == 'read_only') {
            _queue.clear();
            canEdit = false;
            _notify();
          }
          break; // keep the ops for the next (re)connect
        } else if (ticket == null && api != null) {
          try {
            final r = await api!.postMinuteBoardOps(meetingId, ops);
            _queue.removeRange(0, ops.length);
            _applyAnswer(r);
          } catch (_) {
            break;
          }
        } else {
          break;
        }
      }
    } finally {
      _sending = false;
    }
  }

  void _applyAnswer(Map<String, dynamic> a) {
    items = mergeBoard(
      items,
      [for (final j in (a['items'] as List? ?? const [])) BoardItem.fromJson(Map<String, dynamic>.from(j as Map))],
      cleared: [for (final p in (a['cleared'] as List? ?? const [])) (p as num).toInt()],
    );
    _notify();
  }

  void _onConnection() {
    if (_rt.connected || !_joined) return;
    _joined = false;
    status = 'offline';
    _notify();
  }

  int get pendingOps => _queue.length;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sweep?.cancel();
    _sub?.cancel();
    _rt.removeListener(_onConnection);
    _rt.emit('minute:board_leave', {'meeting_id': _mid});
    super.dispose();
  }
}

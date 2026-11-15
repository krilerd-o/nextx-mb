import 'dart:math' as math;

/// Meeting workspace (โน้ต · เช็กลิสต์ · บอร์ด · สเก็ตช์) — the same items and ops as NEXTX
/// `services/aiMinutes/minuteBoard.js` and the web `lib/minuteBoard.js`.
///
/// Items: note {title, text} · check {text, done, assignee, due, task_id} · col {title, color}
/// · sticky {text, color, col, votes} · stroke {page, color, w, tool, pts:[x,y,…] 0..1}.
/// Ops: {t:'put', kind, uid, data, pos?} · {t:'del', uid} · {t:'clear', page}.
class BoardItem {
  const BoardItem({
    required this.uid,
    required this.kind,
    this.data = const {},
    this.pos = 0,
    this.version = 0,
    this.author,
    this.authorIdentity,
    this.updatedBy,
    this.pending = false,
    this.deleted = false,
  });

  final String uid;
  final String kind;
  final Map<String, dynamic> data;
  final double pos;
  final int version;
  final String? author;
  final String? authorIdentity;
  final String? updatedBy;
  final bool pending;
  final bool deleted;

  factory BoardItem.fromJson(Map<String, dynamic> j) => BoardItem(
    uid: '${j['uid'] ?? ''}',
    kind: '${j['kind'] ?? ''}',
    data: j['data'] is Map ? Map<String, dynamic>.from(j['data'] as Map) : const {},
    pos: (j['pos'] as num?)?.toDouble() ?? 0,
    version: (j['version'] as num?)?.toInt() ?? 0,
    author: j['author'] as String?,
    authorIdentity: j['author_identity'] as String?,
    updatedBy: j['updated_by'] as String?,
    deleted: j['deleted'] == true,
  );

  BoardItem copyWith({Map<String, dynamic>? data, double? pos, String? updatedBy, bool? pending}) => BoardItem(
    uid: uid,
    kind: kind,
    data: data ?? this.data,
    pos: pos ?? this.pos,
    version: version,
    author: author,
    authorIdentity: authorIdentity,
    updatedBy: updatedBy ?? this.updatedBy,
    pending: pending ?? this.pending,
  );

  String str(String k) => '${data[k] ?? ''}';
  bool get done => data['done'] == true;
  int get page => (data['page'] as num?)?.toInt() ?? 0;
  List<double> get pts => [for (final v in (data['pts'] as List? ?? const [])) (v as num).toDouble()];
  List<String> get votes => [for (final v in (data['votes'] as List? ?? const [])) '$v'];
}

const kStickyColors = ['yellow', 'pink', 'blue', 'green', 'purple', 'orange'];
const kPenColors = [0xFF111827, 0xFFEF4444, 0xFFF59E0B, 0xFF10B981, 0xFF3B82F6, 0xFF8B5CF6, 0xFFEC4899, 0xFFFFFFFF];
const kShapeTools = ['line', 'rect', 'ellipse', 'arrow'];
const kSketchRatio = 16 / 9;

int _seq = 0;
final _rnd = math.Random();
String newBoardUid(String prefix) {
  _seq = (_seq + 1) % 1000000;
  final r = List.generate(6, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_rnd.nextInt(36)]).join();
  final s = '$prefix-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_seq.toRadixString(36)}$r';
  return s.length > 40 ? s.substring(0, 40) : s;
}

int _byPos(BoardItem a, BoardItem b) {
  final c = a.pos.compareTo(b.pos);
  return c != 0 ? c : a.uid.compareTo(b.uid);
}

/// Fold server changes in: newer versions replace, deleted go, cleared pages lose their strokes.
List<BoardItem> mergeBoard(List<BoardItem> list, Iterable<BoardItem> changes, {Iterable<int> cleared = const []}) {
  final map = {for (final x in list) x.uid: x};
  for (final page in cleared) {
    map.removeWhere((_, v) => v.kind == 'stroke' && v.page == page);
  }
  for (final c in changes) {
    if (c.uid.isEmpty) continue;
    final prev = map[c.uid];
    if (prev != null && prev.version > c.version && !prev.pending) continue;
    if (c.deleted) {
      map.remove(c.uid);
    } else {
      map[c.uid] = c;
    }
  }
  return map.values.toList()..sort(_byPos);
}

double nextBoardPos(List<BoardItem> list, String kind) =>
    list.where((x) => x.kind == kind).fold<double>(0, (m, x) => math.max(m, x.pos)) + 1;

double boardPosBetween(double? a, double? b) {
  if (a == null && b == null) return 1;
  if (a == null) return b! - 1;
  if (b == null) return a + 1;
  return (a + b) / 2;
}

/// My own op, applied before the server answers.
List<BoardItem> applyBoardOp(List<BoardItem> list, Map<String, dynamic> op, {String? me, String? myIdentity}) {
  switch (op['t']) {
    case 'clear':
      return mergeBoard(list, const [], cleared: [(op['page'] as num?)?.toInt() ?? 0]);
    case 'del':
      return list.where((x) => x.uid != op['uid']).toList();
    case 'put':
      final uid = '${op['uid']}';
      final kind = '${op['kind']}';
      final data = Map<String, dynamic>.from(op['data'] as Map? ?? const {});
      final prev = list.where((x) => x.uid == uid).firstOrNull;
      final pos = (op['pos'] as num?)?.toDouble() ?? prev?.pos ?? nextBoardPos(list, kind);
      final item = prev != null
          ? prev.copyWith(data: {...prev.data, ...data}, pos: pos, updatedBy: me, pending: true)
          : BoardItem(uid: uid, kind: kind, data: {..._defaults(kind), ...data}, pos: pos, author: me, authorIdentity: myIdentity, pending: true);
      return [...list.where((x) => x.uid != uid), item]..sort(_byPos);
  }
  return list;
}

Map<String, dynamic> _defaults(String kind) => switch (kind) {
  'check' => {'done': false},
  'sticky' => {'color': 'yellow', 'col': 'col-ideas'},
  _ => const {},
};

({int done, int total, int pct}) checklistProgress(List<BoardItem> list) {
  final checks = list.where((x) => x.kind == 'check' && x.str('text').trim().isNotEmpty).toList();
  final done = checks.where((x) => x.done).length;
  return (done: done, total: checks.length, pct: checks.isEmpty ? 0 : (done * 100 / checks.length).round());
}

int sketchPageCount(List<BoardItem> list, {int extra = 0}) {
  final pages = list.where((x) => x.kind == 'stroke').map((x) => x.page);
  return math.max(math.max(1, pages.isEmpty ? 1 : pages.reduce(math.max) + 1), extra);
}

/// "ส่งสัญญา @สมชาย" → (text, assignee).
(String, String?) parseCheckInput(String input) {
  final t = input.trim();
  final m = RegExp(r'^(.*?)\s+@(\S+)\s*$').firstMatch(t);
  return m == null ? (t, null) : (m.group(1)!.trim(), m.group(2));
}

/* ───────────── sketch geometry (0..1 page units) ───────────── */

List<double> simplifyPoints(List<double> pts, {double eps = 0.0025}) {
  if (pts.length <= 4) return [...pts];
  final out = [pts[0], pts[1]];
  for (var i = 2; i + 1 < pts.length; i += 2) {
    final dx = pts[i] - out[out.length - 2];
    final dy = pts[i + 1] - out[out.length - 1];
    if (dx * dx + dy * dy >= eps * eps || i + 2 >= pts.length) out.addAll([pts[i], pts[i + 1]]);
  }
  return out;
}

List<double> shapePoints(String? tool, List<double> pts) {
  if (!kShapeTools.contains(tool) || pts.length < 4) return pts;
  final x0 = pts[0], y0 = pts[1], x1 = pts[pts.length - 2], y1 = pts[pts.length - 1];
  switch (tool) {
    case 'line':
      return [x0, y0, x1, y1];
    case 'rect':
      return [x0, y0, x1, y0, x1, y1, x0, y1, x0, y0];
    case 'arrow':
      final ang = math.atan2(y1 - y0, (x1 - x0) * kSketchRatio);
      const len = 0.025;
      double hx(double a) => x1 - math.cos(a) * len / kSketchRatio;
      double hy(double a) => y1 - math.sin(a) * len;
      return [x0, y0, x1, y1, hx(ang - 0.45), hy(ang - 0.45), x1, y1, hx(ang + 0.45), hy(ang + 0.45)];
  }
  final cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, rx = (x1 - x0).abs() / 2, ry = (y1 - y0).abs() / 2;
  return [for (var i = 0; i <= 36; i++) ...[cx + math.cos(i / 36 * math.pi * 2) * rx, cy + math.sin(i / 36 * math.pi * 2) * ry]];
}

double strokeDistance(BoardItem s, double x, double y) {
  final pts = shapePoints(s.data['tool'] as String?, s.pts);
  if (pts.length < 2) return double.infinity;
  double sx(double v) => v * kSketchRatio;
  if (pts.length == 2) return math.sqrt(math.pow(sx(pts[0] - x), 2) + math.pow(pts[1] - y, 2));
  var best = double.infinity;
  for (var i = 0; i + 3 < pts.length; i += 2) {
    final ax = sx(pts[i]), ay = pts[i + 1], bx = sx(pts[i + 2]), by = pts[i + 3], px = sx(x);
    final dx = bx - ax, dy = by - ay;
    final l2 = dx * dx + dy * dy;
    final t = l2 == 0 ? 0.0 : (((px - ax) * dx + (y - ay) * dy) / l2).clamp(0.0, 1.0);
    best = math.min(best, math.sqrt(math.pow(px - (ax + t * dx), 2) + math.pow(y - (ay + t * dy), 2)));
  }
  return best;
}

BoardItem? strokeAt(List<BoardItem> list, int page, double x, double y, {double tol = 0.03}) {
  final strokes = list.where((s) => s.kind == 'stroke' && s.page == page).toList();
  for (final s in strokes.reversed) {
    if (strokeDistance(s, x, y) <= tol + ((s.data['w'] as num?)?.toDouble() ?? 3) / 2000) return s;
  }
  return null;
}

/* ───────────── stage (pin) ───────────── */

class StagePin {
  const StagePin({this.identity, this.source = 'camera', this.by});
  final String? identity;
  final String source; // camera | screen | board
  final String? by;

  static StagePin? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final pin = raw['pin'] is Map ? raw['pin'] as Map : raw;
    if (pin['source'] == null && pin['identity'] == null) return null;
    return StagePin(identity: pin['identity'] as String?, source: '${pin['source'] ?? 'camera'}', by: (raw['by'] ?? pin['by']) as String?);
  }

  Map<String, dynamic> toJson({String? name}) => {'source': source, 'identity': ?identity, 'name': ?name};
}

/// What fills the stage: the host's pin, then my pin, then a screen share; null = grid.
({String? identity, String source, String by})? resolveStage({StagePin? stagePin, StagePin? localPin, bool override = false, String? presenter, required Set<String> present}) {
  bool ok(StagePin? p) => p != null && (p.source == 'board' || present.contains(p.identity));
  if (ok(stagePin) && !override) return (identity: stagePin!.identity, source: stagePin.source, by: 'host');
  if (ok(localPin)) return (identity: localPin!.identity, source: localPin.source, by: 'me');
  if (presenter != null && present.contains(presenter)) return (identity: presenter, source: 'screen', by: 'share');
  return null;
}

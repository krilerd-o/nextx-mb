import 'workspace_models.dart';

/// Sort keys for the Task list in an Epic / the Subtask list in a Task (same as the web table).
const kWsChildSortKeys = ['no', 'title', 'priority', 'assignee', 'due', 'status', 'updated', 'manual'];

/// Thai labels (wrap with tr() when shown).
const kWsChildSortLabels = {
  'no': 'เลขที่',
  'title': 'ชื่องาน',
  'priority': 'ความสำคัญ',
  'assignee': 'ผู้รับผิดชอบ',
  'due': 'กำหนดส่ง',
  'status': 'สถานะ',
  'updated': 'อัปเดตล่าสุด',
  'manual': 'เรียงเอง (ลากได้)',
};

const _priorityRank = {'highest': 1, 'high': 2, 'medium': 3, 'low': 4, 'lowest': 5};

int _manualCmp(Map<String, dynamic> a, Map<String, dynamic> b) {
  final ao = num.tryParse('${a['sort_order']}');
  final bo = num.tryParse('${b['sort_order']}');
  if (ao != null && bo != null && ao != bo) return ao.compareTo(bo);
  if (ao != null && bo == null) return -1;
  if (ao == null && bo != null) return 1;
  return (num.tryParse('${a['id']}') ?? 0).compareTo(num.tryParse('${b['id']}') ?? 0);
}

/// Sorted copy. Empty values always go last; ties keep the manual order.
/// Default (what the user asked for): item number, low → high.
List<Map<String, dynamic>> wsSortChildren(
  List<Map<String, dynamic>> rows,
  String key,
  bool asc, {
  List<WsStatus> statuses = const [],
  Map<String, String> users = const {},
}) {
  final base = [...rows]..sort(_manualCmp);
  if (key == 'manual') return base;
  final pos = {for (var i = 0; i < base.length; i++) '${base[i]['id']}': i};
  final statusSeq = {for (final s in statuses) s.id: s.sequence};
  Comparable? val(Map<String, dynamic> r) {
    switch (key) {
      case 'no':
        return num.tryParse('${r['item_no']}');
      case 'title':
        final t = wsTitle(r).trim().toLowerCase();
        return t.isEmpty ? null : t;
      case 'priority':
        return _priorityRank['${r['priority'] ?? 'medium'}'.toLowerCase()];
      case 'assignee':
        final id = r['assignee_id'];
        if (id == null || '$id'.isEmpty) return null;
        return (users['$id'] ?? '#$id').toLowerCase();
      case 'due':
        final d = '${r['due_date'] ?? ''}';
        return d.length >= 10 ? d.substring(0, 10) : null;
      case 'status':
        return statusSeq['${r['status_id']}'];
      case 'updated':
        final u = '${r['updated_at'] ?? ''}';
        return u.isEmpty ? null : u;
    }
    return null;
  }

  return base
    ..sort((a, b) {
      final va = val(a);
      final vb = val(b);
      if (va == null && vb == null) return pos['${a['id']}']!.compareTo(pos['${b['id']}']!);
      if (va == null) return 1;
      if (vb == null) return -1;
      var c = va.compareTo(vb);
      if (!asc) c = -c;
      return c != 0 ? c : pos['${a['id']}']!.compareTo(pos['${b['id']}']!);
    });
}

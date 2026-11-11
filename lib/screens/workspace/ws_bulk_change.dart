import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_icons.dart';
import '../fsm/service_more.dart' show pickWorkspaceBoard;

/// Skip reasons from the server, in Thai (same meaning as the web).
String bulkReasonText(Object? r) => tr(switch ('$r') {
  'no_permission' || 'forbidden' => 'ไม่มีสิทธิ์',
  'not_found' => 'ไม่พบรายการ',
  'same_board' => 'อยู่บอร์ดนี้อยู่แล้ว',
  'no_change' => 'ไม่มีอะไรเปลี่ยน',
  'is_subtask' => 'เป็นงานย่อย (ย้ายไปกับงานแม่)',
  _ => '$r',
});

/// Bulk change like the web's wizard: choose → configure → preview →
/// run as a server job (progress, cancel) → undo the whole batch.
Future<bool> openWorkspaceBulkChange(BuildContext context, {required List<(String, String)> items, required String boardId}) async {
  final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => WorkspaceBulkChangeScreen(items: items, boardId: boardId)));
  return r == true;
}

class WorkspaceBulkChangeScreen extends StatefulWidget {
  const WorkspaceBulkChangeScreen({super.key, required this.items, required this.boardId});
  final List<(String, String)> items;
  final String boardId;

  @override
  State<WorkspaceBulkChangeScreen> createState() => _WorkspaceBulkChangeScreenState();
}

class _WorkspaceBulkChangeScreenState extends State<WorkspaceBulkChangeScreen> {
  String? _op; // move | duplicate | watch | unwatch | delete
  ({int id, String name, String code})? _target;
  Map<String, dynamic>? _preview;
  final Map<String, String> _statusMap = {};
  List<Map<String, dynamic>> _targetStatuses = const [];
  String _scope = 'children';
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _job;
  Timer? _poll;
  bool _changed = false;

  ApiClient get _api => context.read<AppConfig>().apiClient;
  List<Map<String, String>> get _itemRefs => [for (final (t, id) in widget.items) {'type': t, 'id': id}];

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Map<String, dynamic> _options() => switch (_op) {
    'move' => {
      'target_board_id': _target?.id,
      'status_map': {for (final e in _statusMap.entries) e.key: int.tryParse(e.value) ?? e.value},
      'release': 'match',
      'milestone': 'match',
      'components': 'match',
      'children_mode': 'subtask',
    },
    'duplicate' => {
      'scope': _scope,
      'copy': {'comments': false, 'attachments': true, 'watchers': true, 'checklist': true, 'links': false, 'components': true},
      'status': 'initial',
      'title_prefix': '',
      'title_suffix': ' (copy)',
      'link_original': true,
      if (_target != null) 'target_board_id': _target!.id,
      if (_target != null) 'status_map': {for (final e in _statusMap.entries) e.key: int.tryParse(e.value) ?? e.value},
    },
    'watch' || 'unwatch' => {'mode': _op, 'user_ids': [int.tryParse(context.read<AppConfig>().session.userId ?? '') ?? 0]},
    _ => const <String, dynamic>{},
  };

  String get _operation => _op == 'unwatch' ? 'watch' : _op!;

  Future<void> _doPreview() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await _api.previewWorkspaceBulk({'operation': _operation, 'items': _itemRefs, 'options': _options()});
      final ts = p['target_statuses'];
      setState(() {
        _preview = p;
        _targetStatuses = ts is List ? [for (final x in ts) if (x is Map) Map<String, dynamic>.from(x)] : const [];
        for (final m in (p['status_mapping'] as List? ?? const [])) {
          if (m is Map && m['suggested'] != null) _statusMap.putIfAbsent('${m['source_status_id']}', () => '${m['suggested']}');
        }
      });
    } catch (e) {
      setState(() => _error = tr(formatApiError(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run() async {
    final p = _preview;
    final affected = (p?['affected_total'] as num?) ?? widget.items.length;
    if (_op == 'delete' || (_op == 'move' && affected > 50)) {
      final word = _op == 'delete' ? tr('ลบ') : tr('ยืนยัน');
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${_opLabel(_op!)} $affected ${tr('รายการ')}'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${tr('พิมพ์')} "$word" ${tr('เพื่อยืนยัน')}'),
            TextField(key: const ValueKey('bulk-type-confirm'), controller: ctrl, autofocus: true),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim() == word), child: Text(tr('ยืนยัน'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api.startWorkspaceBulk({'operation': _operation, 'items': _itemRefs, 'options': _options()});
      final id = '${r['job_id'] ?? r['id'] ?? ''}';
      setState(() => _job = {'id': id, 'status': 'queued', 'total': r['total'] ?? widget.items.length, 'done': 0});
      _changed = true;
      _poll = Timer.periodic(const Duration(milliseconds: 1200), (_) => _tick(id));
    } catch (e) {
      setState(() => _error = tr(formatApiError(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _tick(String id) async {
    try {
      final j = await _api.getWorkspaceBulkJob(id);
      if (!mounted) return;
      setState(() => _job = j);
      if (const {'done', 'error', 'cancelled'}.contains('${j['status']}')) {
        _poll?.cancel();
        HapticFeedback.mediumImpact();
      }
    } catch (_) {}
  }

  Future<void> _undo() async {
    setState(() => _busy = true);
    try {
      final r = await _api.undoWorkspaceBulkJob('${_job!['id']}');
      final failed = (r['undo_failed'] as List?)?.length ?? 0;
      if (!mounted) return;
      setState(() => _job = {...?(r['job'] is Map ? Map<String, dynamic>.from(r['job'] as Map) : null), ..._job!, 'can_undo': false, 'undone_at': DateTime.now().toIso8601String()});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failed == 0 ? tr('เลิกทำทั้งชุดแล้ว') : '${tr('เลิกทำแล้ว แต่มีบางรายการไม่สำเร็จ')} ($failed)')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _opLabel(String op) => tr(switch (op) {
    'move' => 'ย้ายไปบอร์ดอื่น',
    'duplicate' => 'ทำซ้ำ (พร้อมงานย่อย)',
    'watch' => 'ติดตาม',
    'unwatch' => 'เลิกติดตาม',
    _ => 'ลบ',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final job = _job;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
        appBar: AppBar(
          title: Text('Bulk Change · ${widget.items.length} ${tr('รายการ')}'),
          leading: IconButton(icon: const Icon(NxI.x), onPressed: () => Navigator.pop(context, _changed)),
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (job != null) _jobView(theme, job) else ...[
            Text(tr('1. เลือกการทำงาน'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (op, icon) in const [('move', NxI.arrowRight), ('duplicate', NxI.copySimple), ('watch', NxI.eye), ('unwatch', NxI.eyeSlash), ('delete', NxI.trash)])
                ChoiceChip(
                  key: ValueKey('bulk-op-$op'),
                  avatar: Icon(icon, size: 16),
                  label: Text(_opLabel(op)),
                  selected: _op == op,
                  onSelected: (_) => setState(() {
                    _op = op;
                    _preview = null;
                    _statusMap.clear();
                  }),
                ),
            ]),
            if (_op == 'move' || _op == 'duplicate') ...[
              const SizedBox(height: 16),
              Text(tr('2. ตั้งค่า'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('bulk-target-board'),
                onPressed: () async {
                  final b = await pickWorkspaceBoard(context, title: tr('บอร์ดปลายทาง'));
                  if (b != null) {
                    setState(() {
                      _target = b;
                      _preview = null;
                      _statusMap.clear();
                    });
                  }
                },
                icon: const Icon(NxI.kanban, size: 18),
                label: Text(_target?.name ?? (_op == 'move' ? tr('เลือกบอร์ดปลายทาง') : tr('บอร์ดเดิม (แตะเพื่อเลือกบอร์ดอื่น)'))),
              ),
              if (_op == 'duplicate') ...[
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'self', label: Text(tr('เฉพาะรายการ'))),
                    ButtonSegment(value: 'children', label: Text(tr('พร้อมงานย่อย'))),
                    ButtonSegment(value: 'children_checklist', label: Text(tr('+ เช็กลิสต์'))),
                  ],
                  selected: {_scope},
                  onSelectionChanged: (s) => setState(() => _scope = s.first),
                ),
              ],
            ],
            if (_op != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                key: const ValueKey('bulk-preview'),
                onPressed: _busy || (_op == 'move' && _target == null) ? null : _doPreview,
                icon: const Icon(NxI.magnifyingGlass, size: 18),
                label: Text(tr('ดูตัวอย่างก่อนทำ')),
              ),
            ],
            if (_preview != null) _previewView(theme, _preview!),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: cs.error))),
        ]),
      ),
    );
  }

  Widget _previewView(ThemeData theme, Map<String, dynamic> p) {
    final cs = theme.colorScheme;
    final items = [for (final x in (p['items'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
    final skipped = items.where((x) => x['action'] == 'skip').toList();
    final mapping = [for (final x in (p['status_mapping'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
    final will = (p['will_change'] as num?) ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 16),
      Container(
        key: const ValueKey('bulk-preview-summary'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(16)),
        child: Text(
          '${tr('จะเปลี่ยน')} $will ${tr('รายการ')}'
          '${(p['with_parent'] as num? ?? 0) > 0 ? ' · ${tr('ไปพร้อมงานแม่')} ${p['with_parent']}' : ''}'
          '${skipped.isNotEmpty ? ' · ${tr('ข้าม')} ${skipped.length}' : ''}'
          ' · ${tr('รวมที่กระทบ')} ${p['affected_total'] ?? will}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      if (mapping.isNotEmpty && _targetStatuses.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(tr('จับคู่สถานะ'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
        for (final m in mapping)
          Row(children: [
            Expanded(child: Text('${(m['source_status'] is Map ? (m['source_status']['label_th'] ?? m['source_status']['name']) : m['source_status_id'])} (${m['count'] ?? 0})')),
            const Icon(NxI.arrowRight, size: 16),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _statusMap['${m['source_status_id']}'],
              hint: Text(tr('เลือก')),
              items: [for (final s in _targetStatuses) DropdownMenuItem(value: '${s['id']}', child: Text('${s['label_th'] ?? s['name'] ?? s['id']}'))],
              onChanged: (v) => setState(() => _statusMap['${m['source_status_id']}'] = v ?? ''),
            ),
          ]),
      ],
      if (skipped.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(tr('รายการที่ข้าม'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
        for (final x in skipped.take(20)) Text('• ${x['item_no'] ?? ''} ${x['title'] ?? ''} — ${bulkReasonText(x['reason'])}', style: theme.textTheme.bodySmall),
      ],
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const ValueKey('bulk-run'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: _op == 'delete' ? cs.error : null),
        onPressed: _busy || will <= 0 ? null : _run,
        icon: const Icon(NxI.play, size: 18),
        label: Text('${_opLabel(_op!)} $will ${tr('รายการ')}'),
      ),
    ]);
  }

  Widget _jobView(ThemeData theme, Map<String, dynamic> j) {
    final cs = theme.colorScheme;
    final st = '${j['status'] ?? ''}';
    final total = (j['total'] as num?) ?? widget.items.length;
    final done = (j['done'] as num?) ?? 0;
    final finished = const {'done', 'error', 'cancelled'}.contains(st);
    final skipped = [for (final x in (j['skipped'] as List? ?? const [])) if (x is Map) x];
    return Column(key: const ValueKey('bulk-job'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(finished ? (st == 'done' ? tr('เสร็จแล้ว') : st == 'cancelled' ? tr('ยกเลิกแล้ว') : tr('มีข้อผิดพลาด')) : tr('กำลังทำงาน…'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: total == 0 ? null : (done / total).clamp(0, 1).toDouble(), minHeight: 8)),
      const SizedBox(height: 8),
      Text('$done / $total · ${tr('สำเร็จ')} ${j['succeeded'] ?? '-'} · ${tr('ข้าม')} ${skipped.length}'),
      if ('${j['error'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${j['error']}', style: TextStyle(color: cs.error))),
      for (final x in skipped.take(20)) Text('• ${x['type']} #${x['id']} — ${bulkReasonText(x['reason'])}', style: theme.textTheme.bodySmall),
      const SizedBox(height: 16),
      if (!finished)
        OutlinedButton(key: const ValueKey('bulk-cancel'), onPressed: () => _api.cancelWorkspaceBulkJob('${j['id']}'), child: Text(tr('หยุด')))
      else ...[
        if (j['can_undo'] == true && j['undone_at'] == null)
          OutlinedButton.icon(key: const ValueKey('bulk-undo'), onPressed: _busy ? null : _undo, icon: const Icon(NxI.arrowCounterClockwise, size: 18), label: Text(tr('เลิกทำทั้งชุด (ภายใน 24 ชม.)'))),
        if (j['undone_at'] != null) Text(tr('เลิกทำแล้ว'), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        FilledButton(key: const ValueKey('bulk-done'), onPressed: () => Navigator.pop(context, true), child: Text(tr('เสร็จ'))),
      ],
    ]);
  }
}

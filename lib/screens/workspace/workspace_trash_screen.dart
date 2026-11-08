import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/workspace_models.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_refresh.dart';

/// Workspace trash (`/api/workspace/trash`): restore, or delete for good
/// when the server says this user may purge.
class WorkspaceTrashScreen extends StatefulWidget {
  const WorkspaceTrashScreen({super.key});

  @override
  State<WorkspaceTrashScreen> createState() => _WorkspaceTrashScreenState();
}

class _WorkspaceTrashScreenState extends State<WorkspaceTrashScreen> {
  static const _page = 30;
  final List<Map<String, dynamic>> _rows = [];
  int _total = 0;
  bool _canPurge = false;
  bool _loading = true;
  bool _more = false;
  String? _error;
  final Set<String> _busy = {};

  ApiClient get _api => context.read<AppConfig>().apiClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    setState(() {
      if (!append) _loading = true;
      _more = append;
      _error = null;
    });
    try {
      final r = await _api.getWorkspaceTrash(limit: _page, offset: append ? _rows.length : 0);
      if (!mounted) return;
      final list = extractMapList(r);
      setState(() {
        if (!append) _rows.clear();
        _rows.addAll(list);
        _total = wsInt(r['total']) ?? _rows.length;
        _canPurge = r['can_purge'] == true;
        _loading = false;
        _more = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = formatApiError(e);
          _loading = false;
          _more = false;
        });
      }
    }
  }

  Future<void> _restore(Map<String, dynamic> r) async {
    final id = '${r['id']}';
    setState(() => _busy.add(id));
    try {
      await _api.restoreWorkspaceTrash(id);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _rows.remove(r);
        _total = (_total - 1).clamp(0, 1 << 30);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('กู้คืน ${r['title'] ?? ''} แล้ว'))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _purge(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ลบถาวร?')),
        content: Text(tr('"${r['title'] ?? ''}" จะถูกลบถาวรและกู้คืนไม่ได้')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('ลบถาวร')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final id = '${r['id']}';
    setState(() => _busy.add(id));
    try {
      await _api.purgeWorkspaceTrash(id);
      if (!mounted) return;
      setState(() {
        _rows.remove(r);
        _total = (_total - 1).clamp(0, 1 << 30);
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  ({IconData icon, Color color, String label}) _kindStyle(String kind) => switch (kind) {
        'board' => (icon: NxI.kanban, color: const Color(0xFF6366F1), label: 'บอร์ด'),
        'epic' => (icon: NxI.lightning, color: const Color(0xFF8B5CF6), label: 'Epic'),
        'comment' => (icon: NxI.chatCircle, color: const Color(0xFF64748B), label: 'คอมเม้นท์'),
        'worklog' => (icon: NxI.clock, color: const Color(0xFF0EA5E9), label: 'การลงเวลา'),
        _ => (icon: NxI.checkSquare, color: const Color(0xFF3B82F6), label: 'งาน'),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NxScrollScaffold(
      header: NxAppHeader(title: 'ถังขยะ Workspace', subtitle: _loading ? null : tr('$_total รายการ')),
      body: NxRefresh(
        onRefresh: _load,
        child: _loading
            ? const NxSkeletonList()
            : _error != null
                ? ListView(children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(tr(_error!), textAlign: TextAlign.center),
                    ),
                  ])
                : _rows.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 80),
                        Icon(NxI.trash, size: 48, color: cs.outline),
                        const SizedBox(height: 12),
                        Center(child: Text(tr('ถังขยะว่าง'), style: theme.textTheme.titleMedium)),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        itemCount: _rows.length + (_rows.length < _total ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == _rows.length) {
                            if (!_more) WidgetsBinding.instance.addPostFrameCallback((_) => _load(append: true));
                            return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                          }
                          final r = _rows[i];
                          final k = _kindStyle('${r['kind']}');
                          final busy = _busy.contains('${r['id']}');
                          final who = r['deleted_by_name'] ?? r['deleted_by_username'];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: k.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                                  child: Icon(k.icon, size: 18, color: k.color),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(wsTitle(r), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                                      Text(
                                        [
                                          tr(k.label),
                                          if (r['board_name'] != null) '${r['board_name']}',
                                          if (who != null) tr('ลบโดย $who'),
                                          wsDateTime(r['deleted_at'] ?? r['created_at']),
                                        ].where((e) => e.isNotEmpty).join(' · '),
                                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                if (busy)
                                  const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                                else ...[
                                  IconButton(
                                    key: ValueKey('ws-restore-${r['id']}'),
                                    tooltip: tr('กู้คืน'),
                                    icon: Icon(NxI.arrowCounterClockwise, color: cs.primary),
                                    onPressed: () => _restore(r),
                                  ),
                                  if (_canPurge)
                                    IconButton(tooltip: tr('ลบถาวร'), icon: Icon(NxI.trash, color: cs.error), onPressed: () => _purge(r)),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

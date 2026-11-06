import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_icons.dart';

/// (done, total) over checkable rows — headers don't count, like the web.
(int, int) checklistProgress(List<Map<String, dynamic>> items) {
  final rows = items.where((i) => i['item_kind']?.toString() != 'header').toList();
  return (rows.where((i) => i['status']?.toString() == 'done').length, rows.length);
}

/// Smart checklist of a workspace task
/// (`/api/boards/:b/items/task/:id/smart-checklist`).
class SmartChecklistSection extends StatefulWidget {
  const SmartChecklistSection({super.key, required this.boardId, required this.taskId});

  final String boardId;
  final String taskId;

  @override
  State<SmartChecklistSection> createState() => _SmartChecklistSectionState();
}

class _SmartChecklistSectionState extends State<SmartChecklistSection> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _busy = false;
  final _add = TextEditingController();

  ApiClient get _api => context.read<AppConfig>().apiClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await _api.getSmartChecklist(widget.boardId, widget.taskId);
      if (mounted) setState(() => _items = items);
    } catch (_) {
      // Feature off / no access: the section simply stays empty.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> item, bool done) => _run(() async {
        final id = item['id']?.toString() ?? '';
        setState(() => item['status'] = done ? 'done' : 'todo');
        try {
          await _api.updateSmartChecklistItem(widget.boardId, id, {'status': done ? 'done' : 'todo'});
        } catch (_) {
          if (mounted) setState(() => item['status'] = done ? 'todo' : 'done');
          rethrow;
        }
      });

  Future<void> _addItem() async {
    final title = _add.text.trim();
    if (title.isEmpty) return;
    await _run(() async {
      final item = await _api.addSmartChecklistItem(widget.boardId, widget.taskId, title);
      _add.clear();
      if (mounted) setState(() => _items = [..._items, item]);
    });
  }

  Future<void> _delete(Map<String, dynamic> item) => _run(() async {
        await _api.deleteSmartChecklistItem(widget.boardId, item['id']?.toString() ?? '');
        if (mounted) setState(() => _items = _items.where((e) => e != item).toList());
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (done, total) = checklistProgress(_items);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text('เช็คลิสต์${total > 0 ? ' ($done/$total)' : ''}', style: theme.textTheme.titleSmall)),
          if (_busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        if (total > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: done / total, minHeight: 6),
            ),
          ),
        if (_loading) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
        for (final item in _items)
          if (item['item_kind']?.toString() == 'header')
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Text(item['title']?.toString() ?? '', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            )
          else
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: item['status']?.toString() == 'done',
              onChanged: _busy ? null : (v) => _toggle(item, v ?? false),
              title: Text(
                item['title']?.toString() ?? '',
                style: item['status']?.toString() == 'done' || item['status']?.toString() == 'skipped'
                    ? TextStyle(decoration: TextDecoration.lineThrough, color: cs.onSurfaceVariant)
                    : null,
              ),
              secondary: IconButton(
                tooltip: 'ลบ',
                icon: const Icon(NxI.x, size: 16),
                onPressed: _busy ? null : () => _delete(item),
              ),
            ),
        TextField(
          controller: _add,
          enabled: !_busy,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _addItem(),
          decoration: InputDecoration(
            hintText: 'เพิ่มรายการเช็คลิสต์',
            isDense: true,
            prefixIcon: const Icon(NxI.plus, size: 18),
            suffixIcon: IconButton(icon: const Icon(NxI.paperPlaneTilt, size: 18), onPressed: _busy ? null : _addItem),
          ),
        ),
      ],
    );
  }
}

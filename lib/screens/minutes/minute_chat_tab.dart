import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_icons.dart';

/// "แชท" on a room meeting: the room chat saved with the meeting. The host / co-host can remove a message.
class MinuteChatTab extends StatefulWidget {
  const MinuteChatTab({super.key, required this.meetingId, required this.api, this.canDelete = false});
  final String meetingId;
  final ApiClient api;
  final bool canDelete;

  @override
  State<MinuteChatTab> createState() => _MinuteChatTabState();
}

class _MinuteChatTabState extends State<MinuteChatTab> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.api.getMinuteChat(widget.meetingId);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) {
        setState(() {
          _items = const [];
          _error = e is ApiEnvelopeException ? e.message : tr('โหลดแชทไม่สำเร็จ');
        });
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ลบข้อความนี้?')),
        content: Text('${c['text'] ?? ''}', maxLines: 4, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(key: const ValueKey('minute-chat-delete-ok'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ลบ'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.api.deleteMinuteChat(widget.meetingId, '${c['id']}');
      if (mounted) setState(() => _items = [...?_items?.where((x) => x['id'] != c['id'])]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiEnvelopeException ? e.message : tr('ลบข้อความไม่สำเร็จ'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return Center(
        key: const ValueKey('minute-chat-empty'),
        child: Padding(padding: const EdgeInsets.all(24), child: Text(_error ?? tr('ไม่มีแชทในห้องประชุมนี้'), style: theme.textTheme.bodyMedium)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        key: const ValueKey('minute-chat-list'),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final c = items[i];
          final at = parseThai(c['at']);
          final time = at == null ? '' : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
          return Row(
            key: ValueKey('minute-chat-${c['id']}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text([if ('${c['name'] ?? ''}'.isNotEmpty) '${c['name']}' else tr('ผู้เข้าร่วม'), if (time.isNotEmpty) time].join(' · '),
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text('${c['text'] ?? ''}', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              if (widget.canDelete)
                IconButton(key: ValueKey('minute-chat-delete-${c['id']}'), tooltip: tr('ลบข้อความ'), icon: const Icon(NxI.trash, size: 18), onPressed: () => _delete(c)),
            ],
          );
        },
      ),
    );
  }
}

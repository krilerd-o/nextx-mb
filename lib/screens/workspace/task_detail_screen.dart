import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_overlay_panel.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_icons.dart';

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.task});
  final Map<String, dynamic> task;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  List<Map<String, dynamic>> _logs = [];
  final _hoursController = TextEditingController(text: '30');
  final _noteController = TextEditingController();
  bool _loading = true;

  String get _boardId => strId(widget.task['board_id']);
  String get _taskId => strId(widget.task['id']);

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    if (!context.read<AppConfig>().isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    try {
      final logs = await context.read<AppConfig>().apiClient.getTaskWorklogs(_boardId, _taskId);
      if (mounted) {
        setState(() {
          _logs = logs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _addLog() async {
    final minutes = int.tryParse(_hoursController.text.trim()) ?? 0;
    if (minutes <= 0) return;
    try {
      await context.read<AppConfig>().apiClient.postTaskWorklog(
            _boardId,
            _taskId,
            minutes: minutes,
            description: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          );
      _noteController.clear();
      await _loadLogs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = entityTitle(widget.task, module: 'task');
    final desc = widget.task['description']?.toString();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: NxAppHeader(
          title: title,
          actions: [
            IconButton(
              icon: const Icon(NxI.dotsThree),
              onPressed: () {
                showNxBlurPanel<void>(
                  context: context,
                  builder: (ctx) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(NxI.timer),
                          title: const Text('ลง worklog'),
                          onTap: () {
                            Navigator.pop(ctx);
                            DefaultTabController.of(context).animateTo(1);
                          },
                        ),
                        ListTile(
                          leading: const Icon(NxI.x),
                          title: const Text('ปิด'),
                          onTap: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'รายละเอียด'),
                Tab(text: 'Worklog'),
              ],
            ),
            Expanded(
              child: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (desc != null && desc.isNotEmpty)
                  NxHtmlView(html: desc, style: theme.textTheme.bodyLarge)
                else
                  Text(
                    'ไม่มีคำอธิบาย',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(label: Text('สถานะ: ${widget.task['status'] ?? '—'}')),
                    if (widget.task['id'] != null) Chip(label: Text('id: ${widget.task['id']}')),
                  ],
                ),
              ],
            ),
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_loading && _logs.isEmpty) const NxSkeletonList(rows: 3),
                for (final log in _logs)
                  ListTile(
                    title: Text('${log['time_spent_minutes'] ?? 0} นาที'),
                    subtitle: NxHtmlView(
                      html: log['work_description']?.toString() ?? log['created_at']?.toString() ?? '',
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _hoursController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'นาทีที่ลง',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'รายละเอียดงาน',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(onPressed: _addLog, child: const Text('บันทึก worklog')),
              ],
            ),
          ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

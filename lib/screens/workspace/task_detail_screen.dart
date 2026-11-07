import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/html_display.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_overlay_panel.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_icons.dart';
import '../mail/mail_compose_screen.dart' show plainTextToHtml;
import 'smart_checklist_section.dart';

/// NEXTX board priorities (backend/src/routes/boards.js).
const taskPriorities = <String, String>{
  'highest': 'สูงสุด',
  'high': 'สูง',
  'medium': 'ปานกลาง',
  'low': 'ต่ำ',
  'lowest': 'ต่ำสุด',
};

/// Task attachments arrive as a JSON array or a JSON string of one.
List<Map<String, dynamic>> taskAttachments(dynamic raw) {
  var v = raw;
  if (v is String && v.trim().isNotEmpty) {
    try {
      v = jsonDecode(v);
    } catch (_) {
      return const [];
    }
  }
  if (v is! List) return const [];
  return [
    for (final a in v)
      if (a is Map && a['url'] != null) Map<String, dynamic>.from(a) else if (a is String) {'url': a, 'name': 'file'},
  ];
}

/// `2026-11-06T00:00:00.000Z` / `2026-11-06` → `2026-11-06`.
String? taskDateOnly(dynamic raw) {
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(s);
  return m?.group(1);
}

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.task});
  final Map<String, dynamic> task;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late Map<String, dynamic> _task = Map<String, dynamic>.from(widget.task);
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _comments = [];
  List<Map<String, dynamic>>? _users;
  final _minutesController = TextEditingController(text: '30');
  final _noteController = TextEditingController();
  final _commentController = TextEditingController();
  bool _loading = true;
  bool _loadingComments = true;
  bool _saving = false;

  String get _boardId => strId(_task['board_id']);
  String get _taskId => strId(_task['id']);

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _loadComments();
  }

  @override
  void dispose() {
    _minutesController.dispose();
    _noteController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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

  Future<void> _loadComments() async {
    if (!context.read<AppConfig>().isLoggedIn) {
      setState(() => _loadingComments = false);
      return;
    }
    try {
      final list = await context.read<AppConfig>().apiClient.getTaskComments(_boardId, _taskId);
      if (mounted) {
        setState(() {
          _comments = list;
          _loadingComments = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  Future<void> _addLog() async {
    final minutes = int.tryParse(_minutesController.text.trim()) ?? 0;
    if (minutes <= 0) {
      _snack('กรุณาระบุจำนวนนาทีมากกว่า 0');
      return;
    }
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
      _snack(formatApiError(e));
    }
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    try {
      await context.read<AppConfig>().apiClient.postTaskComment(_boardId, _taskId, plainTextToHtml(text));
      _commentController.clear();
      await _loadComments();
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  /// PUT only the changed fields and merge the server's row back in.
  /// [local] is merged for display only (e.g. the picked assignee's name).
  Future<void> _update(Map<String, dynamic> body, {Map<String, dynamic> local = const {}}) async {
    if (body.isEmpty) return;
    setState(() => _saving = true);
    try {
      final updated = await context.read<AppConfig>().apiClient.putBoardTask(_boardId, _taskId, body);
      if (!mounted) return;
      setState(() {
        _task = {..._task, ...body, ...local, ...updated};
        _saving = false;
      });
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _snack(formatApiError(e));
    }
  }

  Future<void> _edit() async {
    final desc = _task['description']?.toString() ?? '';
    final richDesc = looksLikeHtmlString(desc);
    final title = TextEditingController(text: _task['title']?.toString() ?? '');
    final description = TextEditingController(text: richDesc ? '' : desc);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('แก้ไขงาน'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'ชื่องาน'),
              ),
              const SizedBox(height: 12),
              if (richDesc)
                Text(
                  'คำอธิบายมีรูปแบบ (rich text) — แก้ไขบนเว็บเพื่อไม่ให้รูปแบบหาย',
                  style: Theme.of(ctx).textTheme.bodySmall,
                )
              else
                TextField(
                  controller: description,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(labelText: 'คำอธิบาย', border: OutlineInputBorder()),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('บันทึก')),
        ],
      ),
    );
    final newTitle = title.text.trim();
    final newDesc = description.text.trim();
    title.dispose();
    description.dispose();
    if (result != true) return;
    if (newTitle.isEmpty) {
      _snack('ชื่องานต้องไม่ว่าง');
      return;
    }
    await _update({
      if (newTitle != (_task['title']?.toString() ?? '')) 'title': newTitle,
      if (!richDesc && newDesc != desc) 'description': newDesc,
    });
  }

  Future<void> _pickAssignee() async {
    final api = context.read<AppConfig>().apiClient;
    try {
      _users ??= await api.getUsers(limit: 200);
    } catch (e) {
      _snack(formatApiError(e));
      return;
    }
    if (!mounted) return;
    final users = _users!;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _UserPickerSheet(users: users),
    );
    if (picked == null) return;
    final id = picked['id'];
    await _update(
      {'assignee_id': id == null ? null : int.tryParse(id.toString()) ?? id},
      local: {'assignee_name': id == null ? null : userDisplayName(picked)},
    );
  }

  Future<void> _pickDueDate() async {
    final current = DateTime.tryParse(taskDateOnly(_task['due_date']) ?? '');
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    final ymd = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    await _update({'due_date': ymd});
  }

  Future<void> _pickPriority() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in taskPriorities.entries)
              ListTile(
                leading: Icon(
                  e.key == _task['priority'] ? NxI.radioOn : NxI.radioOff,
                ),
                title: Text(e.value),
                onTap: () => Navigator.pop(ctx, e.key),
              ),
          ],
        ),
      ),
    );
    if (picked != null && picked != _task['priority']) await _update({'priority': picked});
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบงานนี้?'),
        content: const Text('งานจะถูกย้ายไปถังขยะของ Workspace'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ลบ')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppConfig>().apiClient.deleteBoardTask(_boardId, _taskId);
      if (!mounted) return;
      _snack('ลบงานแล้ว');
      Navigator.of(context).pop(true);
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  List<Map<String, dynamic>> get _attachments => taskAttachments(_task['attachments']);

  Future<void> _addAttachment() async {
    final picked = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
    final files = [
      for (final f in picked?.files ?? const <PlatformFile>[])
        if (f.bytes != null) MultipartFile.fromBytes(f.bytes!, filename: f.name),
    ];
    if (files.isEmpty || !mounted) return;
    setState(() => _saving = true);
    try {
      final uploaded = await context.read<AppConfig>().apiClient.uploadBoardAttachments(_boardId, files);
      if (!mounted) return;
      setState(() => _saving = false);
      await _update({'attachments': [..._attachments, ...uploaded]});
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _snack(formatApiError(e));
    }
  }

  Future<void> _removeAttachment(Map<String, dynamic> a) async {
    await _update({'attachments': _attachments.where((x) => x['url'] != a['url']).toList()});
  }

  String _assigneeLabel() {
    final name = _task['assignee_name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    final id = _task['assignee_id'];
    if (id == null || id.toString().isEmpty) return 'ยังไม่มอบหมาย';
    final match = _users?.where((u) => u['id']?.toString() == id.toString());
    if (match != null && match.isNotEmpty) return userDisplayName(match.first);
    return 'User #$id';
  }

  bool get _completed {
    final v = _task['is_completed'];
    return v == true || v == 1 || v?.toString() == '1' || v?.toString() == 'true';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = entityTitle(_task, module: 'task');
    final desc = _task['description']?.toString();
    final due = taskDateOnly(_task['due_date']);
    final priority = taskPriorities[_task['priority']?.toString()] ?? '—';

    return DefaultTabController(
        length: 3,
        child: NxScrollScaffold(
          header: NxAppHeader(
            title: title,
            actions: [
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              IconButton(
                tooltip: 'แก้ไข',
                icon: const Icon(NxI.pencilSimple),
                onPressed: _saving ? null : _edit,
              ),
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
                              DefaultTabController.of(context).animateTo(2);
                            },
                          ),
                          ListTile(
                            leading: Icon(NxI.trash, color: theme.colorScheme.error),
                            title: Text('ลบงาน', style: TextStyle(color: theme.colorScheme.error)),
                            onTap: () {
                              Navigator.pop(ctx);
                              _delete();
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
                  Tab(text: 'ความคิดเห็น'),
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
                        Card(
                          margin: EdgeInsets.zero,
                          child: Column(
                            children: [
                              ListTile(
                                leading: const Icon(NxI.user),
                                title: const Text('ผู้รับผิดชอบ'),
                                subtitle: Text(_assigneeLabel()),
                                trailing: const Icon(NxI.caretRight),
                                onTap: _saving ? null : _pickAssignee,
                              ),
                              ListTile(
                                leading: const Icon(NxI.calendarBlank),
                                title: const Text('กำหนดส่ง'),
                                subtitle: Text(due ?? 'ไม่กำหนด'),
                                trailing: const Icon(NxI.caretRight),
                                onTap: _saving ? null : _pickDueDate,
                              ),
                              ListTile(
                                leading: const Icon(NxI.flag),
                                title: const Text('ความสำคัญ'),
                                subtitle: Text(priority),
                                trailing: const Icon(NxI.caretRight),
                                onTap: _saving ? null : _pickPriority,
                              ),
                              SwitchListTile(
                                secondary: const Icon(NxI.checkCircle),
                                title: const Text('เสร็จแล้ว'),
                                value: _completed,
                                onChanged: _saving ? null : (v) => _update({'is_completed': v}),
                              ),
                            ],
                          ),
                        ),
                        if (_boardId.isNotEmpty && _taskId.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          SmartChecklistSection(boardId: _boardId, taskId: _taskId),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: Text('ไฟล์แนบ (${_attachments.length})', style: theme.textTheme.titleSmall)),
                            TextButton.icon(
                              onPressed: _saving ? null : _addAttachment,
                              icon: const Icon(NxI.paperclip, size: 18),
                              label: const Text('แนบไฟล์'),
                            ),
                          ],
                        ),
                        for (final a in _attachments)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon((a['mime']?.toString() ?? '').startsWith('image/') ? NxI.image : NxI.file),
                            title: Text(a['name']?.toString() ?? 'ไฟล์', maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () {
                              final uri = Uri.tryParse(context.read<AppConfig>().apiClient.absoluteUrl(a['url'].toString()));
                              if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                            },
                            trailing: IconButton(
                              tooltip: 'นำออก',
                              icon: const Icon(NxI.x, size: 18),
                              onPressed: _saving ? null : () => _removeAttachment(a),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            Chip(label: Text('สถานะ: ${_task['status'] ?? _task['status_name'] ?? '—'}')),
                            if (_task['id'] != null) Chip(label: Text('id: ${_task['id']}')),
                          ],
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _loadComments,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(16),
                              children: [
                                if (_loadingComments && _comments.isEmpty) const NxSkeletonList(rows: 3),
                                if (!_loadingComments && _comments.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 24),
                                    child: Center(
                                      child: Text('ยังไม่มีความคิดเห็น', style: theme.textTheme.bodyMedium),
                                    ),
                                  ),
                                for (final c in _comments)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(NxI.chatCircle),
                                    title: Text(c['user_name']?.toString() ?? 'ผู้ใช้'),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        NxHtmlView(html: c['body']?.toString() ?? ''),
                                        if (c['created_at'] != null)
                                          Text('${c['created_at']}', style: theme.textTheme.bodySmall),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _commentController,
                                    minLines: 1,
                                    maxLines: 4,
                                    decoration: const InputDecoration(
                                      hintText: 'เขียนความคิดเห็น…',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'ส่ง',
                                  onPressed: _addComment,
                                  icon: const Icon(NxI.paperPlaneTilt),
                                ),
                              ],
                            ),
                          ),
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
                          controller: _minutesController,
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

class _UserPickerSheet extends StatefulWidget {
  const _UserPickerSheet({required this.users});
  final List<Map<String, dynamic>> users;

  @override
  State<_UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends State<_UserPickerSheet> {
  var _needle = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.users.where((u) {
      if (_needle.isEmpty) return true;
      return userDisplayName(u).toLowerCase().contains(_needle) ||
          (userEmail(u) ?? '').toLowerCase().contains(_needle);
    }).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'ค้นหาผู้ใช้',
                  prefixIcon: Icon(NxI.magnifyingGlass),
                ),
                onChanged: (v) => setState(() => _needle = v.trim().toLowerCase()),
              ),
            ),
            ListTile(
              leading: const Icon(NxI.x),
              title: const Text('ไม่มอบหมาย'),
              onTap: () => Navigator.pop(context, <String, dynamic>{'id': null}),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final u = filtered[i];
                  return ListTile(
                    leading: const Icon(NxI.user),
                    title: Text(userDisplayName(u)),
                    subtitle: userEmail(u) == null ? null : Text(userEmail(u)!),
                    onTap: () => Navigator.pop(context, u),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

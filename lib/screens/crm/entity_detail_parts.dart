import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart' show MultipartFile;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_surface_card.dart';
import '../notifications/notification_center_screen.dart' show relativeTime;
import '../../core/i18n.dart';
import '../../widgets/nx_skeleton.dart';
import '../../core/thai_time.dart';
import '../../core/entity_display.dart';

/// Field that holds a record's status / stage for [module] (first one present).
String? entityStatusKey(Map<String, dynamic> row, String module) {
  for (final k in [
    '${module}_status',
    '${module}_stage',
    'status',
    'leadstatus',
    'deal_stage',
    'sales_stage',
    'case_status',
    'quotation_status',
    'job_status',
    'inspection_status',
    'account_status',
    'contact_status',
  ]) {
    if (row.containsKey(k)) return k;
  }
  return null;
}

/// Status pills the user can tap to move the record (like the web stepper).
class EntityStatusStepper extends StatelessWidget {
  const EntityStatusStepper({
    super.key,
    required this.options,
    required this.current,
    required this.onSelect,
  });

  /// `{value, label}` maps from the module picklist.
  final List<({String value, String label})> options;
  final String? current;
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idx = options.indexWhere((o) => o.value == current || o.label == current);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final o = options[i];
          final done = idx >= 0 && i < idx;
          final active = i == idx;
          final bg = active ? cs.primary : (done ? cs.primary.withValues(alpha: 0.14) : cs.surface);
          final fg = active ? cs.onPrimary : (done ? cs.primary : cs.onSurfaceVariant);
          return Material(
            color: bg,
            shape: StadiumBorder(side: BorderSide(color: active || done ? Colors.transparent : cs.outlineVariant)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onSelect == null || active
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onSelect!(o.value);
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (done) ...[Icon(NxI.check, size: 14, color: fg), const SizedBox(width: 4)],
                    Text(tr(o.label), style: TextStyle(color: fg, fontWeight: active ? FontWeight.w700 : FontWeight.w500, fontSize: 13)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Call / mail / map / copy-number shortcuts from whatever contact fields exist.
class EntityQuickActions extends StatelessWidget {
  const EntityQuickActions({super.key, required this.row, this.onDuplicate});
  final Map<String, dynamic> row;
  final VoidCallback? onDuplicate;

  static String? _first(Map<String, dynamic> row, List<String> keys) {
    for (final k in keys) {
      final v = row[k]?.toString().trim() ?? '';
      if (v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final phone = _first(row, const ['mobile_1st', 'mobile', 'phone', 'phone_1st', 'contact_mobile', 'account_mobile', 'tel']);
    final email = _first(row, const ['email_1st', 'email', 'contact_email', 'account_email']);
    final map = _first(row, const ['lead_locationmap', 'locationmap', 'location', 'address_line1']);
    final items = <(IconData, String, VoidCallback?)>[
      (NxI.phoneCall, 'โทร', phone == null ? null : () => launchUrl(Uri(scheme: 'tel', path: phone))),
      (NxI.envelope, 'อีเมล', email == null ? null : () => launchUrl(Uri(scheme: 'mailto', path: email))),
      (
        NxI.mapPin,
        'แผนที่',
        map == null
            ? null
            : () => launchUrl(
                  map.startsWith('http') ? Uri.parse(map) : Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': map}),
                  mode: LaunchMode.externalApplication,
                )
      ),
      (NxI.copySimple, 'ทำซ้ำ', onDuplicate),
    ];
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final (icon, label, onTap) in items)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Opacity(
                opacity: onTap == null ? 0.38 : 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.10), shape: BoxShape.circle),
                        child: Icon(icon, size: 20, color: cs.primary),
                      ),
                      const SizedBox(height: 4),
                      Text(tr(label), style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

bool isImageAttachment(Map<String, dynamic> a) {
  final mime = a['mime']?.toString() ?? '';
  if (mime.startsWith('image/')) return true;
  final n = (a['name'] ?? a['url'] ?? '').toString().toLowerCase();
  return RegExp(r'\.(png|jpe?g|gif|webp|heic)$').hasMatch(n);
}

List<Map<String, dynamic>> commentAttachments(Map<String, dynamic> c) {
  final raw = c['attachments'];
  if (raw is! List) return const [];
  return [for (final a in raw) if (a is Map) Map<String, dynamic>.from(a)];
}

/// Groups flat comments into threads: top-level (newest first) with replies (oldest first).
List<(Map<String, dynamic>, List<Map<String, dynamic>>)> threadComments(List<Map<String, dynamic>> rows) {
  final roots = <Map<String, dynamic>>[];
  final replies = <String, List<Map<String, dynamic>>>{};
  final ids = {for (final r in rows) r['id']?.toString()};
  for (final r in rows) {
    final p = r['parent_id']?.toString();
    if (p != null && p.isNotEmpty && ids.contains(p)) {
      (replies[p] ??= []).add(r);
    } else {
      roots.add(r);
    }
  }
  int cmp(Map<String, dynamic> a, Map<String, dynamic> b) =>
      (DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(0))
          .compareTo(DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(0));
  roots.sort((a, b) => cmp(b, a));
  return [
    for (final r in roots) (r, (replies[r['id']?.toString()] ?? [])..sort(cmp)),
  ];
}

/// Picks files from camera / gallery / storage and returns them as uploads.
Future<List<MultipartFile>> pickAttachments(BuildContext context) async {
  final source = await showAppBottomSheet<String>(
    context: context,
    title: 'แนบไฟล์',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(leading: const Icon(NxI.camera), title: Text(tr('ถ่ายรูป')), onTap: () => Navigator.pop(context, 'camera')),
        ListTile(leading: const Icon(NxI.images), title: Text(tr('เลือกรูปจากเครื่อง')), onTap: () => Navigator.pop(context, 'gallery')),
        ListTile(leading: const Icon(NxI.file), title: Text(tr('เลือกไฟล์')), onTap: () => Navigator.pop(context, 'file')),
      ],
    ),
  );
  if (source == null) return const [];
  final out = <MultipartFile>[];
  if (source == 'file') {
    final picked = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
    for (final f in picked?.files ?? const <PlatformFile>[]) {
      if (f.bytes != null) out.add(MultipartFile.fromBytes(f.bytes!, filename: f.name));
    }
    return out;
  }
  final picker = ImagePicker();
  // Resize before upload: phone photos are 4–12MB, 1920px is plenty for CRM.
  if (source == 'camera') {
    final x = await picker.pickImage(source: ImageSource.camera, maxWidth: 1920, imageQuality: 82);
    if (x != null) out.add(MultipartFile.fromBytes(await x.readAsBytes(), filename: x.name));
  } else {
    for (final x in await picker.pickMultiImage(maxWidth: 1920, imageQuality: 82)) {
      out.add(MultipartFile.fromBytes(await x.readAsBytes(), filename: x.name));
    }
  }
  return out;
}

/// Threaded comments with reply + attachments (camera / gallery / file).
class EntityCommentsPanel extends StatefulWidget {
  const EntityCommentsPanel({
    super.key,
    required this.module,
    required this.id,
    required this.comments,
    required this.onChanged,
  });

  final String module;
  final String id;
  final List<Map<String, dynamic>> comments;
  final Future<void> Function() onChanged;

  @override
  State<EntityCommentsPanel> createState() => _EntityCommentsPanelState();
}

class _EntityCommentsPanelState extends State<EntityCommentsPanel> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final List<Map<String, dynamic>> _pending = [];
  Map<String, dynamic>? _replyTo;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    final files = await pickAttachments(context);
    if (files.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final atts = await context.read<AppConfig>().apiClient.uploadCommentAttachments(files);
      if (mounted) setState(() => _pending.addAll(atts));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty && _pending.isEmpty) return;
    setState(() => _busy = true);
    try {
      await context.read<AppConfig>().apiClient.postEntityComment(
            widget.module,
            widget.id,
            body,
            attachments: List.of(_pending),
            parentId: _replyTo?['id'],
          );
      _text.clear();
      _pending.clear();
      _replyTo = null;
      HapticFeedback.lightImpact();
      await widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final threads = threadComments(widget.comments);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NxSurfaceCard(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_replyTo != null)
                Row(
                  children: [
                    Icon(NxI.arrowRight, size: 14, color: cs.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tr('ตอบกลับ ${_replyTo!['user_name'] ?? ''}'),
                        style: theme.textTheme.labelMedium?.copyWith(color: cs.primary),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(NxI.x, size: 16),
                      onPressed: () => setState(() => _replyTo = null),
                    ),
                  ],
                ),
              if (_pending.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final a in _pending)
                      InputChip(
        deleteIcon: const Icon(NxI.x, size: 16),
                        avatar: Icon(isImageAttachment(a) ? NxI.image : NxI.paperclip, size: 16),
                        label: Text(tr(a['name']?.toString() ?? 'file'), overflow: TextOverflow.ellipsis),
                        onDeleted: () => setState(() => _pending.remove(a)),
                      ),
                  ],
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(tooltip: tr('แนบไฟล์ / ถ่ายรูป'), icon: const Icon(NxI.paperclip), onPressed: _busy ? null : _attach),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(hintText: tr('เขียนความคิดเห็น'), border: InputBorder.none, filled: false),
                    ),
                  ),
                  _busy
                      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton.filled(tooltip: tr('ส่ง'), icon: const Icon(NxI.paperPlaneTilt, size: 18), onPressed: _send),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (threads.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(tr('ยังไม่มีความคิดเห็น'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
        for (final (root, replies) in threads)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NxSurfaceCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CommentTile(c: root),
                  for (final r in replies)
                    Container(
                      margin: const EdgeInsets.only(left: 18, top: 8),
                      padding: const EdgeInsets.only(left: 12),
                      decoration: BoxDecoration(border: Border(left: BorderSide(color: cs.outlineVariant, width: 2))),
                      child: _CommentTile(c: r, small: true),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        setState(() => _replyTo = root);
                        _focus.requestFocus();
                      },
                      child: Text(tr(replies.isEmpty ? 'ตอบกลับ' : 'ตอบกลับ (${replies.length})')),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.c, this.small = false});
  final Map<String, dynamic> c;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = c['user_name']?.toString().trim();
    final atts = commentAttachments(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            NxAvatar(label: name?.isNotEmpty == true ? name! : '?', size: small ? 24 : 30),
            const SizedBox(width: 8),
            Expanded(child: Text(tr(name?.isNotEmpty == true ? name! : 'ผู้ใช้'), style: theme.textTheme.titleSmall)),
            Text(tr(relativeTime(c['created_at'])), style: theme.textTheme.bodySmall),
          ],
        ),
        if ((c['body']?.toString() ?? '').trim().isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: NxHtmlView(html: c['body'].toString())),
        if (atts.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: AttachmentStrip(items: atts)),
      ],
    );
  }
}

/// Image thumbnails (tap = full screen) + file chips (tap = open).
class AttachmentStrip extends StatelessWidget {
  const AttachmentStrip({super.key, required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppConfig>().apiClient;
    final images = items.where(isImageAttachment).toList();
    final files = items.where((a) => !isImageAttachment(a)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (images.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < images.length; i++)
                GestureDetector(
                  onTap: () => openImageViewer(context, [for (final a in images) api.absoluteUrl(a['url'].toString())], i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image(
                      image: ResizeImage(CachedNetworkImageProvider(api.absoluteUrl(images[i]['url'].toString())), width: 252),
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(width: 84, height: 84, color: Colors.black12, child: const Icon(NxI.image)),
                    ),
                  ),
                ),
            ],
          ),
        for (final f in files)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(NxI.paperclip),
            title: Text(tr(f['name']?.toString() ?? 'file'), maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => launchUrl(Uri.parse(api.absoluteUrl(f['url'].toString())), mode: LaunchMode.externalApplication),
          ),
      ],
    );
  }
}

Future<void> openImageViewer(BuildContext context, List<String> urls, int initial) {
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (context, _, __) => _ImageViewer(urls: urls, initial: initial),
    transitionsBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
  ));
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.urls, required this.initial});
  final List<String> urls;
  final int initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0),
      body: PageView.builder(
        controller: PageController(initialPage: initial),
        itemCount: urls.length,
        itemBuilder: (context, i) => InteractiveViewer(
          maxScale: 5,
          child: Center(child: Image(image: CachedNetworkImageProvider(urls[i]), fit: BoxFit.contain)),
        ),
      ),
    );
  }
}

/// Every attachment from the record's comments, images first (like the web Files tab).
class EntityFilesPanel extends StatelessWidget {
  const EntityFilesPanel({super.key, required this.comments, required this.onAdd});
  final List<Map<String, dynamic>> comments;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final all = [for (final c in comments) ...commentAttachments(c)];
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(NxI.camera),
          label: Text(tr('ถ่ายรูป / แนบไฟล์')),
        ),
        const SizedBox(height: 12),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(tr('ยังไม่มีไฟล์แนบ'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          )
        else
          NxSurfaceCard(padding: const EdgeInsets.all(12), child: AttachmentStrip(items: all)),
      ],
    );
  }
}

/// Plain-language line for one timeline event.
({IconData icon, String title, String? detail}) describeTimelineEvent(
  Map<String, dynamic> e, {
  String Function(String field, String value)? valueLabel,
}) {
  final field = e['field_name']?.toString() ?? '';
  String plain(dynamic v) {
    final s = v?.toString() ?? '';
    if (s.isEmpty || s == 'null') return '—';
    final clean = stripTags(s);
    return valueLabel == null || field.isEmpty ? clean : valueLabel(field, clean);
  }

  switch (e['type']?.toString()) {
    case 'field_change':
      final label = e['field_label_th']?.toString() ?? e['field_name']?.toString() ?? 'ฟิลด์';
      return (icon: NxI.pencilSimple, title: 'แก้ $label', detail: '${plain(e['old_value'])} → ${plain(e['new_value'])}');
    case 'audit':
      final action = e['action']?.toString() ?? '';
      final t = switch (action.toLowerCase()) {
        final a when a.contains('create') => 'สร้างรายการ',
        final a when a.contains('delete') => 'ลบรายการ',
        final a when a.contains('update') || a.contains('edit') => 'แก้ไขรายการ',
        final a when a.contains('duplicate') => 'ทำซ้ำรายการ',
        final a when a.contains('convert') => 'แปลงรายการ',
        _ => action.isEmpty ? 'กิจกรรม' : action,
      };
      final d = e['details'];
      return (icon: NxI.clockCounterClockwise, title: t, detail: d is String && d.isNotEmpty && d.length < 160 ? d : null);
    case 'engagement':
      final kind = (e['event_type'] ?? e['source'])?.toString() ?? '';
      const names = {
        'comment': 'แสดงความคิดเห็น',
        'email_open': 'เปิดอีเมล',
        'email_click': 'คลิกลิงก์ในอีเมล',
        'email_sent': 'ส่งอีเมล',
        'call': 'โทรหา',
        'meeting': 'นัดประชุม',
        'activity': 'กิจกรรม',
        'web_visit': 'เข้าชมเว็บไซต์',
        'form_submit': 'กรอกฟอร์ม',
      };
      return (icon: NxI.chatCircle, title: names[kind] ?? 'การมีส่วนร่วม', detail: null);
    case 'status':
    case 'status_change':
      return (icon: NxI.flag, title: 'เปลี่ยนสถานะ', detail: '${plain(e['from_status'] ?? e['old_value'])} → ${plain(e['to_status'] ?? e['new_value'])}');
    default:
      return (
        icon: NxI.info,
        title: e['title']?.toString() ?? e['label']?.toString() ?? e['type']?.toString() ?? 'กิจกรรม',
        detail: e['description']?.toString() ?? e['summary']?.toString(),
      );
  }
}

String stripTags(String s) => s.replaceAll(RegExp(r'<[^>]*>'), '').trim();

class EntityHistoryPanel extends StatelessWidget {
  const EntityHistoryPanel({super.key, required this.events, required this.loading, this.valueLabel});
  final List<Map<String, dynamic>> events;
  final bool loading;

  /// Maps stored picklist values to their Thai labels (`Contacted` → `ติดต่อแล้ว`).
  final String Function(String field, String value)? valueLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (loading) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(tr('ยังไม่มีประวัติ'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
      );
    }
    return NxSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        children: [
          for (var i = 0; i < events.length; i++)
            () {
              final d = describeTimelineEvent(events[i], valueLabel: valueLabel);
              final who = events[i]['user_name']?.toString();
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                          child: Icon(d.icon, size: 15, color: cs.primary),
                        ),
                        if (i < events.length - 1) Expanded(child: Container(width: 2, color: cs.outlineVariant)),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14, top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr(d.title), style: theme.textTheme.titleSmall),
                            if (d.detail != null) Text(tr(d.detail!), style: theme.textTheme.bodyMedium),
                            Text(
                              tr([if (who != null && who.isNotEmpty) who, relativeTime(events[i]['at'])].join(' · ')),
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }(),
        ],
      ),
    );
  }
}

/// Pill segmented control (Inbox reference).
class NxSegmented extends StatelessWidget {
  const NxSegmented({super.key, required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(999)),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (i == index) return;
                  HapticFeedback.selectionClick();
                  onChanged(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: i == index ? cs.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: i == index ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))] : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    tr(labels[i]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                      color: i == index ? cs.onSurface : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Deletes wait 5 s with an "undo" snackbar before the API call is sent.
/// Lists hide pending ids so the row disappears at once.
class PendingEntityDeletes extends ChangeNotifier {
  PendingEntityDeletes._();
  static final PendingEntityDeletes instance = PendingEntityDeletes._();

  static const window = Duration(seconds: 5);
  final Set<String> _keys = {};

  bool isPending(String module, String id) => _keys.contains('$module:$id');

  /// Schedules deletion of [ids]; [commit] runs after the undo window.
  void schedule({
    required ScaffoldMessengerState messenger,
    required String module,
    required List<String> ids,
    required String label,
    required Future<void> Function() commit,
  }) {
    final keys = [for (final id in ids) '$module:$id'];
    _keys.addAll(keys);
    notifyListeners();
    var undone = false;
    messenger.hideCurrentSnackBar();
    final ctrl = messenger.showSnackBar(SnackBar(
      duration: window,
      behavior: SnackBarBehavior.floating,
      content: Text(tr('ลบ $label แล้ว')),
      action: SnackBarAction(label: 'เลิกทำ', onPressed: () => undone = true),
    ));
    ctrl.closed.then((_) async {
      if (!undone) {
        try {
          await commit();
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(tr('ลบไม่สำเร็จ: ${formatApiError(e)}'))));
        }
      }
      _keys.removeAll(keys);
      notifyListeners();
    });
  }
}

/// "กิจกรรม" tab: appointments linked to this record (related_module /
/// related_id), newest first, plus a button to book one linked to it.
class EntityActivitiesPanel extends StatefulWidget {
  const EntityActivitiesPanel({
    super.key,
    required this.module,
    required this.id,
    required this.title,
    required this.onOpen,
    required this.onCreate,
  });

  final String module;
  final String id;
  final String title;
  final void Function(Map<String, dynamic> row) onOpen;
  final Future<bool?> Function() onCreate;

  @override
  State<EntityActivitiesPanel> createState() => _EntityActivitiesPanelState();
}

class _EntityActivitiesPanelState extends State<EntityActivitiesPanel> {
  List<Map<String, dynamic>>? _rows;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await context.read<AppConfig>().apiClient.getEntityList(
        'activity',
        limit: 50,
        extra: {
          'filter[related_module]': widget.module,
          'filter[related_id]': widget.id,
          'sort': 'date_start',
          'order': 'desc',
        },
      );
      if (mounted) setState(() => _rows = page.items);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rows = _rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          onPressed: () async {
            final ok = await widget.onCreate();
            if (ok == true) _load();
          },
          icon: const Icon(NxI.calendarCheck),
          label: Text(tr('สร้างนัดผูกกับรายการนี้')),
        ),
        const SizedBox(height: 12),
        if (_error != null)
          Text(tr(formatApiError(_error!)), style: TextStyle(color: cs.error))
        else if (rows == null)
          const NxSkeletonList(rows: 2)
        else if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(tr('ยังไม่มีกิจกรรมที่ผูกกับรายการนี้'), style: theme.textTheme.bodyMedium)),
          )
        else
          for (final r in rows)
            NxSurfaceCard(
              margin: const EdgeInsets.only(bottom: 10),
              onTap: () => widget.onOpen(r),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: Icon(
                      '${r['checkindate'] ?? ''}'.isNotEmpty ? NxI.checkCircle : NxI.calendarBlank,
                      color: cs.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${r['subject'] ?? entityTitle(r, module: 'activity')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          [
                            _activityWhen(r['date_start']),
                            if ('${r['status'] ?? ''}'.isNotEmpty) '${r['status']}',
                            if ('${r['activitytype'] ?? ''}'.isNotEmpty) '${r['activitytype']}',
                          ].where((e) => e.isNotEmpty).join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(NxI.caretRight, size: 18, color: cs.onSurfaceVariant),
                ],
              ),
            ),
      ],
    );
  }
}

String _activityWhen(dynamic raw) {
  final d = parseThai(raw);
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day}/${d.month}/${uiYear(d.year)} ${two(d.hour)}:${two(d.minute)}';
}

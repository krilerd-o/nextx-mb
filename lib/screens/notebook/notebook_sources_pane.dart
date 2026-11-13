import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
import '../../core/notebook/notebook_models.dart';
import '../../services/api_client.dart';
import '../../services/notebook/notebook_controller.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_markdown.dart';
import 'notebook_widgets.dart';

/// A picked file for upload.
typedef NotebookPickedFile = ({String name, List<int> bytes});

/// File / camera pickers (tests replace them).
class NotebookPickers {
  NotebookPickers._();

  static Future<List<NotebookPickedFile>> Function() files = () async {
    final r = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'txt', 'md', 'doc', 'docx', 'ppt', 'pptx', 'csv', 'xls', 'xlsx', 'json', 'png', 'jpg', 'jpeg', 'webp', 'mp3', 'm4a', 'wav'],
    );
    return [for (final f in r?.files ?? const <PlatformFile>[]) if (f.bytes != null) (name: f.name, bytes: f.bytes!)];
  };

  static Future<NotebookPickedFile?> Function() camera = () async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2400, imageQuality: 88);
    if (x == null) return null;
    return (name: x.name, bytes: await x.readAsBytes());
  };
}

/// "แหล่งข้อมูล" tab: what the chat and studio read from.
class NotebookSourcesPane extends StatelessWidget {
  const NotebookSourcesPane({super.key, required this.c});
  final NotebookController c;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: c, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sources = c.sources;
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;
    if (sources.isEmpty && c.uploads.isEmpty) {
      return NotebookState(
        key: const ValueKey('notebook-sources-empty'),
        mood: 'book_flood',
        title: 'เพิ่มแหล่งข้อมูลแรก',
        message: 'อัปโหลด PDF เอกสาร รูป ลิงก์เว็บ หรือวางข้อความ ไอแซคจะตอบจากแหล่งเหล่านี้เท่านั้น',
        action: c.canWrite
            ? FilledButton.icon(
                key: const ValueKey('notebook-add-source-empty'),
                onPressed: () => showAddSourceSheet(context, c),
                icon: const Icon(NxI.plus, size: 18),
                label: Text(tr('เพิ่มแหล่งข้อมูล')),
              )
            : null,
      );
    }
    final header = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      NotebookCard(
        padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
        child: Row(children: [
          Checkbox(
            key: const ValueKey('notebook-select-all'),
            value: c.allEnabled ? true : (c.enabledSources.isEmpty ? false : null),
            tristate: true,
            onChanged: c.canWrite && sources.isNotEmpty
                ? (_) {
                    HapticFeedback.selectionClick();
                    c.selectAll(!c.allEnabled);
                  }
                : null,
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('เลือกทั้งหมด'), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(tr('ใช้ในแชทและสตูดิโอ ${c.enabledSources.length}/${sources.length} แหล่ง'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          if (c.canWrite)
            FilledButton.icon(
              key: const ValueKey('notebook-add-source'),
              style: FilledButton.styleFrom(
                backgroundColor: kNotebookAccent,
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => showAddSourceSheet(context, c),
              icon: const Icon(NxI.plus, size: 18),
              label: Text(tr('เพิ่ม')),
            ),
        ]),
      ),
      for (final up in c.uploads) Padding(padding: const EdgeInsets.only(top: 10), child: _UploadRow(c: c, up: up)),
      if (sources.length > 1 && c.canWrite)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 2),
          child: Text(tr('กดค้างแล้วลากเพื่อเรียงลำดับ'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
      const SizedBox(height: 8),
    ]);
    return ReorderableListView.builder(
      key: const ValueKey('notebook-sources-list'),
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottom),
      buildDefaultDragHandles: false,
      header: header,
      itemCount: sources.length,
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      onReorderItem: (a, b) => c.reorder(a, b),
      proxyDecorator: (child, _, anim) => Material(color: Colors.transparent, elevation: 6, shadowColor: kNotebookAccent.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(20), child: child),
      itemBuilder: (context, i) {
        final s = sources[i];
        final row = Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SourceRow(c: c, s: s),
        );
        return c.canWrite
            ? ReorderableDelayedDragStartListener(key: ValueKey('notebook-source-${s.id}'), index: i, child: row)
            : KeyedSubtree(key: ValueKey('notebook-source-${s.id}'), child: row);
      },
    );
  }
}

class _UploadRow extends StatelessWidget {
  const _UploadRow({required this.c, required this.up});
  final NotebookController c;
  final NotebookUpload up;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NotebookCard(
      key: ValueKey('notebook-upload-${up.name}'),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      child: Row(children: [
        NotebookIconBadge(icon: up.kind == 'image' ? LucideIcons300.image : LucideIcons300.fileUp, color: up.failed ? cs.error : kNotebookAccent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(up.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (up.failed)
              Text(tr(up.error!), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.error))
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(key: const ValueKey('notebook-upload-progress'), value: up.progress >= 1 ? null : up.progress, minHeight: 5),
              ),
              const SizedBox(height: 4),
              Text(
                up.progress >= 1 ? tr('ไอแซคกำลังอ่านไฟล์…') : tr('กำลังอัปโหลด ${(up.progress * 100).round()}%'),
                style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ]),
        ),
        if (up.failed)
          IconButton(tooltip: tr('ปิด'), icon: const Icon(NxI.x, size: 18), onPressed: () => c.dismissUpload(up)),
      ]),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.c, required this.s});
  final NotebookController c;
  final NotebookSource s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final st = sourceKindStyle(s);
    final status = s.status;
    final (String statusText, Color statusColor) = switch (status) {
      NotebookSourceStatus.processing => ('กำลังประมวลผล', const Color(0xFFD97706)),
      NotebookSourceStatus.error => ('อ่านไม่สำเร็จ', cs.error),
      NotebookSourceStatus.empty => ('ไม่มีข้อความ', cs.onSurfaceVariant),
      NotebookSourceStatus.ready => ('พร้อม', const Color(0xFF16A34A)),
    };
    return NotebookCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      onTap: () => showSourceViewer(context, c, s),
      child: Opacity(
        opacity: s.enabled ? 1 : 0.6,
        child: Row(children: [
          NotebookIconBadge(icon: st.icon, color: st.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
              const SizedBox(height: 3),
              Row(children: [
                Flexible(child: Text(tr(notebookSourceKindLabel(s)), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant))),
                const SizedBox(width: 8),
                Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(tr(statusText), key: ValueKey('notebook-source-status-${s.id}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: statusColor, fontWeight: FontWeight.w700)),
                ),
              ]),
            ]),
          ),
          Checkbox(
            key: ValueKey('notebook-source-toggle-${s.id}'),
            value: s.enabled,
            onChanged: c.canWrite
                ? (v) {
                    HapticFeedback.selectionClick();
                    c.toggleSource(s, v ?? false);
                  }
                : null,
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- add sheet

Future<void> showAddSourceSheet(BuildContext context, NotebookController c) async {
  final pick = await showAppBottomSheet<String>(
    context: context,
    title: 'เพิ่มแหล่งข้อมูล',
    child: const _AddSourceGrid(),
  );
  if (pick == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  void snack(String t) => messenger?.showSnackBar(SnackBar(content: Text(tr(t))));
  try {
    switch (pick) {
      case 'file':
        final files = await NotebookPickers.files();
        for (final f in files) {
          await c.addFile(() => MultipartFile.fromBytes(f.bytes, filename: f.name), name: f.name);
        }
      case 'camera':
        final f = await NotebookPickers.camera();
        if (f == null) return;
        await c.addFile(() => MultipartFile.fromBytes(f.bytes, filename: f.name), name: f.name, kind: 'image');
      case 'url':
      case 'youtube':
        final yt = pick == 'youtube';
        if (!context.mounted) return;
        final url = await _askUrl(context, youtube: yt);
        if (url == null) return;
        await c.addUrl(url, youtube: yt);
        snack('เพิ่มลิงก์แล้ว');
      case 'text':
        if (!context.mounted) return;
        final t = await _askText(context);
        if (t == null) return;
        await c.addText(title: t.title, content: t.content);
        snack('เพิ่มข้อความแล้ว');
      case 'library':
        if (!context.mounted) return;
        final ids = await _pickKnowledge(context, c);
        if (ids == null || ids.isEmpty) return;
        await c.addKnowledge(ids);
        snack('เพิ่มแหล่งจากคลังแล้ว');
      case 'crm':
        if (!context.mounted) return;
        final m = await _pickCrm(context);
        if (m == null) return;
        await c.api.addNotebookSource(c.id, {
          'source_kind': 'crm_module',
          'title': m.label,
          'source_config': {'module': m.module, 'limit': m.limit},
        });
        await c.load(quiet: true);
        snack('เพิ่มข้อมูล CRM แล้ว');
    }
  } catch (e) {
    snack(notebookError(e).text);
  }
}

class _AddSourceGrid extends StatelessWidget {
  const _AddSourceGrid();

  @override
  Widget build(BuildContext context) {
    final options = <(String, IconData, String, String, Color, bool)>[
      ('file', LucideIcons300.fileUp, 'อัปโหลดไฟล์', 'PDF, Word, Excel, รูป, เสียง', const Color(0xFF2563EB), true),
      ('camera', LucideIcons300.scanLine, 'ถ่ายรูป / สแกน', 'เอกสารหรือไวต์บอร์ด', const Color(0xFF0EA5E9), !kIsWeb),
      ('url', LucideIcons300.globe, 'ลิงก์เว็บ', 'อ่านเนื้อหาจากหน้าเว็บ', const Color(0xFF0891B2), true),
      ('youtube', LucideIcons300.circlePlay, 'YouTube', 'ลิงก์วิดีโอ', const Color(0xFFEF4444), true),
      ('text', LucideIcons300.clipboardPaste, 'วางข้อความ', 'โน้ต อีเมล หรือบทความ', const Color(0xFF64748B), true),
      ('library', LucideIcons300.library, 'คลังความรู้', 'จากคลังของธุรกิจ', const Color(0xFFD97706), true),
      ('crm', LucideIcons300.database, 'ข้อมูล CRM', 'ลูกค้า ดีล เคส ที่คุณเห็น', const Color(0xFF7C3AED), true),
      ('record', LucideIcons300.mic, 'อัดเสียง', 'เร็วๆ นี้', const Color(0xFFDB2777), false),
    ];
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth > 520 ? 4 : 2;
      final w = (box.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (id, icon, label, hint, color, on) in options)
          SizedBox(
            width: w,
            child: Opacity(
              opacity: on ? 1 : 0.45,
              child: NotebookCard(
                key: ValueKey('notebook-add-$id'),
                padding: const EdgeInsets.all(12),
                onTap: on
                    ? () {
                        HapticFeedback.selectionClick();
                        Navigator.pop(context, id);
                      }
                    : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  NotebookIconBadge(icon: icon, color: color, size: 38),
                  const SizedBox(height: 10),
                  Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text(tr(hint), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ),
            ),
          ),
      ]);
    });
  }
}

Future<String?> _askUrl(BuildContext context, {required bool youtube}) {
  return showAppBottomSheet<String>(
    context: context,
    title: youtube ? 'เพิ่มวิดีโอ YouTube' : 'เพิ่มลิงก์เว็บ',
    child: _UrlForm(youtube: youtube),
  );
}

class _UrlForm extends StatefulWidget {
  const _UrlForm({required this.youtube});
  final bool youtube;

  @override
  State<_UrlForm> createState() => _UrlFormState();
}

class _UrlFormState extends State<_UrlForm> {
  final _ctl = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    final url = normalizeWebUrl(_ctl.text);
    if (url == null) {
      setState(() => _err = tr('ลิงก์ไม่ถูกต้อง'));
      return;
    }
    if (widget.youtube && !isYoutubeUrl(url)) {
      setState(() => _err = tr('ต้องเป็นลิงก์ youtube.com หรือ youtu.be'));
      return;
    }
    Navigator.pop(context, url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        key: const ValueKey('notebook-url-field'),
        controller: _ctl,
        autofocus: true,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: widget.youtube ? 'https://youtu.be/…' : 'https://…',
          errorText: _err,
          prefixIcon: Icon(widget.youtube ? LucideIcons300.circlePlay : LucideIcons300.globe),
          suffixIcon: IconButton(
            tooltip: tr('วาง'),
            icon: const Icon(LucideIcons300.clipboardPaste, size: 18),
            onPressed: () async {
              final d = await Clipboard.getData(Clipboard.kTextPlain);
              if (d?.text != null) _ctl.text = d!.text!.trim();
            },
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        tr(widget.youtube ? 'ตอนนี้ไอแซคอ่านรายละเอียดของวิดีโอ — คำบรรยายเต็มจะตามมาเร็วๆ นี้' : 'ไอแซคจะดึงชื่อและเนื้อหาหลักของหน้าเว็บมาเป็นแหล่งข้อมูล'),
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 16),
      FilledButton(key: const ValueKey('notebook-url-add'), onPressed: _submit, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: Text(tr('เพิ่มลิงก์'))),
    ]);
  }
}

Future<({String title, String content})?> _askText(BuildContext context) {
  return showAppBottomSheet<({String title, String content})>(context: context, title: 'วางข้อความ', child: const _TextForm());
}

class _TextForm extends StatefulWidget {
  const _TextForm();

  @override
  State<_TextForm> createState() => _TextFormState();
}

class _TextFormState extends State<_TextForm> {
  final _title = TextEditingController();
  final _body = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(key: const ValueKey('notebook-text-title'), controller: _title, decoration: InputDecoration(labelText: tr('ชื่อ (ไม่บังคับ)'))),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('notebook-text-body'),
        controller: _body,
        minLines: 6,
        maxLines: 12,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: tr('เนื้อหา'),
          alignLabelWithHint: true,
          suffixIcon: IconButton(
            tooltip: tr('วาง'),
            icon: const Icon(LucideIcons300.clipboardPaste, size: 18),
            onPressed: () async {
              final d = await Clipboard.getData(Clipboard.kTextPlain);
              if (d?.text != null) setState(() => _body.text = d!.text!);
            },
          ),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        key: const ValueKey('notebook-text-add'),
        onPressed: _body.text.trim().isEmpty ? null : () => Navigator.pop(context, (title: _title.text.trim(), content: _body.text.trim())),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: Text(tr('เพิ่มข้อความ')),
      ),
    ]);
  }
}

Future<List<String>?> _pickKnowledge(BuildContext context, NotebookController c) {
  return showNxSnapSheet<List<String>>(
    context: context,
    title: 'เลือกจากคลังความรู้',
    snaps: const [0.6, 0.9],
    builder: (ctx, scroll) => _KnowledgePicker(c: c, scroll: scroll),
  );
}

class _KnowledgePicker extends StatefulWidget {
  const _KnowledgePicker({required this.c, required this.scroll});
  final NotebookController c;
  final ScrollController scroll;

  @override
  State<_KnowledgePicker> createState() => _KnowledgePickerState();
}

class _KnowledgePickerState extends State<_KnowledgePicker> {
  List<Map<String, dynamic>>? _rows;
  String? _error;
  final Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    widget.c.api.getAiKnowledge().then((r) {
      if (mounted) setState(() => _rows = r);
    }, onError: (Object e) {
      if (mounted) setState(() => _error = notebookError(e).text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _rows;
    final have = {for (final s in widget.c.sources) if (s.knowledgeId != null) s.knowledgeId!};
    if (_error != null) return NotebookState(mood: 'error', title: 'เปิดคลังความรู้ไม่ได้', message: _error, size: 72);
    if (rows == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (rows.isEmpty) return const NotebookState(mood: 'shrug', title: 'คลังความรู้ยังว่าง', message: 'ผู้ดูแลเพิ่มองค์ความรู้ได้ที่ตั้งค่า AI บนเว็บ', size: 72);
    return Column(children: [
      Expanded(
        child: ListView(controller: widget.scroll, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (final r in rows)
            CheckboxListTile(
              key: ValueKey('notebook-knowledge-${r['id']}'),
              value: have.contains('${r['id']}') || _picked.contains('${r['id']}'),
              onChanged: have.contains('${r['id']}') ? null : (v) => setState(() => v == true ? _picked.add('${r['id']}') : _picked.remove('${r['id']}')),
              title: Text('${r['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                have.contains('${r['id']}') ? tr('อยู่ในสมุดแล้ว') : '${r['type'] ?? ''}',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ]),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(
            key: const ValueKey('notebook-knowledge-add'),
            onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, _picked.toList()),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(tr('เพิ่ม ${_picked.length} รายการ')),
          ),
        ),
      ),
    ]);
  }
}

/// CRM modules the server can read as a source (`allowedCrmModules`).
const kNotebookCrmModules = [
  ('lead', 'ผู้มุ่งหวัง'),
  ('contact', 'ผู้ติดต่อ'),
  ('account', 'บัญชีลูกค้า'),
  ('case', 'เคส'),
  ('activity', 'กิจกรรม'),
  ('product', 'สินค้า'),
  ('quotation', 'ใบเสนอราคา'),
  ('call_log', 'บันทึกการโทร'),
];

Future<({String module, String label, int limit})?> _pickCrm(BuildContext context) {
  return showAppBottomSheet<({String module, String label, int limit})>(context: context, title: 'ข้อมูล CRM', child: const _CrmForm());
}

class _CrmForm extends StatefulWidget {
  const _CrmForm();

  @override
  State<_CrmForm> createState() => _CrmFormState();
}

class _CrmFormState extends State<_CrmForm> {
  String _module = 'account';
  int _limit = 20;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('ไอแซคจะอ่านรายการล่าสุดที่คุณมีสิทธิ์เห็นในโมดูลนี้'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (id, label) in kNotebookCrmModules)
          ChoiceChip(key: ValueKey('notebook-crm-$id'), label: Text(tr(label)), selected: _module == id, showCheckmark: false, onSelected: (_) => setState(() => _module = id)),
      ]),
      const SizedBox(height: 16),
      Text(tr('จำนวนรายการ'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      Wrap(spacing: 8, children: [
        for (final n in const [10, 20, 50]) ChoiceChip(label: Text('$n'), selected: _limit == n, showCheckmark: false, onSelected: (_) => setState(() => _limit = n)),
      ]),
      const SizedBox(height: 18),
      FilledButton(
        key: const ValueKey('notebook-crm-add'),
        onPressed: () {
          final label = kNotebookCrmModules.firstWhere((m) => m.$1 == _module).$2;
          Navigator.pop(context, (module: _module, label: tr('ข้อมูล CRM: $label'), limit: _limit));
        },
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: Text(tr('เพิ่มข้อมูล CRM')),
      ),
    ]);
  }
}

// -------------------------------------------------------------- source viewer

/// Source guide sheet: what the source says, plus refresh / rename / delete /
/// on-off. [highlight] marks a cited passage and scrolls to it.
Future<void> showSourceViewer(BuildContext context, NotebookController c, NotebookSource s, {String? highlight}) {
  return showNxSnapSheet<void>(
    context: context,
    snaps: const [0.62, 0.95],
    initial: highlight != null ? 0.95 : null,
    builder: (ctx, scroll) => NotebookSourceViewer(c: c, source: s, highlight: highlight, scroll: scroll),
  );
}

class NotebookSourceViewer extends StatefulWidget {
  const NotebookSourceViewer({super.key, required this.c, required this.source, this.highlight, this.scroll});
  final NotebookController c;
  final NotebookSource source;
  final String? highlight;
  final ScrollController? scroll;

  @override
  State<NotebookSourceViewer> createState() => _NotebookSourceViewerState();
}

class _NotebookSourceViewerState extends State<NotebookSourceViewer> {
  late NotebookSource _s = widget.source;
  bool _busy = false;
  bool _full = false;
  final _hit = GlobalKey();

  static const _previewChars = 24000;

  @override
  void initState() {
    super.initState();
    if (widget.highlight != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _hit.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), alignment: 0.2);
      });
    }
  }

  Future<void> _run(Future<void> Function() f, {String? done}) async {
    setState(() => _busy = true);
    try {
      await f();
      _s = widget.c.sourceById(_s.id) ?? _s;
      if (done != null && mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr(done))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr(notebookError(e).text))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename() async {
    final ctl = TextEditingController(text: _s.displayTitle);
    final t = await showAppBottomSheet<String>(
      context: context,
      title: 'เปลี่ยนชื่อแหล่ง',
      child: Builder(
        builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(key: const ValueKey('notebook-source-rename-field'), controller: ctl, autofocus: true),
          const SizedBox(height: 16),
          FilledButton(key: const ValueKey('notebook-source-rename-save'), onPressed: () => Navigator.pop(ctx, ctl.text), child: Text(tr('บันทึก'))),
        ]),
      ),
    );
    ctl.dispose();
    if (t == null || t.trim().isEmpty) return;
    await _run(() => widget.c.renameSource(_s, t));
  }

  Future<void> _delete() async {
    final ok = await showDeleteConfirm(context, name: _s.displayTitle, loses: const ['แหล่งนี้จะไม่ถูกใช้ตอบในแชทและสตูดิโอ'], note: null);
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    await _run(() => widget.c.deleteSource(_s));
    if (widget.c.sourceById(_s.id) == null) nav.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final st = sourceKindStyle(_s);
    final body = _s.body;
    final hit = findQuote(body, widget.highlight);
    final url = _s.url;
    final canWrite = widget.c.canWrite;
    final long = body.length > _previewChars && !_full && hit == null;
    return ListView(
      key: const ValueKey('notebook-source-viewer'),
      controller: widget.scroll,
      padding: EdgeInsets.fromLTRB(20, 0, 20, 28 + MediaQuery.paddingOf(context).bottom),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          NotebookIconBadge(icon: st.icon, color: st.color, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_s.displayTitle, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.3)),
              const SizedBox(height: 2),
              Text('${tr(notebookSourceKindLabel(_s))} · ${tr('${body.length} ตัวอักษร')}', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilterChip(
            key: const ValueKey('notebook-viewer-toggle'),
            avatar: Icon(_s.enabled ? NxI.checkCircle : NxI.circle, size: 16),
            label: Text(tr(_s.enabled ? 'ใช้ในแชทอยู่' : 'ไม่ได้ใช้ในแชท')),
            selected: _s.enabled,
            showCheckmark: false,
            onSelected: canWrite && !_busy ? (v) => _run(() => widget.c.toggleSource(_s, v)).then((_) => setState(() {})) : null,
          ),
          if (canWrite && _s.kind != 'manual')
            ActionChip(key: const ValueKey('notebook-viewer-refresh'), avatar: const Icon(LucideIcons300.refreshCw, size: 16), label: Text(tr('รีเฟรช')), onPressed: _busy ? null : () => _run(() => widget.c.refreshSource(_s), done: 'รีเฟรชแล้ว')),
          if (canWrite) ActionChip(key: const ValueKey('notebook-viewer-rename'), avatar: const Icon(NxI.pencilSimple, size: 16), label: Text(tr('เปลี่ยนชื่อ')), onPressed: _busy ? null : _rename),
          if (url != null) ActionChip(avatar: const Icon(NxI.arrowSquareOut, size: 16), label: Text(tr('เปิดลิงก์')), onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
          ActionChip(
            avatar: const Icon(NxI.copySimple, size: 16),
            label: Text(tr('คัดลอก')),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: body));
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('คัดลอกแล้ว'))));
            },
          ),
          if (canWrite)
            ActionChip(
              key: const ValueKey('notebook-viewer-delete'),
              avatar: Icon(NxI.trash, size: 16, color: cs.error),
              label: Text(tr('ลบ'), style: TextStyle(color: cs.error)),
              onPressed: _busy ? null : _delete,
            ),
        ]),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(minHeight: 2)),
        if (_s.status == NotebookSourceStatus.error || _s.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(tr(_s.error ?? 'อ่านเนื้อหาจากไฟล์นี้ไม่สำเร็จ'), style: TextStyle(color: cs.error)),
          ),
        const SizedBox(height: 16),
        if (widget.highlight != null && hit == null) _quoteCard(context, widget.highlight!),
        if (body.trim().isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(tr('ยังไม่มีข้อความในแหล่งนี้'), textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          )
        else if (hit != null)
          _highlighted(context, body, hit)
        else
          NxMarkdown(data: long ? '${body.substring(0, _previewChars)}…' : body),
        if (long)
          TextButton(onPressed: () => setState(() => _full = true), child: Text(tr('แสดงทั้งหมด'))),
      ],
    );
  }

  Widget _quoteCard(BuildContext context, String quote) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('notebook-viewer-quote'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDE68A).withValues(alpha: theme.brightness == Brightness.dark ? 0.18 : 0.45),
        borderRadius: BorderRadius.circular(14),
        border: const Border(left: BorderSide(color: Color(0xFFF59E0B), width: 3)),
      ),
      child: Text(quote, style: theme.textTheme.bodyMedium?.copyWith(height: 1.55)),
    );
  }

  /// Body split in paragraphs; the one holding the quote is highlighted and scrolled to.
  Widget _highlighted(BuildContext context, String body, ({int start, int end}) hit) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final base = theme.textTheme.bodyLarge?.copyWith(height: 1.6, fontSize: 15.5);
    final mark = base?.copyWith(backgroundColor: const Color(0xFFFDE68A).withValues(alpha: dark ? 0.35 : 0.9), color: dark ? Colors.white : const Color(0xFF1F2937));
    final out = <Widget>[];
    var offset = 0;
    var first = true;
    for (final para in body.split(RegExp(r'\n\s*\n'))) {
      final start = body.indexOf(para, offset);
      final end = start + para.length;
      offset = end;
      final overlaps = hit.start < end && hit.end > start;
      if (!overlaps) {
        out.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: SelectableText(para.trim(), style: base)));
        continue;
      }
      final a = (hit.start - start).clamp(0, para.length), b = (hit.end - start).clamp(0, para.length);
      final isFirst = first;
      first = false;
      out.add(Padding(
        key: isFirst ? _hit : null,
        padding: const EdgeInsets.only(bottom: 12),
        child: SelectableText.rich(
          TextSpan(style: base, children: [
            TextSpan(text: para.substring(0, a)),
            TextSpan(text: para.substring(a, b), style: mark),
            TextSpan(text: para.substring(b)),
          ]),
          key: isFirst ? const ValueKey('notebook-viewer-highlight') : null,
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }
}

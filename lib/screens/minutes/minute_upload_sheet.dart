import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../services/minutes/minute_uploader.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import 'minutes_widgets.dart';

/// A file chosen to upload (tests inject one instead of the system picker).
class PickedMedia {
  const PickedMedia({required this.path, required this.name, required this.size});
  final String path;
  final String name;
  final int size;
}

@visibleForTesting
Future<PickedMedia?> Function() pickMinuteMedia = () async {
  final r = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['mp3', 'm4a', 'wav', 'aac', 'ogg', 'webm', 'flac', 'amr', 'mp4', 'mov', 'mkv', 'avi', '3gp'],
    withData: false,
  );
  final f = r?.files.firstOrNull;
  if (f == null || f.path == null) return null;
  return PickedMedia(path: f.path!, name: f.name, size: f.size);
};

String _mimeOf(String name) {
  final ext = name.split('.').last.toLowerCase();
  return const {
        'mp3': 'audio/mpeg',
        'm4a': 'audio/mp4',
        'wav': 'audio/wav',
        'aac': 'audio/aac',
        'ogg': 'audio/ogg',
        'webm': 'video/webm',
        'flac': 'audio/flac',
        'amr': 'audio/amr',
        'mp4': 'video/mp4',
        'mov': 'video/quicktime',
        'mkv': 'video/x-matroska',
        'avi': 'video/x-msvideo',
        '3gp': 'video/3gpp',
      }[ext] ??
      'application/octet-stream';
}

/// "อัปโหลดไฟล์": pick audio / video → what ISAAC should do → resumable upload in the background.
Future<void> showMinuteUploadSheet(BuildContext context) async {
  final file = await pickMinuteMedia();
  if (file == null || !context.mounted) return;
  await showAppBottomSheet<void>(context: context, title: tr('อัปโหลดไฟล์ประชุม'), child: _UploadPanel(file: file));
}

class _UploadPanel extends StatefulWidget {
  const _UploadPanel({required this.file});
  final PickedMedia file;
  @override
  State<_UploadPanel> createState() => _UploadPanelState();
}

class _UploadPanelState extends State<_UploadPanel> {
  late final _title = TextEditingController(text: widget.file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''));
  final _email = TextEditingController();
  String _spoken = L10n.isEn ? 'en' : 'th';
  String _template = 'general';
  bool _summarize = true;
  bool _tasks = false;
  List<String> _translate = const [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final emails = [for (final e in _email.text.split(RegExp(r'[,;\s]+'))) if (e.contains('@')) e.trim()];
      final features = {'summarize': _summarize, 'translate': _translate, 'tasks': _summarize && _tasks, 'email_to': _summarize ? emails : const <String>[]};
      await MinuteUploader.instance.add(
        path: widget.file.path,
        filename: widget.file.name,
        mime: _mimeOf(widget.file.name),
        body: {'title': _title.text.trim(), 'locale': _spoken, 'languages': [_spoken, ..._translate], 'template': _template, 'features': features},
        complete: {'features': features, 'template': _template, 'summary_mode': _summarize ? 'now' : 'later'},
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('กำลังอัปโหลด — ปิดแอปได้ ไอแซคจะอัปโหลดต่อและแจ้งเมื่อสรุปเสร็จ'))));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst(RegExp(r'^[A-Za-z]+Exception\(?[0-9, ]*\)?:? ?'), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = widget.file;
    final mb = f.size / (1 << 20);
    final mins = (mb / 1).round(); // ~1 MB per minute for compressed audio: only a rough hint
    return Column(
      key: const ValueKey('minute-upload-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(_mimeOf(f.name).startsWith('video/') ? NxI.videoCamera : NxI.microphone),
          title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(mb >= 1024 ? '${(mb / 1024).toStringAsFixed(2)} GB' : '${mb.toStringAsFixed(1)} MB'),
        ),
        TextField(key: const ValueKey('minute-upload-title'), controller: _title, decoration: InputDecoration(labelText: tr('ชื่อการประชุม'), border: const OutlineInputBorder())),
        MinuteSectionTitle('ภาษาที่พูดในไฟล์', icon: NxI.microphone),
        MinuteLangChips(selected: [_spoken], single: true, onChanged: (v) => setState(() => _spoken = v.isEmpty ? _spoken : v.first)),
        MinuteSectionTitle('ให้ไอแซคทำอะไรบ้าง', icon: NxI.sparkle),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: true,
          onChanged: null,
          title: Text(tr('ถอดข้อความ พร้อมเวลา')),
          subtitle: Text(tr('ทำทุกไฟล์')),
        ),
        CheckboxListTile(
          key: const ValueKey('minute-upload-summarize'),
          contentPadding: EdgeInsets.zero,
          value: _summarize,
          onChanged: (v) => setState(() => _summarize = v ?? true),
          title: Text(tr('สรุปการประชุม')),
          subtitle: Text(tr('ใจความ มติ สิ่งที่ต้องทำ คำถามค้าง ลำดับหัวข้อ')),
        ),
        if (_summarize) ...[
          Padding(padding: const EdgeInsets.only(left: 8, bottom: 6), child: MinuteTemplatePicker(value: _template, onChanged: (v) => setState(() => _template = v))),
          CheckboxListTile(
            key: const ValueKey('minute-upload-tasks'),
            contentPadding: EdgeInsets.zero,
            value: _tasks,
            onChanged: (v) => setState(() => _tasks = v ?? false),
            title: Text(tr('สร้างงานจากสิ่งที่ต้องทำ')),
          ),
        ],
        MinuteSectionTitle('แปลเป็น', icon: NxI.languages),
        MinuteLangChips(selected: _translate, exclude: {_spoken}, onChanged: (v) => setState(() => _translate = v)),
        if (_summarize) ...[
          MinuteSectionTitle('ส่งสรุปทางอีเมล (ไม่บังคับ)', icon: NxI.envelope),
          TextField(key: const ValueKey('minute-upload-email'), controller: _email, decoration: InputDecoration(hintText: tr('a@company.com, b@company.com'), border: const OutlineInputBorder(), isDense: true)),
        ],
        const SizedBox(height: 10),
        Text(
          tr('ไฟล์ใหญ่ได้ถึง 8 GB · อัปโหลดทีละส่วน หลุดแล้วต่อได้ · ประมวลผลบนเซิร์ฟเวอร์ ไม่ต้องเปิดแอปค้างไว้') + (mins > 60 ? ' · ${tr('ไฟล์ยาว อาจใช้เวลาหลายนาที')}' : ''),
          style: theme.textTheme.bodySmall,
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr(_error!), style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('minute-upload-go'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _busy ? null : _go,
            icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.uploadSimple),
            label: Text(tr('เริ่มอัปโหลด')),
          ),
        ),
      ],
    );
  }
}

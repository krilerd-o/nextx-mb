import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/minutes/minutes.dart';
import '../../core/navigation/app_routes.dart';
import '../../services/minutes/minute_recorder.dart';
import '../../services/notebook/notebook_recorder.dart' show RecordStart;
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../notebook/notebook_recorder_ui.dart' show showMicPermissionSheet;
import 'minute_record_screen.dart';
import 'minutes_widgets.dart';

/// Options chosen before a recording starts.
class MinuteStartOptions {
  const MinuteStartOptions({required this.title, required this.spoken, this.translateTo, this.template = 'general'});
  final String title;
  final String spoken;
  final String? translateTo;
  final String template;
}

/// "บันทึกเสียง" / "บันทึกวิดีโอ": options sheet → microphone → the full-screen recorder.
Future<bool> startMinuteRecording(BuildContext context, {bool video = false, Map<String, dynamic>? ref, String? title}) async {
  final rec = MinuteRecorder.instance;
  final messenger = ScaffoldMessenger.maybeOf(context);
  void snack(String t) => messenger?.showSnackBar(SnackBar(content: Text(tr(t))));
  if (rec.active) {
    await openMinuteRecorder(context, rec);
    return true;
  }
  final opts = await showAppBottomSheet<MinuteStartOptions>(context: context, title: tr(video ? 'บันทึกวิดีโอการประชุม' : 'บันทึกเสียงการประชุม'), child: _StartPanel(video: video, title: title));
  if (opts == null || !context.mounted) return false;
  HapticFeedback.mediumImpact();
  final res = await rec.start(title: opts.title, locale: opts.spoken, languages: [opts.spoken, ?opts.translateTo], ref: ref, template: opts.template);
  if (!context.mounted) return res == RecordStart.started;
  switch (res) {
    case RecordStart.started:
      if (opts.translateTo != null) await rec.setTranslate(opts.translateTo);
      if (!context.mounted) return true;
      await openMinuteRecorder(context, rec, video: video);
      return true;
    case RecordStart.denied:
    case RecordStart.permanentlyDenied:
      await showMicPermissionSheet(context, permanent: res == RecordStart.permanentlyDenied);
    case RecordStart.inCall:
      snack(MinuteRecorder.inCallText);
    case RecordStart.busy:
      snack(rec.error ?? 'กำลังบันทึกอยู่');
    case RecordStart.unsupported:
    case RecordStart.failed:
      snack(rec.error ?? 'เริ่มบันทึกไม่สำเร็จ');
  }
  return false;
}

Future<void> openMinuteRecorder(BuildContext context, MinuteRecorder rec, {bool video = false}) async {
  final done = await Navigator.of(context, rootNavigator: true).push<FinishedMinute>(
    PageRouteBuilder<FinishedMinute>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => MinuteRecordScreen(recorder: rec, video: video),
      transitionsBuilder: (_, anim, _, child) {
        final a = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(a), child: child));
      },
    ),
  );
  if (done?.meetingId != null && context.mounted) context.push(AppRoutes.aiMinute(done!.meetingId!));
}

class _StartPanel extends StatefulWidget {
  const _StartPanel({required this.video, this.title});
  final bool video;
  final String? title;
  @override
  State<_StartPanel> createState() => _StartPanelState();
}

class _StartPanelState extends State<_StartPanel> {
  late final _title = TextEditingController(text: widget.title ?? '');
  String _spoken = L10n.isEn ? 'en' : 'th';
  String? _translate;
  String _template = 'general';

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('minute-start-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('minute-start-title'),
          controller: _title,
          decoration: InputDecoration(
            hintText: tr('ชื่อการประชุม เช่น ประชุมทีมขายประจำสัปดาห์'),
            prefixIcon: const Icon(NxI.pencilSimple, size: 18),
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        MinuteSectionTitle('ภาษาที่พูดในการประชุม', icon: NxI.microphone),
        MinuteLangChips(selected: [_spoken], single: true, onChanged: (v) => setState(() => _spoken = v.isEmpty ? _spoken : v.first)),
        MinuteSectionTitle('แปลสดเป็น (ไม่บังคับ)', icon: NxI.languages),
        MinuteLangChips(selected: [?_translate], single: true, exclude: {_spoken}, onChanged: (v) => setState(() => _translate = v.isEmpty ? null : v.first)),
        MinuteSectionTitle('รูปแบบสรุป', icon: NxI.sparkle),
        MinuteTemplatePicker(value: _template, onChanged: (v) => setState(() => _template = v)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(NxI.shieldCheck, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('แจ้งผู้ร่วมประชุมก่อนบันทึกทุกครั้ง · บันทึกต่อได้แม้ล็อกหน้าจอ · ถ้าเน็ตหลุด ไอแซคจะถอดจากไฟล์ให้ภายหลัง'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('minute-start-go'),
            style: FilledButton.styleFrom(backgroundColor: kMinuteRecord, padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: Icon(widget.video ? NxI.videoCamera : NxI.microphone),
            label: Text(tr('เริ่มบันทึก')),
            onPressed: () => Navigator.of(context).pop(MinuteStartOptions(title: _title.text.trim(), spoken: _spoken, translateTo: _translate, template: _template)),
          ),
        ),
      ],
    );
  }
}

/// "จบการประชุม": summarise now or later, template, translations, who gets the minutes, tasks.
Future<MinuteFinish?> showMinuteFinishSheet(BuildContext context, {String template = 'general', List<String> translate = const [], String spoken = 'th'}) {
  return showAppBottomSheet<MinuteFinish>(context: context, title: tr('จบการประชุม'), child: _FinishPanel(template: template, translate: translate, spoken: spoken));
}

class _FinishPanel extends StatefulWidget {
  const _FinishPanel({required this.template, required this.translate, required this.spoken});
  final String template;
  final List<String> translate;
  final String spoken;
  @override
  State<_FinishPanel> createState() => _FinishPanelState();
}

class _FinishPanelState extends State<_FinishPanel> {
  bool _now = true;
  late String _template = widget.template;
  late List<String> _translate = [...widget.translate];
  bool _tasks = false;
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Widget _mode(bool now, IconData icon, String title, String hint) {
    final cs = Theme.of(context).colorScheme;
    final on = _now == now;
    return Expanded(
      child: InkWell(
        key: ValueKey(now ? 'minute-finish-now' : 'minute-finish-later'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _now = now),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? cs.primary : cs.outlineVariant, width: on ? 2 : 1),
            color: on ? cs.primary.withValues(alpha: 0.06) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: on ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(height: 6),
              Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(tr(hint), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('minute-finish-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _mode(true, NxI.sparkle, 'สรุปตอนนี้', 'ไอแซคสรุปทันทีที่ประมวลผลเสร็จ'),
          const SizedBox(width: 8),
          _mode(false, NxI.clock, 'สรุปภายหลัง', 'เก็บบันทึกและถอดข้อความไว้ก่อน'),
        ]),
        if (_now) ...[
          MinuteSectionTitle('รูปแบบสรุป', icon: NxI.sparkle),
          MinuteTemplatePicker(value: _template, onChanged: (v) => setState(() => _template = v)),
        ],
        MinuteSectionTitle('แปลบันทึกการประชุมเป็น', icon: NxI.languages),
        MinuteLangChips(selected: _translate, exclude: {widget.spoken}, onChanged: (v) => setState(() => _translate = v)),
        if (_now) ...[
          MinuteSectionTitle('ส่งสรุปทางอีเมล (ไม่บังคับ)', icon: NxI.envelope),
          TextField(
            key: const ValueKey('minute-finish-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(hintText: tr('a@company.com, b@company.com'), border: const OutlineInputBorder(), isDense: true),
          ),
          SwitchListTile(
            key: const ValueKey('minute-finish-tasks'),
            contentPadding: EdgeInsets.zero,
            value: _tasks,
            onChanged: (v) => setState(() => _tasks = v),
            title: Text(tr('สร้างงานจากสิ่งที่ต้องทำ')),
            subtitle: Text(tr('มอบหมายตามชื่อที่พูดถึงในการประชุม')),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const ValueKey('minute-finish-go'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () => Navigator.of(context).pop(
              MinuteFinish(
                summarizeNow: _now,
                template: _template,
                translate: _translate,
                emailTo: _now ? [for (final e in _email.text.split(RegExp(r'[,;\s]+'))) if (e.contains('@')) e.trim()] : const [],
                tasks: _now && _tasks,
              ),
            ),
            child: Text(tr('จบและบันทึก')),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../../core/i18n.dart';
import '../../core/notebook/notebook_recording.dart';
import '../../services/notebook/notebook_controller.dart';
import '../../services/notebook/notebook_recorder.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../comm_ai/comm_ai_isaac.dart';
import 'notebook_record_screen.dart';
import 'notebook_widgets.dart';

/// Opens system settings (tests replace it).
@visibleForTesting
Future<bool> Function() openMicSettings = openAppSettings;

/// "อัดเสียง" in a notebook: consent (first time) → microphone → the full-screen recorder.
/// Returns false when it did not start.
Future<bool> startNotebookRecording(BuildContext context, NotebookController c) async {
  final rec = c.recorder;
  final messenger = ScaffoldMessenger.maybeOf(context);
  void snack(String t) => messenger?.showSnackBar(SnackBar(content: Text(tr(t))));
  if (rec.active) {
    if (rec.notebookId == c.id) {
      await openNotebookRecorder(context, rec);
      return true;
    }
    snack('กำลังบันทึกเสียงในสมุดอื่นอยู่ — จบอันนั้นก่อน');
    return false;
  }
  if (!await NotebookRecorder.consentRemembered()) {
    if (!context.mounted) return false;
    final ok = await showNotebookRecordConsent(context);
    if (ok != true || !context.mounted) return false;
  }
  HapticFeedback.mediumImpact();
  final nb = c.notebook;
  final res = await rec.start(notebookId: c.id, notebookTitle: nb?.title, locale: L10n.isEn ? 'en' : 'th');
  if (!context.mounted) return res == RecordStart.started;
  switch (res) {
    case RecordStart.started:
      await openNotebookRecorder(context, rec);
      return true;
    case RecordStart.denied:
    case RecordStart.permanentlyDenied:
      await showMicPermissionSheet(context, permanent: res == RecordStart.permanentlyDenied);
    case RecordStart.unsupported:
      c.markRecordingsUnsupported();
      snack('เซิร์ฟเวอร์นี้ยังไม่รองรับการบันทึกเสียงในสมุดโน้ต');
    case RecordStart.inCall:
      snack(NotebookRecorder.inCallText);
    case RecordStart.busy:
      snack('กำลังบันทึกเสียงอยู่');
    case RecordStart.failed:
      snack(rec.error ?? 'เริ่มบันทึกไม่สำเร็จ');
  }
  return false;
}

Future<void> openNotebookRecorder(BuildContext context, NotebookRecorder rec) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => NotebookRecordScreen(recorder: rec),
      transitionsBuilder: (_, anim, _, child) {
        final a = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(a),
            child: child,
          ),
        );
      },
    ),
  );
}

// ------------------------------------------------------------------ consent

/// "กำลังจะบันทึกเสียงและถอดข้อความ…" — once, unless "ไม่ต้องถามอีก" is left off.
Future<bool?> showNotebookRecordConsent(BuildContext context) {
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push<bool>(ModalBottomSheetRoute<bool>(isScrollControlled: true, backgroundColor: Colors.transparent, modalBarrierColor: Colors.black54, builder: (_) => const NotebookRecordConsentPanel()));
}

class NotebookRecordConsentPanel extends StatefulWidget {
  const NotebookRecordConsentPanel({super.key});

  @override
  State<NotebookRecordConsentPanel> createState() => _NotebookRecordConsentPanelState();
}

class _NotebookRecordConsentPanelState extends State<NotebookRecordConsentPanel> {
  bool _remember = false;

  Widget _point(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 16, color: const Color(0xFFFDA4AF)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(tr(text), style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.45)),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        key: const ValueKey('notebook-record-consent'),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xF51E293B), Color(0xF50F172A)]),
          border: Border.all(color: Colors.white12),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 30, offset: Offset(0, 12))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const IsaacAvatar(mood: 'listening', size: 76),
                  Positioned(
                    right: -2,
                    bottom: 2,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: kRecordRed,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF1E293B), width: 3),
                      ),
                      child: const Icon(NxI.microphone, size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              tr('บันทึกเสียงและถอดข้อความ'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              tr('กำลังจะบันทึกเสียงและถอดข้อความแบบสด เมื่อจบ ไอแซคจะเก็บเสียงไว้ในสมุดนี้และสรุปให้'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 18),
            _point(LucideIcons300.users, 'แจ้งผู้ร่วมประชุมก่อนเริ่มบันทึกทุกครั้ง'),
            _point(LucideIcons300.pause, 'หยุดชั่วคราว อัดต่อ หรือย่อเป็นหน้าต่างลอยได้ — ปิดจอแล้วยังบันทึกต่อ'),
            _point(LucideIcons300.wifiOff, 'เน็ตหลุดก็ไม่หาย เสียงเก็บในเครื่องแล้วส่งให้เมื่อกลับมาออนไลน์'),
            const SizedBox(height: 2),
            InkWell(
              key: const ValueKey('notebook-record-remember'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _remember = !_remember),
              child: Row(
                children: [
                  Checkbox(
                    value: _remember,
                    onChanged: (v) => setState(() => _remember = v ?? false),
                    side: const BorderSide(color: Colors.white38),
                  ),
                  Text(tr('ไม่ต้องถามอีก'), style: const TextStyle(color: Colors.white60, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            FilledButton.icon(
              key: const ValueKey('notebook-record-accept'),
              style: FilledButton.styleFrom(
                backgroundColor: kRecordRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: () async {
                if (_remember) await NotebookRecorder.rememberConsent(true);
                if (context.mounted) Navigator.pop(context, true);
              },
              icon: const Icon(NxI.microphone),
              label: Text(tr('เริ่มบันทึก'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('notebook-record-cancel'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white10,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('ยกเลิก')),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- permission

/// Microphone refused: explain, and open Settings when the system will not ask again.
Future<void> showMicPermissionSheet(BuildContext context, {required bool permanent}) {
  return showAppBottomSheet<void>(
    context: context,
    title: null,
    child: Builder(
      builder: (ctx) => Column(
        key: const ValueKey('notebook-mic-permission'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: IsaacAvatar(mood: 'shrug', size: 64, animate: false)),
          const SizedBox(height: 12),
          Text(
            tr('ต้องใช้ไมโครโฟน'),
            textAlign: TextAlign.center,
            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              permanent
                  ? 'แอปยังไม่ได้รับอนุญาตให้ใช้ไมโครโฟน เปิดได้ที่ การตั้งค่า › MOAI NEXT › ไมโครโฟน แล้วกลับมาเริ่มบันทึกอีกครั้ง'
                  : 'ไอแซคต้องใช้ไมโครโฟนเพื่อบันทึกเสียงและถอดข้อความ กด "อนุญาต" เมื่อระบบถาม',
            ),
            textAlign: TextAlign.center,
            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant, height: 1.45),
          ),
          const SizedBox(height: 18),
          if (permanent)
            FilledButton.icon(
              key: const ValueKey('notebook-mic-settings'),
              onPressed: () {
                Navigator.pop(ctx);
                unawaited(openMicSettings());
              },
              icon: const Icon(NxI.gear),
              label: Text(tr('เปิดการตั้งค่า')),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(permanent ? 'ไว้ทีหลัง' : 'ตกลง'))),
        ],
      ),
    ),
  );
}

// ----------------------------------------------------------- sources cards

/// In the sources list: the live recording of this notebook (tap → the recorder).
class NotebookLiveRecordingCard extends StatelessWidget {
  const NotebookLiveRecordingCard({super.key, required this.recorder});
  final NotebookRecorder recorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paused = recorder.paused;
    return NotebookCard(
      key: const ValueKey('notebook-recording-live-card'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      border: kRecordRed.withValues(alpha: 0.35),
      onTap: () => openNotebookRecorder(context, recorder),
      child: Row(
        children: [
          NotebookIconBadge(icon: paused ? LucideIcons300.pause : LucideIcons300.mic, color: kRecordRed),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recorder.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                _Ticker(
                  builder: (_) => Text(
                    '${tr(paused ? 'หยุดชั่วคราว' : 'กำลังบันทึก')} · ${recordingClock(recorder.elapsed.inMilliseconds)}',
                    style: theme.textTheme.labelSmall?.copyWith(color: kRecordRed, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
              ],
            ),
          ),
          Icon(NxI.caretRight, size: 18, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// In the sources list: a recording being uploaded / processed (or one that failed).
class NotebookRecordingCard extends StatelessWidget {
  const NotebookRecordingCard({super.key, required this.c, required this.r});
  final NotebookController c;
  final NotebookRecording r;

  Future<void> _menu(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final pick = await showAppBottomSheet<String>(
      context: context,
      title: null,
      child: Builder(
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (r.status == RecordingStatus.failed && !r.id.startsWith('local:'))
              ListTile(leading: const Icon(LucideIcons300.refreshCw), title: Text(tr('ลองประมวลผลใหม่')), onTap: () => Navigator.pop(ctx, 'retry')),
            ListTile(
              leading: const Icon(NxI.trash, color: kNxDangerRed),
              title: Text(
                tr('ลบบันทึกเสียงนี้'),
                style: const TextStyle(color: kNxDangerRed, fontWeight: FontWeight.w600),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (pick == null || !context.mounted) return;
    try {
      if (pick == 'retry') {
        await c.retryRecording(r);
      } else if (pick == 'delete') {
        final ok = await showDeleteConfirm(context, name: r.displayTitle, loses: const ['เสียงและข้อความที่ถอดไว้'], note: null);
        if (ok) await c.deleteRecording(r);
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(tr(notebookError(e).text))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final failed = r.status == RecordingStatus.failed;
    final (String text, Color color) = switch (r.status) {
      RecordingStatus.uploading => ('กำลังส่งเสียงขึ้นเซิร์ฟเวอร์…', const Color(0xFF0EA5E9)),
      RecordingStatus.failed => (r.error ?? 'ประมวลผลไม่สำเร็จ', cs.error),
      RecordingStatus.recording || RecordingStatus.paused => ('กำลังบันทึกจากอีกเครื่อง', kRecordRed),
      _ => ('กำลังประมวลผล… ไอแซคกำลังถอดเสียงและสรุป', const Color(0xFFD97706)),
    };
    return NotebookCard(
      key: ValueKey('notebook-recording-${r.id}'),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      onTap: failed ? () => _menu(context) : null,
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              NotebookIconBadge(icon: LucideIcons300.audioLines, color: failed ? cs.error : kRecordRed),
              if (!failed)
                const Positioned(
                  right: -3,
                  bottom: -3,
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD97706))),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  r.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  tr(text),
                  key: ValueKey('notebook-recording-status-${r.id}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
                ),
                if (r.status.working) ...[
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(minHeight: 4, color: color, backgroundColor: color.withValues(alpha: 0.12)),
                  ),
                ],
              ],
            ),
          ),
          if (r.durationMs > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                recordingClock(r.durationMs),
                style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          IconButton(tooltip: tr('ตัวเลือก'), visualDensity: VisualDensity.compact, icon: const Icon(NxI.dotsThreeVertical, size: 18), onPressed: () => _menu(context)),
        ],
      ),
    );
  }
}

/// Rebuilds every second (elapsed time).
class _Ticker extends StatefulWidget {
  const _Ticker({required this.builder});
  final WidgetBuilder builder;

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

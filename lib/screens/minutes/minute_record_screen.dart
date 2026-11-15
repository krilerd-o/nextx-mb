import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/minutes/minutes.dart';
import '../../services/api_client.dart';
import '../../services/minutes/minute_board_controller.dart';
import '../../services/minutes/minute_recorder.dart';
import '../../services/minutes/minute_uploader.dart';
import '../../services/notebook/notebook_recorder.dart' show LiveState;
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_icons.dart';
import 'minute_record_flow.dart';
import 'minute_workspace.dart';
import 'minutes_widgets.dart';

/// Camera seam (tests run without a camera).
abstract class MinuteCamera {
  Future<void> start();
  Future<String?> stop();
  Widget preview();
  Future<void> dispose();
}

/// Camera video WITHOUT sound (the microphone belongs to the recorder: live captions + WAV parts);
/// the server joins the two after the meeting.
class DeviceMinuteCamera implements MinuteCamera {
  CameraController? _c;
  @override
  Future<void> start() async {
    final cams = await availableCameras();
    if (cams.isEmpty) throw StateError('no camera');
    final cam = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
    final c = CameraController(cam, ResolutionPreset.high, enableAudio: false);
    await c.initialize();
    await c.startVideoRecording();
    _c = c;
  }

  @override
  Future<String?> stop() async {
    final c = _c;
    if (c == null || !c.value.isRecordingVideo) return null;
    final f = await c.stopVideoRecording();
    return f.path;
  }

  @override
  Widget preview() {
    final c = _c;
    return c == null || !c.value.isInitialized ? const SizedBox.shrink() : CameraPreview(c);
  }

  @override
  Future<void> dispose() async => _c?.dispose();
}

/// Tests replace the camera.
@visibleForTesting
MinuteCamera Function() minuteCameraFactory = DeviceMinuteCamera.new;

/// Full-screen recorder: timer, waveform, live captions (with live translation), bookmarks,
/// pause / resume, and "จบการประชุม" (summarise now / later).
class MinuteRecordScreen extends StatefulWidget {
  const MinuteRecordScreen({super.key, required this.recorder, this.video = false});
  final MinuteRecorder recorder;
  final bool video;

  @override
  State<MinuteRecordScreen> createState() => _MinuteRecordScreenState();
}

class _MinuteRecordScreenState extends State<MinuteRecordScreen> {
  MinuteRecorder get r => widget.recorder;
  Timer? _tick;
  MinuteCamera? _cam;
  bool _camOn = false;
  bool _stopping = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    r.screenShown();
    r.addListener(_changed);
    r.lines.addListener(_follow);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
    if (widget.video) _startCamera();
  }

  Future<void> _startCamera() async {
    final cam = minuteCameraFactory();
    try {
      await cam.start();
      if (!mounted) {
        await cam.dispose();
        return;
      }
      setState(() {
        _cam = cam;
        _camOn = true;
      });
    } catch (_) {
      await cam.dispose();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('เปิดกล้องไม่ได้ — บันทึกเฉพาะเสียงต่อ'))));
    }
  }

  MinuteBoardController? _board;

  /// Notes / checklist / board / sketch while recording — kept with the meeting and used in the summary.
  Future<void> _workspace() async {
    final id = widget.recorder.meetingId;
    if (id == null) return;
    final api = _boardApi();
    if (_board == null || _board!.meetingId != id) {
      _board?.dispose();
      _board = MinuteBoardController(meetingId: id, api: api);
      unawaited(_board!.start());
    }
    await showMinuteWorkspaceSheet(context, _board!, api: api);
  }

  ApiClient? _boardApi() {
    try {
      return context.read<AppConfig>().apiClient;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _board?.dispose();
    _tick?.cancel();
    r.removeListener(_changed);
    r.lines.removeListener(_follow);
    r.screenHidden();
    _scroll.dispose();
    unawaited(_cam?.dispose());
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (!r.active && !_stopping) Navigator.of(context).maybePop();
  }

  void _follow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      if (pos.maxScrollExtent - pos.pixels < 120) _scroll.animateTo(pos.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  Future<void> _stop() async {
    final finish = await showMinuteFinishSheet(context, template: 'general', translate: [?r.translateTo], spoken: r.locale);
    if (finish == null || !mounted) return;
    _stopping = true;
    HapticFeedback.mediumImpact();
    String? videoPath;
    if (_cam != null) {
      try {
        videoPath = await _cam!.stop();
      } catch (_) {}
    }
    final effective = videoPath == null ? finish : finish.withVideo();
    final done = await r.stop(effective);
    if (videoPath != null && done?.meetingId != null) {
      // Upload the camera file in the background; the server waits for it, then joins it with the audio.
      unawaited(
        MinuteUploader.instance
            .add(path: videoPath, filename: 'camera.mp4', mime: 'video/mp4', body: {'meeting_id': int.tryParse(done!.meetingId!) ?? done.meetingId})
            .then((_) {}, onError: (_) {}),
      );
    }
    if (mounted) Navigator.of(context).pop(done);
  }

  Future<void> _discard() async {
    final ok = await showDeleteConfirm(context, name: tr('การบันทึกนี้'), title: tr('ทิ้งการบันทึกนี้?'), loses: const ['เสียงที่บันทึกไว้', 'ข้อความที่ถอดไว้'], note: null, confirmLabel: 'ทิ้ง');
    if (!ok || !mounted) return;
    _stopping = true;
    await _cam?.stop().catchError((_) => null);
    await r.discard();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickTranslate() async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(tr('ไม่แปล')), leading: const Icon(NxI.x), onTap: () => Navigator.pop(ctx, '')),
            for (final e in kMinuteLangs.entries)
              if (e.key != r.locale)
                ListTile(key: ValueKey('minute-rec-tr-${e.key}'), title: Text(tr(e.value)), trailing: r.translateTo == e.key ? const Icon(NxI.check) : null, onTap: () => Navigator.pop(ctx, e.key)),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await r.setTranslate(picked.isEmpty ? null : picked);
  }

  String get _liveText => switch (r.live) {
    LiveState.live => r.translateTo != null ? '${tr('ถอดสด')} + ${tr('แปลเป็น')}${tr(minuteLangLabel(r.translateTo!))}' : tr('ถอดสด'),
    LiveState.paused => tr('หยุดชั่วคราว'),
    LiveState.connecting => tr('กำลังเชื่อมต่อ…'),
    LiveState.reconnecting => tr('กำลังเชื่อมต่อใหม่…'),
    LiveState.offline => tr('ออฟไลน์ — ยังบันทึกอยู่'),
    LiveState.unavailable => tr('ถอดจากไฟล์ภายหลัง'),
  };

  @override
  Widget build(BuildContext context) {
    final lines = r.lines.value;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        key: const ValueKey('minute-record-screen'),
        backgroundColor: const Color(0xFF0B1020),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(tooltip: tr('ย่อ'), icon: const Icon(NxI.caretDown, color: Colors.white70), onPressed: () => Navigator.of(context).maybePop()),
                    Expanded(
                      child: GestureDetector(
                        onTap: _rename,
                        child: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                    ),
                    if (r.meetingId != null)
                      IconButton(key: const ValueKey('minute-rec-workspace'), tooltip: tr('โน้ต · เช็กลิสต์ · บอร์ด · สเก็ตช์'), icon: const Icon(NxI.notePencil, color: Colors.white), onPressed: _workspace),
                    IconButton(key: const ValueKey('minute-rec-discard'), tooltip: tr('ทิ้ง'), icon: const Icon(NxI.trash, color: Colors.white54), onPressed: _discard),
                  ],
                ),
              ),
              if (_camOn && _cam != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: ClipRRect(borderRadius: BorderRadius.circular(20), child: AspectRatio(aspectRatio: 3 / 4, child: _cam!.preview())),
                ),
              const SizedBox(height: 10),
              Text(minuteClock(r.elapsed.inMilliseconds), key: const ValueKey('minute-rec-timer'), style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w300, fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: r.recording ? kMinuteRecord : Colors.white38, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(_liveText, key: const ValueKey('minute-rec-live'), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                ],
              ),
              ValueListenableBuilder<List<double>>(
                valueListenable: r.levels,
                builder: (_, lv, _) => SizedBox(height: 44, child: CustomPaint(painter: _Wave(lv, r.recording), size: const Size(double.infinity, 44))),
              ),
              ValueListenableBuilder<String?>(
                valueListenable: r.notice,
                builder: (_, n, _) => n == null
                    ? const SizedBox.shrink()
                    : Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                        child: Text(tr(n), style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 12.5)),
                      ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
                        child: Row(
                          children: [
                            const Icon(NxI.textAlignLeft, size: 16, color: Colors.white54),
                            const SizedBox(width: 6),
                            Expanded(child: Text(tr('คำบรรยายสด'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600))),
                            TextButton.icon(
                              key: const ValueKey('minute-rec-translate'),
                              onPressed: _pickTranslate,
                              icon: const Icon(NxI.languages, size: 16),
                              label: Text(r.translateTo == null ? tr('แปลสด') : tr(minuteLangLabel(r.translateTo!))),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: lines.isEmpty
                            ? Center(child: Text(tr('เริ่มพูดได้เลย ไอแซคกำลังฟัง…'), style: const TextStyle(color: Colors.white38)))
                            : ValueListenableBuilder<Map<int, String>>(
                                valueListenable: r.translated,
                                builder: (_, tr0, _) => ListView.builder(
                                  controller: _scroll,
                                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                                  itemCount: lines.length,
                                  itemBuilder: (_, i) {
                                    final l = lines[i];
                                    return Padding(
                                      key: ValueKey('minute-rec-line-${l.seq}'),
                                      padding: const EdgeInsets.symmetric(vertical: 5),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(width: 44, child: Text(minuteClock(l.startMs), style: const TextStyle(color: Colors.white38, fontSize: 11.5))),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(l.text, style: TextStyle(color: l.partial ? Colors.white54 : Colors.white, height: 1.4)),
                                                if (tr0[l.seq] != null) Text(tr0[l.seq]!, style: const TextStyle(color: Color(0xFFA5B4FC), height: 1.4, fontSize: 13)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _side(NxI.bookmark, '${tr('จุดสำคัญ')}${r.bookmarks.isEmpty ? '' : ' (${r.bookmarks.length})'}', const ValueKey('minute-rec-bookmark'), () {
                      HapticFeedback.selectionClick();
                      r.addBookmark();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 1), content: Text('${tr('ปักหมุดที่')} ${minuteClock(r.elapsed.inMilliseconds)}')));
                    }),
                    GestureDetector(
                      key: const ValueKey('minute-rec-stop'),
                      onTap: _stop,
                      child: Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 4)),
                        child: Center(child: Container(width: 30, height: 30, decoration: BoxDecoration(color: kMinuteRecord, borderRadius: BorderRadius.circular(8)))),
                      ),
                    ),
                    _side(r.paused ? NxI.play : NxI.pause, tr(r.paused ? 'บันทึกต่อ' : 'หยุดชั่วคราว'), const ValueKey('minute-rec-pause'), () => r.togglePause()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _side(IconData icon, String label, Key key, VoidCallback onTap) => SizedBox(
    width: 84,
    child: Column(
      children: [
        IconButton.filledTonal(key: key, onPressed: onTap, icon: Icon(icon), style: IconButton.styleFrom(backgroundColor: Colors.white12, foregroundColor: Colors.white, minimumSize: const Size(52, 52))),
        const SizedBox(height: 4),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
      ],
    ),
  );

  Future<void> _rename() async {
    final c = TextEditingController(text: r.title);
    final t = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ชื่อการประชุม')),
        content: TextField(controller: c, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('ยกเลิก'))), FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('บันทึก')))],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 400), c.dispose);
    if (t != null) r.rename(t);
  }
}

class _Wave extends CustomPainter {
  _Wave(this.levels, this.on);
  final List<double> levels;
  final bool on;
  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final p = Paint()
      ..color = on ? const Color(0xFFFB7185) : Colors.white24
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final n = levels.length;
    final step = size.width / (MinuteRecorder.levelHistory + 1);
    final start = size.width - n * step;
    for (var i = 0; i < n; i++) {
      final h = (levels[i].clamp(0.04, 1.0)) * size.height;
      final x = start + i * step;
      canvas.drawLine(Offset(x, (size.height - h) / 2), Offset(x, (size.height + h) / 2), p);
    }
  }

  @override
  bool shouldRepaint(_Wave old) => true;
}

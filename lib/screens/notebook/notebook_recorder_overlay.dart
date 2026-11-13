import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';

import '../../core/i18n.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/notebook/notebook_recording.dart';
import '../../services/calls/call_service.dart';
import '../../services/notebook/notebook_recorder.dart';
import '../../widgets/nx_icons.dart';
import '../comm_ai/comm_ai_isaac.dart';
import 'notebook_record_screen.dart';
import 'notebook_widgets.dart' show kRecordRed;

/// Size of the floating recorder bubble.
const kRecorderBubbleSize = Size(156, 50);

/// The call's own floating bubble (top right, see `call_overlay.dart`): the recorder bubble stays clear of it.
Rect callBubbleRect(Size screen, EdgeInsets pad) => Rect.fromLTWH(screen.width - 96 - 12, pad.top + 72, 96, 132);

/// Default place of the recorder bubble: right edge, a little below the middle — clear of app bars, tabs and
/// the call bubble (top right), and above bottom bars / chat inputs.
Offset defaultRecorderBubblePos(Size screen, EdgeInsets pad, {required bool callBubble}) {
  var top = pad.top + (screen.height - pad.top - pad.bottom) * 0.6;
  if (callBubble) top = max(top, callBubbleRect(screen, pad).bottom + 12);
  return Offset(screen.width - kRecorderBubbleSize.width - 12, top);
}

/// Keeps the bubble inside the safe area and off the call bubble.
Offset clampRecorderBubble(Offset p, Size screen, EdgeInsets pad, {required bool callBubble}) {
  const s = kRecorderBubbleSize;
  var out = Offset(p.dx.clamp(8.0, screen.width - s.width - 8), p.dy.clamp(pad.top + 8, screen.height - s.height - pad.bottom - 8));
  if (callBubble) {
    final call = callBubbleRect(screen, pad).inflate(6);
    if ((out & s).overlaps(call)) {
      // Move to whichever side of the call bubble is nearer (below, else above).
      final below = call.bottom;
      final above = call.top - s.height;
      final y = (out.dy - above).abs() < (out.dy - below).abs() && above >= pad.top + 8 ? above : below;
      out = Offset(out.dx, y.clamp(pad.top + 8, screen.height - s.height - pad.bottom - 8));
    }
  }
  return out;
}

/// Floating recorder over the whole app while a notebook recording runs and its screen is closed:
/// red dot + elapsed time + pause / resume; drag it anywhere, tap to open the recorder.
/// Also: the "สรุปเสร็จแล้ว" toast, the notification tap, and Android back on the first screen
/// (moves the app to the background instead of closing it, so the recording keeps going).
class NotebookRecorderOverlay extends StatefulWidget {
  const NotebookRecorderOverlay({super.key, required this.recorder, required this.navigatorKey, this.call, this.open, this.canPop});
  final NotebookRecorder recorder;
  final GlobalKey<NavigatorState> navigatorKey;
  final CallService? call;

  /// Opens an app location (the router's push); used by the "ดูสรุป" toast.
  final void Function(String location)? open;

  /// Whether the router can go back (Android back while recording).
  final bool Function()? canPop;

  @override
  State<NotebookRecorderOverlay> createState() => _NotebookRecorderOverlayState();
}

class _NotebookRecorderOverlayState extends State<NotebookRecorderOverlay> with WidgetsBindingObserver {
  static const _channel = MethodChannel('nextx/notebook_recorder');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.recorder.onOpenRequest = _expand;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.recorder.onOpenRequest == _expand) widget.recorder.onOpenRequest = null;
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    if (kIsWeb || !Platform.isAndroid || !widget.recorder.active) return false;
    if (widget.canPop?.call() ?? widget.navigatorKey.currentState?.canPop() ?? true) return false;
    try {
      return await _channel.invokeMethod<bool>('background') ?? false;
    } catch (_) {
      return false;
    }
  }

  void _expand() {
    final nav = widget.navigatorKey.currentState;
    if (nav == null || widget.recorder.screenOpen || !widget.recorder.active) return;
    HapticFeedback.selectionClick();
    nav.push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, _, _) => NotebookRecordScreen(recorder: widget.recorder),
        transitionsBuilder: (_, anim, _, child) {
          final a = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.recorder, ?call]),
      builder: (context, _) {
        final r = widget.recorder;
        final callBubble = call != null && call.minimized && (call.phase == CallPhase.active || call.phase == CallPhase.outgoing);
        final callFull = call != null && !call.minimized && (call.phase == CallPhase.active || call.phase == CallPhase.outgoing || call.incoming != null);
        return Stack(
          children: [
            if (r.active && !r.screenOpen && !callFull) NotebookRecorderBubble(recorder: r, callBubble: callBubble, onExpand: _expand),
            NotebookRecordingToast(recorder: r, open: widget.open),
          ],
        );
      },
    );
  }
}

class NotebookRecorderBubble extends StatefulWidget {
  const NotebookRecorderBubble({super.key, required this.recorder, required this.onExpand, this.callBubble = false});
  final NotebookRecorder recorder;
  final VoidCallback onExpand;
  final bool callBubble;

  @override
  State<NotebookRecorderBubble> createState() => _NotebookRecorderBubbleState();
}

class _NotebookRecorderBubbleState extends State<NotebookRecorderBubble> {
  Offset? _pos;
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
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final r = widget.recorder;
    const s = kRecorderBubbleSize;
    final pos = clampRecorderBubble(_pos ?? defaultRecorderBubblePos(size, pad, callBubble: widget.callBubble), size, pad, callBubble: widget.callBubble);
    final paused = r.paused;
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      width: s.width,
      height: s.height,
      child: GestureDetector(
        key: const ValueKey('notebook-recorder-bubble'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onExpand,
        onPanUpdate: (d) => setState(() => _pos = clampRecorderBubble((_pos ?? pos) + d.delta, size, pad, callBubble: widget.callBubble)),
        child: Semantics(
          button: true,
          label: tr('บันทึกเสียงในสมุดโน้ต — แตะเพื่อเปิด'),
          child: Material(
            elevation: 12,
            shadowColor: Colors.black54,
            color: const Color(0xF2111827),
            shape: StadiumBorder(
              side: BorderSide(color: (paused ? Colors.white : kRecordRed).withValues(alpha: paused ? 0.14 : 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 5, 0),
              child: Row(
                children: [
                  NotebookRecordDot(paused: paused, size: 10),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recordingClock(r.elapsed.inMilliseconds),
                          key: const ValueKey('notebook-recorder-bubble-time'),
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, height: 1.1, fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                        Text(
                          tr(paused ? 'หยุดชั่วคราว' : 'กำลังบันทึก'),
                          maxLines: 1,
                          style: TextStyle(color: paused ? Colors.white54 : const Color(0xFFFDA4AF), fontSize: 10.5, fontWeight: FontWeight.w700, height: 1.2),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: Material(
                      color: paused ? kRecordRed : Colors.white.withValues(alpha: 0.12),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: const ValueKey('notebook-recorder-bubble-toggle'),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          r.togglePause();
                        },
                        child: Icon(paused ? NxI.microphone : LucideIcons300.pause, size: 19, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "ไอแซคสรุปบันทึกเสียงเสร็จแล้ว" on any screen when `ai:notebook_recording_ready` arrives.
class NotebookRecordingToast extends StatelessWidget {
  const NotebookRecordingToast({super.key, required this.recorder, this.open});
  final NotebookRecorder recorder;
  final void Function(String location)? open;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: recorder.ready,
      builder: (context, ready, _) {
        if (ready == null) return const SizedBox.shrink();
        final nb = '${ready['notebook_id'] ?? ''}';
        final title = '${ready['title'] ?? ''}'.trim();
        return Positioned(
          left: 12,
          right: 12,
          bottom: MediaQuery.paddingOf(context).bottom + 76,
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                key: const ValueKey('notebook-recording-ready-toast'),
                elevation: 8,
                borderRadius: BorderRadius.circular(20),
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  child: Row(
                    children: [
                      const IsaacAvatar(mood: 'success', size: 42),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(tr('ไอแซคสรุปบันทึกเสียงเสร็จแล้ว'), style: const TextStyle(fontWeight: FontWeight.w700)),
                            if (title.isNotEmpty)
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                              ),
                          ],
                        ),
                      ),
                      if (nb.isNotEmpty && open != null)
                        TextButton(
                          key: const ValueKey('notebook-recording-ready-open'),
                          onPressed: () {
                            recorder.ready.value = null;
                            open!(notebookRecordingLocation(nb, recordingId: '${ready['recording_id'] ?? ''}', noteId: '${ready['note_id'] ?? ''}'));
                          },
                          child: Text(tr('ดูสรุป')),
                        ),
                      // No tooltip: this sits above the navigator's Overlay (a Tooltip needs one).
                      Semantics(
                        button: true,
                        label: tr('ปิด'),
                        child: IconButton(key: const ValueKey('notebook-recording-ready-close'), icon: const Icon(NxI.x, size: 18), onPressed: () => recorder.ready.value = null),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `/notebook/<id>?recording=<rid>&note=<nid>` — the notebook opens the recording's summary note.
String notebookRecordingLocation(String notebookId, {String? recordingId, String? noteId}) {
  final q = <String, String>{
    if (recordingId != null && recordingId.isNotEmpty && recordingId != 'null') 'recording': recordingId,
    if (noteId != null && noteId.isNotEmpty && noteId != 'null') 'note': noteId,
  };
  final base = AppRoutes.notebookOf(notebookId);
  return q.isEmpty ? base : '$base?${Uri(queryParameters: q).query}';
}

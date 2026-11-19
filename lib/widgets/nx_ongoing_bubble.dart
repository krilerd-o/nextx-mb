import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import 'nx_icons.dart';

/// Which ongoing sessions the user hid by dragging their bubble onto the × (they keep running and stay in
/// the device's notification bar; the small "กำลัง…" pill brings the bubble back).
class OngoingBubbles extends ChangeNotifier {
  OngoingBubbles._();
  static final OngoingBubbles instance = OngoingBubbles._();

  final Set<String> _hidden = {};
  bool isHidden(String kind) => _hidden.contains(kind);

  void hide(String kind) {
    if (_hidden.add(kind)) notifyListeners();
  }

  void show(String kind) {
    if (_hidden.remove(kind)) notifyListeners();
  }

  /// A session ended: next time it starts, its bubble shows again. Called while building: no notify.
  void forget(String kind) => _hidden.remove(kind);

  @visibleForTesting
  void reset() {
    _hidden.clear();
    notifyListeners();
  }
}

/// Size of the shared floating bubble.
const kOngoingBubbleSize = Size(168, 52);

/// Where the × drop zone sits (bottom centre, above the home indicator).
Rect ongoingDismissZone(Size screen, EdgeInsets pad) {
  const d = 72.0;
  return Rect.fromCenter(center: Offset(screen.width / 2, screen.height - pad.bottom - 64), width: d, height: d);
}

/// Bubble inside the safe area.
Offset clampOngoingBubble(Offset p, Size screen, EdgeInsets pad, {Size size = kOngoingBubbleSize}) =>
    Offset(p.dx.clamp(8.0, screen.width - size.width - 8), p.dy.clamp(pad.top + 8, screen.height - size.height - pad.bottom - 8));

/// After a drag: to the nearer side edge.
Offset snapOngoingBubble(Offset p, Size screen, EdgeInsets pad, {Size size = kOngoingBubbleSize}) {
  final c = clampOngoingBubble(p, screen, pad, size: size);
  final left = c.dx + size.width / 2 < screen.width / 2;
  return Offset(left ? 8 : screen.width - size.width - 8, c.dy);
}

/// A floating bubble for a call / meeting room / recording on every screen: drag anywhere (snaps to an
/// edge), tap to open, drop on the × at the bottom to hide it (the session keeps going).
/// Put it in a full-screen [Stack]; empty areas pass touches through.
class NxOngoingBubble extends StatefulWidget {
  const NxOngoingBubble({
    super.key,
    required this.kind,
    required this.child,
    required this.onTap,
    this.size = kOngoingBubbleSize,
    this.initial,
    this.semanticsLabel = '',
    this.accent = const Color(0xFF6366F1),
    this.onHidden,
    this.gestureKey,
  });

  /// Key of the tappable area (tests); default `ongoing-bubble-<kind>`.
  final Key? gestureKey;

  /// call | room | minute_recording | notebook_recording
  final String kind;
  final Widget child;
  final VoidCallback onTap;
  final Size size;
  final Offset Function(Size screen, EdgeInsets pad)? initial;
  final String semanticsLabel;
  final Color accent;

  /// After it was dropped on the × (e.g. a "ยังทำงานอยู่ในแถบแจ้งเตือน" hint).
  final VoidCallback? onHidden;

  @override
  State<NxOngoingBubble> createState() => _NxOngoingBubbleState();
}

class _NxOngoingBubbleState extends State<NxOngoingBubble> {
  Offset? _pos;
  bool _dragging = false;
  bool _overX = false;

  Offset _default(Size size, EdgeInsets pad) =>
      widget.initial?.call(size, pad) ?? Offset(size.width - widget.size.width - 12, pad.top + (size.height - pad.top - pad.bottom) * 0.6);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final pos = clampOngoingBubble(_pos ?? _default(screen, pad), screen, pad, size: widget.size);
    final zone = ongoingDismissZone(screen, pad);
    return Stack(
      children: [
        if (_dragging)
          Positioned.fromRect(
            key: const ValueKey('zone'),
            rect: zone,
            child: IgnorePointer(
              child: AnimatedScale(
                key: const ValueKey('ongoing-dismiss-zone'),
                scale: _overX ? 1.18 : 1,
                duration: const Duration(milliseconds: 140),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (_overX ? const Color(0xFFDC2626) : Colors.black).withValues(alpha: _overX ? 0.92 : 0.55),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
                  ),
                  child: const Center(child: Icon(NxI.x, color: Colors.white, size: 28)),
                ),
              ),
            ),
          ),
        AnimatedPositioned(
          // Keyed: the × zone appearing mid-drag must not rebuild the bubble (it would drop the gesture).
          key: const ValueKey('bubble'),
          duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: pos.dx,
          top: pos.dy,
          width: widget.size.width,
          height: widget.size.height,
          child: GestureDetector(
            key: widget.gestureKey ?? ValueKey('ongoing-bubble-${widget.kind}'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onTap();
            },
            onPanStart: (_) => setState(() => _dragging = true),
            onPanUpdate: (d) {
              final next = clampOngoingBubble((_pos ?? pos) + d.delta, screen, pad, size: widget.size);
              final over = (next & widget.size).overlaps(zone.inflate(8));
              if (over != _overX) HapticFeedback.selectionClick();
              setState(() {
                _pos = next;
                _overX = over;
              });
            },
            onPanEnd: (_) {
              if (_overX) {
                HapticFeedback.mediumImpact();
                setState(() {
                  _dragging = false;
                  _overX = false;
                  _pos = null;
                });
                OngoingBubbles.instance.hide(widget.kind);
                widget.onHidden?.call();
                return;
              }
              setState(() {
                _dragging = false;
                _pos = snapOngoingBubble(_pos ?? pos, screen, pad, size: widget.size);
              });
            },
            child: Semantics(
              button: true,
              label: widget.semanticsLabel,
              child: AnimatedOpacity(
                opacity: _overX ? 0.55 : 1,
                duration: const Duration(milliseconds: 120),
                child: widget.child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dark pill content used by the room / recorder bubbles: a leading badge, a title + a status line, one action.
class NxOngoingPill extends StatelessWidget {
  const NxOngoingPill({super.key, required this.leading, required this.title, required this.subtitle, this.action, this.border = const Color(0x66FFFFFF)});
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? action;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      shadowColor: Colors.black54,
      color: const Color(0xF2111827),
      shape: StadiumBorder(side: BorderSide(color: border)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, height: 1.1, fontFeatures: [FontFeature.tabularFigures()])),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 10.5, fontWeight: FontWeight.w600, height: 1.25)),
                ],
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// Round button inside a pill (mute / pause).
class NxOngoingPillButton extends StatelessWidget {
  const NxOngoingPillButton({super.key, required this.icon, required this.onTap, this.active = false, this.color = const Color(0xFFDC2626)});
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 38,
        height: 38,
        child: Material(
          color: active ? color : Colors.white.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      );
}

/// Small pill at the top while a hidden session keeps running: tap to bring its bubble back.
class NxOngoingRestorePill extends StatelessWidget {
  const NxOngoingRestorePill({super.key, required this.kind, required this.label, this.color = const Color(0xFFDC2626)});
  final String kind;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Positioned(
      top: pad.top + 4,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          key: ValueKey('ongoing-restore-$kind'),
          color: const Color(0xE6111827),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => OngoingBubbles.instance.show(kind),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 7),
                  Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Text(tr('แสดง'), style: const TextStyle(color: Color(0xFFA5B4FC), fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

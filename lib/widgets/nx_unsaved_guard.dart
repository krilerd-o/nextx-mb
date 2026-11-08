import 'package:flutter/material.dart';

import '../core/i18n.dart';

/// Asks before back / swipe / the header arrow throws away typed data.
///
/// [snapshot] returns the form's current values as text. The baseline is
/// taken at the user's first touch inside the form (after loading and
/// defaults), so only the user's own edits count. Saving with
/// `Navigator.pop(context, result)` is never blocked.
class NxUnsavedGuard extends StatefulWidget {
  const NxUnsavedGuard({super.key, required this.snapshot, required this.child, this.enabled = true});

  final String Function() snapshot;
  final Widget child;
  final bool enabled;

  @override
  State<NxUnsavedGuard> createState() => _NxUnsavedGuardState();
}

class _NxUnsavedGuardState extends State<NxUnsavedGuard> {
  String? _baseline;
  bool _asking = false;

  bool get _dirty {
    if (_baseline == null) return false;
    try {
      return widget.snapshot() != _baseline;
    } catch (_) {
      return false;
    }
  }

  void _touch() {
    if (_baseline != null || !widget.enabled) return;
    try {
      // canPop flips to false so the next back comes to us.
      setState(() => _baseline = widget.snapshot());
    } catch (_) {}
  }

  Future<void> _onBack() async {
    if (_asking) return;
    final nav = Navigator.of(context);
    if (!_dirty) {
      nav.pop();
      return;
    }
    _asking = true;
    final leave = await confirmNxDiscard(context);
    _asking = false;
    if (leave && mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.enabled || _baseline == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _touch(),
        child: widget.child,
      ),
    );
  }
}

/// "Discard changes?" — true when the user chooses to leave.
Future<bool> confirmNxDiscard(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('nx-discard-dialog'),
      title: Text(tr('ทิ้งข้อมูลที่กรอกไว้?')),
      content: Text(tr('ยังไม่ได้บันทึก ถ้าออกตอนนี้ข้อมูลที่กรอกจะหายไป')),
      actions: [
        TextButton(key: const ValueKey('nx-discard-stay'), onPressed: () => Navigator.pop(ctx, false), child: Text(tr('กรอกต่อ'))),
        FilledButton(
          key: const ValueKey('nx-discard-leave'),
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error, foregroundColor: Theme.of(ctx).colorScheme.onError),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('ทิ้งและออก')),
        ),
      ],
    ),
  );
  return ok == true;
}

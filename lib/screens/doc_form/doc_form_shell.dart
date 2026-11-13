import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/thai_time.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/fields/nx_entity_form.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_shake.dart';
import '../../widgets/nx_skeleton.dart';

/// One step of a step form.
class DocStepInfo {
  const DocStepInfo(this.title, this.icon);
  final String title;
  final IconData icon;
}

/// Frame of the quotation / job step forms: header, step chips (red count =
/// required fields still missing on that step), the current step, and a
/// sticky bottom bar (live summary + back / next / finish). On a tablet the
/// [side] panel (summary / preview) sits next to the step.
class DocStepShell extends StatelessWidget {
  const DocStepShell({
    super.key,
    required this.title,
    required this.steps,
    required this.current,
    required this.missing,
    required this.canOpen,
    required this.onStep,
    required this.body,
    this.complete,
    required this.bottom,
    this.subtitle,
    this.banners = const [],
    this.side,
    this.loading = false,
    this.embedded = false,
    this.onClose,
    this.actions,
  });

  final String title;
  final String? subtitle;
  final List<DocStepInfo> steps;
  final int current;
  final List<int> missing;

  /// Steps done (a check instead of the number); null = never shown.
  final List<bool>? complete;
  final bool Function(int step) canOpen;
  final ValueChanged<int> onStep;
  final List<Widget> banners;
  final Widget body;
  final Widget bottom;
  final Widget? side;
  final bool loading;
  final bool embedded;
  final VoidCallback? onClose;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final bp = NxBreakpoint.of(context);
    final wide = bp.twoPane && MediaQuery.sizeOf(context).width >= 900 && side != null;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: NxAppHeader(
        title: title,
        subtitle: subtitle,
        actions: actions,
        automaticallyImplyLeading: !embedded,
        leading: embedded || onClose != null
            ? IconButton(key: const ValueKey('docform-close'), tooltip: tr('ปิด'), onPressed: onClose, icon: const Icon(NxI.x))
            : null,
      ),
      body: loading
          ? const NxSkeletonForm()
          : Column(
              children: [
                _StepChips(steps: steps, current: current, missing: missing, complete: complete, canOpen: canOpen, onStep: onStep),
                ...banners,
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: body),
                            SizedBox(
                              width: 360,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border(left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5))),
                                ),
                                child: KeyedSubtree(key: const ValueKey('docform-side'), child: side!),
                              ),
                            ),
                          ],
                        )
                      : NxContentWidth(child: body),
                ),
                bottom,
              ],
            ),
    );
  }
}

/// Steps as a compact stepper that always fits the width: a circle per step
/// (its icon · green check when done · filled when current) joined by a
/// line, the title under it, and a small amber dot with the count of
/// required fields still missing (tooltip "ยังขาด N ช่อง").
class _StepChips extends StatelessWidget {
  const _StepChips({required this.steps, required this.current, required this.missing, required this.canOpen, required this.onStep, this.complete});
  final List<DocStepInfo> steps;
  final int current;
  final List<int> missing;
  final List<bool>? complete;
  final bool Function(int) canOpen;
  final ValueChanged<int> onStep;

  static const _warn = Color(0xFFF59E0B);
  static const _done = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget line(bool on, bool show) => Expanded(
          child: show
              ? Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: on ? cs.primary.withValues(alpha: 0.7) : cs.outlineVariant.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(1),
                  ),
                )
              : const SizedBox.shrink(),
        );
    return Padding(
      key: const ValueKey('docform-steps'),
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
            child: () {
              final on = i == current;
              final miss = i < missing.length ? missing[i] : 0;
              final done = !on && miss == 0 && complete != null && i < complete!.length && complete![i];
              final open = canOpen(i);
              final Color fill = on ? cs.primary : (done ? _done : cs.surfaceContainerHighest);
              final Color fg = on ? cs.onPrimary : (done ? Colors.white : (open ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.55)));
              final circle = Container(
                key: done ? ValueKey('docform-step-done-$i') : null,
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  border: on ? Border.all(color: cs.primary.withValues(alpha: 0.35), width: 4, strokeAlign: BorderSide.strokeAlignOutside) : null,
                ),
                child: done ? const Icon(NxI.check, size: 16, color: Colors.white) : Icon(steps[i].icon, size: 15, color: fg),
              );
              return Semantics(
                container: true,
                selected: on,
                button: open && !on,
                label: '${i + 1}. ${tr(steps[i].title)}',
                hint: miss > 0 ? tr('ยังขาด $miss ช่อง') : (done ? tr('ครบแล้ว') : null),
                child: InkWell(
                  key: ValueKey('docform-step-$i'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: open && !on ? () => onStep(i) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        height: 34,
                        child: Row(children: [
                          line(i <= current, i > 0),
                          Stack(clipBehavior: Clip.none, children: [
                            circle,
                            if (miss > 0)
                              Positioned(
                                top: -4,
                                right: -7,
                                child: Tooltip(
                                  message: tr('ยังขาด $miss ช่อง'),
                                  child: Container(
                                    key: ValueKey('docform-step-warn-$i'),
                                    constraints: const BoxConstraints(minWidth: 17),
                                    height: 17,
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: _warn,
                                      borderRadius: BorderRadius.circular(9),
                                      border: Border.all(color: theme.scaffoldBackgroundColor, width: 1.5),
                                    ),
                                    child: Text(
                                      '$miss',
                                      key: ValueKey('docform-step-missing-$i'),
                                      textScaler: TextScaler.noScaling,
                                      style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800, height: 1.1),
                                    ),
                                  ),
                                ),
                              ),
                          ]),
                          line(i < current, i < steps.length - 1),
                        ]),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          tr(steps[i].title),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            height: 1.2,
                            fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                            color: on ? cs.primary : (open ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.6)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              );
            }(),
          ),
      ]),
    );
  }
}

/// Card around a group of fields (same look as the generic form's sections).
class DocSectionCard extends StatelessWidget {
  const DocSectionCard({super.key, required this.title, required this.icon, required this.child, this.color, this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? color;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final tint = color ?? cs.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      // A Material (not a coloured box) so list tiles / chips inside show their ink.
      child: Material(
        color: dark ? cs.surfaceContainerHigh : cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35))),
        clipBehavior: Clip.antiAlias,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: tint.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, size: 18, color: tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  if (subtitle != null) Text(tr(subtitle!), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
              ?trailing,
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(14, 4, 14, 14), child: child),
        ],
        ),
      ),
    );
  }
}

/// Scroll + shake targets for fields the step screens draw themselves.
class DocFieldAnchors {
  final _keys = <String, GlobalKey>{};
  final _shakers = <String, GlobalKey<NxShakeState>>{};

  /// Extra-field lists per group, so their own fields can be revealed too.
  final forms = <String, GlobalKey<NxEntityFormState>>{};

  GlobalKey<NxEntityFormState> formKey(String group) => forms.putIfAbsent(group, GlobalKey<NxEntityFormState>.new);

  Widget wrap(String name, Widget child) => NxShake(
        key: _shakers.putIfAbsent(name, GlobalKey<NxShakeState>.new),
        child: KeyedSubtree(key: _keys.putIfAbsent(name, GlobalKey.new), child: child),
      );

  /// Scroll to [name] and shake every name in [all]. False when not on screen.
  Future<bool> reveal(String name, Iterable<String> all) async {
    final ctx = _keys[name]?.currentContext;
    if (ctx == null) {
      for (final f in forms.values) {
        final st = f.currentState;
        if (st != null && st.widget.fields.any((x) => '${x['name'] ?? x['key']}' == name)) {
          await st.revealErrors(name, all);
          return true;
        }
      }
      return false;
    }
    await Scrollable.ensureVisible(ctx, alignment: 0.15, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    var haptic = true;
    for (final n in all) {
      _shakers[n]?.currentState?.shake(haptic: haptic);
      haptic = false;
    }
    for (final f in forms.values) {
      final st = f.currentState;
      if (st == null) continue;
      final mine = [for (final n in all) if (st.widget.fields.any((x) => '${x['name'] ?? x['key']}' == n)) n];
      if (mine.isNotEmpty) st.revealErrors(mine.first, mine);
    }
    return true;
  }
}

/// Sticky bottom bar: summary on the left, actions on the right.
class DocBottomBar extends StatelessWidget {
  const DocBottomBar({super.key, required this.summary, required this.actions, this.secondary});
  final Widget summary;
  final List<Widget> actions;

  /// Optional row of secondary actions above [actions] (each sized by the caller).
  final List<Widget>? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pad = NxBreakpoint.of(context).pagePadding;
    return Material(
      color: theme.brightness == Brightness.dark ? cs.surfaceContainer : cs.surface,
      elevation: 8,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, 10, pad, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyedSubtree(key: const ValueKey('docform-summary'), child: summary),
              const SizedBox(height: 10),
              if (secondary != null && secondary!.isNotEmpty) ...[
                Row(children: [
                  for (var i = 0; i < secondary!.length; i++) ...[if (i > 0) const SizedBox(width: 8), secondary![i]],
                ]),
                const SizedBox(height: 8),
              ],
              Row(children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  i == actions.length - 1 ? Expanded(child: actions[i]) : actions[i],
                ],
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// "ทำต่อจากร่าง" (true) / "เริ่มใหม่" (false) / dismissed (null).
Future<bool?> askResumeDraft(BuildContext context, {required DateTime savedAt, String? what}) {
  final t = toThai(savedAt);
  String two(int n) => n.toString().padLeft(2, '0');
  final when = '${t.day}/${t.month}/${uiYear(t.year)} ${two(t.hour)}:${two(t.minute)}';
  return showAppBottomSheet<bool>(
    context: context,
    title: tr('มีร่างที่ยังไม่บันทึก'),
    child: Builder(builder: (ctx) {
      final theme = Theme.of(ctx);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('${what ?? 'ฟอร์มนี้'} มีข้อมูลที่กรอกค้างไว้เมื่อ $when'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              key: const ValueKey('docform-draft-resume'),
              onPressed: () {
                HapticFeedback.selectionClick();
                Navigator.pop(ctx, true);
              },
              icon: const Icon(NxI.pencilSimple, size: 18),
              label: Text(tr('ทำต่อจากร่าง')),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              key: const ValueKey('docform-draft-discard'),
              onPressed: () => Navigator.pop(ctx, false),
              icon: const Icon(NxI.arrowCounterClockwise, size: 18),
              label: Text(tr('เริ่มใหม่')),
            ),
          ),
        ],
      );
    }),
  );
}

/// Notice strip under the step chips (revise banner, locked record …).
class DocBanner extends StatelessWidget {
  const DocBanner({super.key, required this.text, this.icon = NxI.info, this.color, this.child, this.title});
  final String? title;
  final String text;
  final IconData icon;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: tint)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (title != null) Text(tr(title!), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: tint)),
              Text(tr(text), style: theme.textTheme.bodySmall),
            ]),
          ),
        ]),
        ?child,
      ]),
    );
  }
}

/// Small label/value row in review cards.
class DocKeyValue extends StatelessWidget {
  const DocKeyValue(this.label, this.value, {super.key, this.strong = false, this.valueKey});
  final String label;
  final String value;
  final bool strong;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: LayoutBuilder(builder: (context, c) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // The label keeps its own width (at most ~45 %); the value takes the rest.
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: c.maxWidth * 0.45),
          child: Text(tr(label), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(width: 12),
        // The value hugs the right edge (amounts line up under each other).
        Expanded(
          child: Align(
            alignment: Alignment.topRight,
            child: Text(
              value.isEmpty ? '—' : value,
              key: valueKey,
              textAlign: TextAlign.right,
              style: (strong ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)?.copyWith(fontWeight: strong ? FontWeight.w900 : FontWeight.w600),
            ),
          ),
        ),
      ])),
    );
  }
}

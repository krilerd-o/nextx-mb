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
                _StepChips(steps: steps, current: current, missing: missing, canOpen: canOpen, onStep: onStep),
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

class _StepChips extends StatefulWidget {
  const _StepChips({required this.steps, required this.current, required this.missing, required this.canOpen, required this.onStep});
  final List<DocStepInfo> steps;
  final int current;
  final List<int> missing;
  final bool Function(int) canOpen;
  final ValueChanged<int> onStep;

  @override
  State<_StepChips> createState() => _StepChipsState();
}

class _StepChipsState extends State<_StepChips> {
  final _chipKeys = <int, GlobalKey>{};

  @override
  void didUpdateWidget(covariant _StepChips old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) {
      // Keep the current step in view on a narrow phone.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _chipKeys[widget.current]?.currentContext;
        if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 250));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps, current = widget.current, missing = widget.missing, canOpen = widget.canOpen, onStep = widget.onStep;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SingleChildScrollView(
      key: const ValueKey('docform-steps'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) Container(width: 14, height: 1.5, color: cs.outlineVariant),
          () {
            final on = i == current;
            final miss = i < missing.length ? missing[i] : 0;
            final open = canOpen(i);
            final fg = on ? cs.onPrimary : (open ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.6));
            return Semantics(
              key: _chipKeys.putIfAbsent(i, GlobalKey.new),
              container: true,
              selected: on,
              hint: miss > 0 ? tr('ยังขาด $miss ช่อง') : null,
              child: Material(
                color: on ? cs.primary : cs.surfaceContainerHighest.withValues(alpha: open ? 0.7 : 0.35),
                shape: StadiumBorder(side: BorderSide(color: miss > 0 && !on ? cs.error.withValues(alpha: 0.6) : Colors.transparent)),
                child: InkWell(
                  key: ValueKey('docform-step-$i'),
                  customBorder: const StadiumBorder(),
                  onTap: open && !on ? () => onStep(i) : null,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: miss > 0 ? cs.error : (on ? cs.onPrimary.withValues(alpha: 0.2) : cs.surface),
                          shape: BoxShape.circle,
                        ),
                        child: miss > 0
                            ? Text('$miss', key: ValueKey('docform-step-missing-$i'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onError, fontWeight: FontWeight.w800))
                            : Text('${i + 1}', style: theme.textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 6),
                      Icon(steps[i].icon, size: 15, color: fg),
                      const SizedBox(width: 4),
                      Text(tr(steps[i].title), style: theme.textTheme.labelLarge?.copyWith(color: fg, fontWeight: on ? FontWeight.w800 : FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
            );
          }(),
        ],
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
  const DocBottomBar({super.key, required this.summary, required this.actions});
  final Widget summary;
  final List<Widget> actions;

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
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(tr(label), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value.isEmpty ? '—' : value,
            key: valueKey,
            textAlign: TextAlign.right,
            style: (strong ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)?.copyWith(fontWeight: strong ? FontWeight.w900 : FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

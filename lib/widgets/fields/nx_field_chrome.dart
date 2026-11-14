import 'package:flutter/material.dart';

import 'field_ui_type.dart';
import '../nx_icons.dart';
import '../../core/i18n.dart';

/// Outlined field chrome — radius 14, light resting label, float on focus/value.
class NxFieldStyle {
  NxFieldStyle._();

  static const double radius = 14;
  static const double controlHeight = 52;

  static InputBorder border(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static BoxDecoration box(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: scheme.outline.withValues(alpha: 0.85)),
    );
  }

  static const double lineHeight = 24;

  /// Height of one line of text inside a single-line [TextField] (what
  /// `RenderEditable` sizes itself to). Tap fields (picklist, date, user, …)
  /// use it for their content so they come out exactly as tall as the text
  /// inputs next to them, whatever the font / text scale.
  static double inputLineHeight(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge ?? const TextStyle(fontSize: 16);
    final tp = TextPainter(
      text: TextSpan(text: ' ', style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final h = tp.preferredLineHeight;
    tp.dispose();
    return h;
  }

  /// Resting outline colour of every input box.
  static Color idleColor(ColorScheme scheme) => scheme.outline.withValues(alpha: 0.55);
  static Color disabledColor(ColorScheme scheme) => scheme.outline.withValues(alpha: 0.4);

  /// Icon slots are one text line tall, so a field with an icon is exactly
  /// as tall as one without.
  static const BoxConstraints iconSlotConstraints = BoxConstraints(minWidth: 36, minHeight: 22, maxHeight: 22);

  static EdgeInsets padding({bool multiline = false}) => EdgeInsets.fromLTRB(16, multiline ? 16 : 15, 12, multiline ? 16 : 15);

  static TextStyle floatingStyle(ColorScheme scheme) => TextStyle(
        color: scheme.primary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      );

  /// App-wide default ([ThemeData.inputDecorationTheme]): a plain
  /// `TextField(decoration: InputDecoration(labelText: ...))` anywhere in the
  /// app gets the same outlined box as the Lead / entity forms — radius 14,
  /// hairline outline, primary-colour border on focus, label floating on the
  /// border. Search bars / chat composers that want another look set their
  /// own borders explicitly.
  static InputDecorationTheme theme(ColorScheme scheme, {String? fontFamily, List<String>? fontFamilyFallback}) {
    TextStyle font(TextStyle s) => s.copyWith(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback);
    return InputDecorationTheme(
      filled: false,
      isDense: true,
      contentPadding: padding(),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      border: border(idleColor(scheme)),
      enabledBorder: border(idleColor(scheme)),
      focusedBorder: border(scheme.primary, width: 1.5),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, width: 1.4),
      disabledBorder: border(disabledColor(scheme)),
      hintStyle: font(restingStyle(scheme)),
      labelStyle: font(restingStyle(scheme)),
      floatingLabelStyle: font(floatingStyle(scheme)),
      helperMaxLines: 3,
      errorMaxLines: 3,
    );
  }

  /// THE input decoration for any form field outside the entity forms
  /// (profile, password, OTP, sheets, dialogs …) — same box, label, icon
  /// slots and height as the Lead form. Use with a plain
  /// `TextField` / `TextFormField`; validators, controllers and keys stay
  /// on the field.
  ///
  /// * [label] floats onto the border on focus / value; [required] adds a
  ///   red " *" and makes the resting label bold (like the entity form).
  /// * [icon] / [prefixIcon] — leading icon inside the box.
  /// * [suffix] — trailing action ([NxFieldAction], a short [Text] such as
  ///   "เปลี่ยน", a password eye toggle …) kept one line tall.
  /// * [multiline] — label stays at the top of a tall box.
  /// * [counter] false hides the maxLength counter (OTP / code inputs).
  static InputDecoration input(
    BuildContext context, {
    String? label,
    bool required = false,
    IconData? icon,
    Widget? prefixIcon,
    Widget? suffix,
    String? hint,
    String? helper,
    String? prefixText,
    String? suffixText,
    String? errorText,
    bool multiline = false,
    bool counter = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final hasLabel = label != null && label.isNotEmpty;
    final lead = prefixIcon ?? (icon == null ? null : Icon(icon));
    return InputDecoration(
      label: hasLabel
          ? Text.rich(TextSpan(text: tr(label), children: [if (required) requiredMark(scheme)]))
          : null,
      labelStyle: required
          ? restingStyle(scheme).copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface)
          : restingStyle(scheme),
      floatingLabelStyle: floatingStyle(scheme),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      alignLabelWithHint: multiline,
      filled: false,
      hintText: trn(hint),
      hintStyle: restingStyle(scheme),
      helperText: trn(helper),
      helperMaxLines: 3,
      errorText: trn(errorText),
      errorMaxLines: 3,
      prefixText: prefixText,
      suffixText: suffixText,
      counterText: counter ? null : '',
      prefixIcon: _iconSlot(lead),
      suffixIcon: _iconSlot(suffix),
      isDense: true,
      suffixIconConstraints: iconSlotConstraints,
      prefixIconConstraints: iconSlotConstraints,
      contentPadding: padding(multiline: multiline),
      border: border(idleColor(scheme)),
      enabledBorder: border(idleColor(scheme)),
      focusedBorder: border(scheme.primary, width: 1.5),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, width: 1.4),
      disabledBorder: border(disabledColor(scheme)),
    );
  }

  static TextStyle restingStyle(ColorScheme scheme) => TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.2,
      );

  static InputDecoration decoration(
    BuildContext context, {
    String? label,
    bool required = false,
    String? hint,
    Widget? suffixIcon,
    Widget? prefixIcon,
    String? errorText,
    int? maxLines,
    bool floatLabel = false,
    bool skipRestingHint = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final hasLabel = label != null && label.isNotEmpty;
    final restInside = hasLabel && !floatLabel && !skipRestingHint;
    final floatingLabel = hasLabel && floatLabel
        ? Text.rich(
            TextSpan(
              text: trn(label),
              children: [if (required) requiredMark(scheme, fontSize: 12)],
            ),
          )
        : null;
    final tall = (maxLines ?? 1) > 1;
    return InputDecoration(
      label: floatingLabel,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      floatingLabelAlignment: FloatingLabelAlignment.start,
      floatingLabelStyle: floatingStyle(scheme),
      alignLabelWithHint: tall,
      filled: false,
      // Resting label: bold with a red * while a required field is still empty.
      hint: restInside ? restingLabel(scheme, label, required: required) : null,
      hintText: restInside ? null : trn(hasLabel ? null : hint),
      hintStyle: restingStyle(scheme),
      errorText: trn(errorText),
      suffixIcon: _iconSlot(suffixIcon),
      prefixIcon: _iconSlot(prefixIcon),
      isDense: true,
      suffixIconConstraints: iconSlotConstraints,
      prefixIconConstraints: iconSlotConstraints,
      contentPadding: padding(multiline: tall),
      border: border(idleColor(scheme)),
      enabledBorder: border(idleColor(scheme)),
      focusedBorder: border(scheme.primary, width: 1.5),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, width: 1.4),
      disabledBorder: border(disabledColor(scheme)),
    );
  }

  /// The red " *" after a required field's label.
  static TextSpan requiredMark(ColorScheme scheme, {double? fontSize}) => TextSpan(
        text: ' *',
        style: TextStyle(color: scheme.error, fontWeight: FontWeight.w700, fontSize: fontSize),
      );

  /// Label shown inside an empty field. Required ones are bold + red *.
  static Widget restingLabel(ColorScheme scheme, String label, {required bool required}) => Text.rich(
        TextSpan(
          text: tr(label),
          style: restingStyle(scheme).copyWith(
            fontWeight: required ? FontWeight.w700 : FontWeight.w400,
            color: required ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
          children: [if (required) requiredMark(scheme)],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  static Widget? _iconSlot(Widget? icon) {
    if (icon == null) return null;
    return IconTheme.merge(
      data: const IconThemeData(size: 20),
      child: Align(widthFactor: 1, alignment: Alignment.center, child: icon),
    );
  }
}

IconData nxTypeIcon(IconDataSpec spec) {
  switch (spec) {
    case IconDataSpec.email:
      return NxI.envelope;
    case IconDataSpec.phone:
      return NxI.phone;
    case IconDataSpec.link:
      return NxI.arrowSquareOut;
    case IconDataSpec.calendar:
      return NxI.calendarBlank;
    case IconDataSpec.time:
      return NxI.clock;
    case IconDataSpec.chevron:
      return NxI.caretDown;
    case IconDataSpec.pin:
      return NxI.mapPin;
    case IconDataSpec.clip:
      return NxI.paperclip;
    case IconDataSpec.none:
      return NxI.note;
  }
}

/// Tap target that looks like an outlined TextField with a floating label.
class NxOutlinedTapField extends StatelessWidget {
  const NxOutlinedTapField({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.isEmpty = true,
    this.enabled = true,
    this.errorText,
    this.suffixIcon,
    this.prefixIcon,
    this.onTap,
    this.multiLine = false,
    this.hint,
  });

  final String label;
  final Widget child;
  final bool required;
  final bool isEmpty;
  final bool enabled;
  final String? errorText;
  final Widget? suffixIcon;

  /// Field type icon — always on the left, like the text inputs.
  final Widget? prefixIcon;
  final VoidCallback? onTap;

  /// Content may wrap onto more lines (chips). Otherwise the content box is
  /// exactly one text-input line tall, so the field matches a text input.
  final bool multiLine;

  /// Shown inside an empty field (the label then sits on the border), e.g.
  /// "แตะเพื่อเลือกจังหวัด".
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = NxFieldStyle.inputLineHeight(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(NxFieldStyle.radius),
      child: InputDecorator(
        isEmpty: false,
        decoration: NxFieldStyle.decoration(
          context,
          label: label,
          required: required,
          errorText: trn(errorText),
          suffixIcon: suffixIcon,
          prefixIcon: prefixIcon,
          floatLabel: !isEmpty || hint != null,
          skipRestingHint: true,
        ),
        child: isEmpty
            ? SizedBox(
                height: line,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: hint != null
                      ? Text(
                          tr(hint!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NxFieldStyle.restingStyle(scheme).copyWith(color: scheme.onSurfaceVariant.withValues(alpha: enabled ? 1 : 0.6)),
                        )
                      : NxFieldStyle.restingLabel(scheme, label, required: required),
                ),
              )
            : multiLine
                ? ConstrainedBox(
                    constraints: BoxConstraints(minHeight: line),
                    child: Align(alignment: Alignment.centerLeft, heightFactor: 1, child: child),
                  )
                : SizedBox(
                    height: line,
                    child: Align(alignment: Alignment.centerLeft, child: child),
                  ),
      ),
    );
  }
}

/// Small "clear value" button that fits in a field's suffix slot (no extra
/// height — a full IconButton would make the field taller than a text input).
class NxFieldClearButton extends StatelessWidget {
  const NxFieldClearButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tr('ล้างค่า'),
      child: InkResponse(
        onTap: onPressed,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(NxI.x, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Small icon action for a field's icon slot (edit, show/hide password …):
/// keeps the field one line tall, unlike a full [IconButton].
class NxFieldAction extends StatelessWidget {
  const NxFieldAction({super.key, required this.icon, required this.tooltip, this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tr(tooltip),
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: tr(tooltip),
        child: InkResponse(
          onTap: onPressed,
          radius: 20,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(icon, size: 20, color: onPressed == null ? cs.onSurfaceVariant.withValues(alpha: 0.5) : cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Show / hide toggle for a password field's suffix.
class NxPasswordToggle extends StatelessWidget {
  const NxPasswordToggle({super.key, required this.obscured, required this.onToggle});
  final bool obscured;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => NxFieldAction(
        icon: obscured ? NxI.eye : NxI.eyeSlash,
        tooltip: obscured ? 'แสดงรหัสผ่าน' : 'ซ่อนรหัสผ่าน',
        onPressed: onToggle,
      );
}

/// Short text action in a field's trailing slot, e.g. "เปลี่ยน".
class NxFieldTextAction extends StatelessWidget {
  const NxFieldTextAction(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 4),
      child: Text(tr(text), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 14)),
    );
  }
}

/// Suffix for a tap field: optional clear button + the caret.
Widget nxTapFieldSuffix(BuildContext context, {VoidCallback? onClear}) {
  final caret = Icon(NxI.caretDown, color: Theme.of(context).colorScheme.onSurfaceVariant);
  if (onClear == null) return caret;
  return Row(mainAxisSize: MainAxisSize.min, children: [NxFieldClearButton(onPressed: onClear), caret]);
}

class NxDashedDropzone extends StatelessWidget {
  const NxDashedDropzone({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.child,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(NxFieldStyle.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NxFieldStyle.radius),
        child: CustomPaint(
          painter: _DashBorderPainter(color: scheme.outline.withValues(alpha: 0.7)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: child ??
                Row(
                  children: [
                    Icon(icon, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr(label),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
          ),
        ),
      ),
    );
  }
}

class _DashBorderPainter extends CustomPainter {
  _DashBorderPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(NxFieldStyle.radius),
    );
    const dash = 6.0;
    const gap = 4.0;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final next = (dist + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashBorderPainter oldDelegate) => oldDelegate.color != color;
}

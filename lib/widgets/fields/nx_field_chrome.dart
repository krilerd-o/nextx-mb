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

  static const double lineHeight = 22;

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
      floatingLabelStyle: TextStyle(
        color: scheme.primary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
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
      suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 22, maxHeight: 22),
      prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 22, maxHeight: 22),
      contentPadding: EdgeInsets.fromLTRB(16, tall ? 16 : 15, 12, tall ? 16 : 15),
      border: border(scheme.outline.withValues(alpha: 0.55)),
      enabledBorder: border(scheme.outline.withValues(alpha: 0.55)),
      focusedBorder: border(scheme.primary, width: 1.5),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, width: 1.4),
      disabledBorder: border(scheme.outline.withValues(alpha: 0.4)),
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
    this.onTap,
  });

  final String label;
  final Widget child;
  final bool required;
  final bool isEmpty;
  final bool enabled;
  final String? errorText;
  final Widget? suffixIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
          floatLabel: !isEmpty,
          skipRestingHint: true,
        ),
        child: isEmpty
            ? SizedBox(
                height: NxFieldStyle.lineHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: NxFieldStyle.restingLabel(scheme, label, required: required),
                ),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(minHeight: NxFieldStyle.lineHeight),
                child: Align(
                  alignment: Alignment.centerLeft,
                  heightFactor: 1,
                  child: child,
                ),
              ),
      ),
    );
  }
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

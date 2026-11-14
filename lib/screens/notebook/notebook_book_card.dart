import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';

import '../../core/i18n.dart';
import '../../core/notebook/notebook_models.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_sliding_segmented.dart';

/// Library cards for the ISAAC notebook home: a book with a coloured spine and a
/// bookmark ribbon ("สมุด"), a modern gradient top ("ไล่สี") or a plain card
/// ("เรียบ"), in the notebook's colour + icon. Same look in the appearance picker.

const _kCardRadius = 20.0;

Color _cardColor(bool dark) => dark ? const Color(0xFF1C1D26) : Colors.white;

/// Darker / lighter shade of [c] for spines and gradients.
Color _shade(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

/// Text describing a card: what the grid / list / preview show.
@immutable
class NotebookCardInfo {
  const NotebookCardInfo({
    required this.title,
    this.description = '',
    required this.look,
    this.sources = 0,
    this.when = '',
    this.scopeLabel = 'ส่วนตัว',
    this.scopeIcon = NxI.lock,
  });

  factory NotebookCardInfo.of(Notebook n, {required String scopeLabel, required IconData scopeIcon, NotebookAppearance? look}) => NotebookCardInfo(
        title: n.title,
        description: n.description,
        look: look ?? n.look,
        sources: n.sourcesTotal,
        when: notebookRelativeTime(n.updatedAt),
        scopeLabel: scopeLabel,
        scopeIcon: scopeIcon,
      );

  final String title;
  final String description;
  final NotebookAppearance look;
  final int sources;

  /// Thai relative time (wrap with tr()).
  final String when;
  final String scopeLabel;
  final IconData scopeIcon;

  String get shownTitle => title.trim().isEmpty ? tr('สมุดไม่มีชื่อ') : title;
}

/// Grid card ("book").
class NotebookBookCard extends StatelessWidget {
  const NotebookBookCard({super.key, required this.info, this.onTap, this.onLongPress});

  final NotebookCardInfo info;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final look = info.look;
    final tint = look.tint(context);
    final cover = look.cover;
    final book = cover == 'book';
    final gradient = cover == 'gradient';

    Widget body() {
      final title = Text(
        info.shownTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.3, fontSize: 14.5),
      );
      final bottom = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (!gradient) ...[
          _ScopeChip(icon: info.scopeIcon, label: info.scopeLabel, tint: tint),
          const SizedBox(height: 6),
        ],
        _MetaRow(sources: info.sources, when: info.when),
      ]);
      if (gradient) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 9, child: _GradientTop(look: look, info: info, tint: tint)),
          Expanded(
            flex: 10,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const Spacer(), bottom]),
            ),
          ),
        ]);
      }
      return Padding(
        padding: EdgeInsets.fromLTRB(book ? 24 : 14, 14, 10, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _IconTile(look: look, tint: tint, size: 38),
            const Spacer(),
            if (look.pinned) _PinMark(tint: tint),
          ]),
          const SizedBox(height: 10),
          title,
          const Spacer(),
          bottom,
        ]),
      );
    }

    return Semantics(
      button: true,
      label: info.shownTitle,
      child: Material(
        color: _cardColor(dark),
        borderRadius: BorderRadius.circular(_kCardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_kCardRadius),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: dark ? 0.35 : 0.45)),
            ),
            child: Stack(children: [
              // Soft swirl in the corner, in the book's colour.
              Positioned(
                right: -30,
                bottom: -30,
                width: 104,
                height: 104,
                child: IgnorePointer(child: CustomPaint(painter: _SwirlPainter(tint.withValues(alpha: dark ? 0.2 : 0.13)))),
              ),
              if (book) Positioned(left: 0, top: 0, bottom: 0, width: 12, child: _Spine(tint: tint)),
              // Bookmark ribbon hanging from the bottom of the spine.
              if (book) Positioned(left: 8, bottom: 0, width: 10, height: 28, child: _Ribbon(color: _shade(tint, dark ? 0.16 : 0.2))),
              Positioned.fill(child: body()),
            ]),
          ),
        ),
      ),
    );
  }
}

/// List row: a small book cover + title / description / meta + ⋮.
class NotebookListCard extends StatelessWidget {
  const NotebookListCard({super.key, required this.info, this.onTap, this.onLongPress, this.trailing});

  final NotebookCardInfo info;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final tint = info.look.tint(context);
    return Material(
      color: _cardColor(dark),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 2, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: dark ? 0.35 : 0.45)),
          ),
          child: Row(children: [
            NotebookMiniBook(look: info.look),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  if (info.look.pinned) ...[
                    Icon(LucideIcons300.pin, size: 14, color: tint, semanticLabel: tr('ปักหมุด')),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(info.shownTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                ]),
                if (info.description.trim().isNotEmpty)
                  Text(info.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 5),
                Row(children: [
                  _ScopeChip(icon: info.scopeIcon, label: info.scopeLabel, tint: tint),
                  const SizedBox(width: 8),
                  Expanded(child: _MetaRow(sources: info.sources, when: info.when)),
                ]),
              ]),
            ),
            ?trailing,
          ]),
        ),
      ),
    );
  }
}

/// Small book cover (list rows, menus, picker).
class NotebookMiniBook extends StatelessWidget {
  const NotebookMiniBook({super.key, required this.look, this.width = 44, this.height = 56});
  final NotebookAppearance look;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = look.tint(context);
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(5),
      bottomLeft: const Radius.circular(5),
      topRight: Radius.circular(width * 0.24),
      bottomRight: Radius.circular(width * 0.24),
    );
    final iconSize = width * 0.44;
    final Widget face = switch (look.cover) {
      'gradient' => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint, _shade(tint, dark ? -0.12 : 0.16)]),
          ),
          child: Center(child: Icon(look.iconData, size: iconSize, color: Colors.white)),
        ),
      'minimal' => DecoratedBox(
          decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: tint.withValues(alpha: 0.55), width: 1.4)),
          child: Center(child: Icon(look.iconData, size: iconSize, color: tint)),
        ),
      _ => ClipRRect(
          borderRadius: radius,
          child: ColoredBox(
            color: tint.withValues(alpha: dark ? 0.2 : 0.12),
            child: Stack(children: [
              Positioned(left: 0, top: 0, bottom: 0, width: width * 0.18, child: _Spine(tint: tint)),
              Positioned(left: width * 0.18, right: 0, top: 0, bottom: 0, child: Center(child: Icon(look.iconData, size: iconSize, color: tint))),
              Positioned(right: width * 0.16, bottom: 0, width: width * 0.16, height: height * 0.3, child: _Ribbon(color: tint)),
            ]),
          ),
        ),
    };
    return SizedBox(width: width, height: height, child: face);
  }
}

class _Spine extends StatelessWidget {
  const _Spine({required this.tint});
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(children: [
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_shade(tint, dark ? -0.06 : -0.08), tint, _shade(tint, 0.06)], stops: const [0, 0.7, 1]),
          ),
        ),
      ),
      // Light edge where the cover bends.
      Positioned(right: 2, top: 0, bottom: 0, width: 1, child: ColoredBox(color: Colors.white.withValues(alpha: 0.28))),
    ]);
  }
}

class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => ClipPath(clipper: _RibbonClipper(), child: ColoredBox(color: color));
}

class _RibbonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height)
    ..lineTo(s.width / 2, s.height - math.min(6, s.width * 0.8))
    ..lineTo(0, s.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.look, required this.tint, this.size = 38});
  final NotebookAppearance look;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final minimal = look.cover == 'minimal';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: minimal ? null : tint.withValues(alpha: dark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
        border: minimal ? Border.all(color: tint.withValues(alpha: 0.5), width: 1.3) : null,
      ),
      child: Icon(look.iconData, size: size * 0.52, color: tint),
    );
  }
}

class _PinMark extends StatelessWidget {
  const _PinMark({required this.tint, this.onColor = false});
  final Color tint;
  final bool onColor;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: const ValueKey('notebook-pin-mark'),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: onColor ? Colors.white.withValues(alpha: 0.24) : tint.withValues(alpha: dark ? 0.2 : 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(LucideIcons300.pin, size: 13, color: onColor ? Colors.white : tint, semanticLabel: tr('ปักหมุด')),
    );
  }
}

class _GradientTop extends StatelessWidget {
  const _GradientTop({required this.look, required this.info, required this.tint});
  final NotebookAppearance look;
  final NotebookCardInfo info;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final second = HSLColor.fromColor(tint);
    final end = second.withHue((second.hue + 28) % 360).withLightness((second.lightness + (dark ? -0.08 : 0.08)).clamp(0.0, 1.0)).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint, end])),
      child: Stack(children: [
        const Positioned(right: -18, top: -26, width: 86, height: 86, child: _Bubble(alpha: 0.16)),
        const Positioned(left: -14, bottom: -30, width: 64, height: 64, child: _Bubble(alpha: 0.1)),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: _ScopeChip(icon: info.scopeIcon, label: info.scopeLabel, tint: tint, onColor: true)),
              const Spacer(),
              if (look.pinned) _PinMark(tint: tint, onColor: true),
            ]),
            const Spacer(),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(12)),
              child: Icon(look.iconData, size: 19, color: Colors.white),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.alpha});
  final double alpha;

  @override
  Widget build(BuildContext context) =>
      DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: alpha)));
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.icon, required this.label, required this.tint, this.onColor = false});
  final IconData icon;
  final String label;
  final Color tint;
  final bool onColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final fg = onColor ? Colors.white : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: onColor ? Colors.white.withValues(alpha: 0.22) : (dark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10.5, color: fg),
        const SizedBox(width: 3),
        Flexible(
          child: Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg, height: 1.2)),
        ),
      ]),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.sources, required this.when});
  final int sources;
  final String when;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.labelSmall?.copyWith(color: hint);
    return Row(children: [
      Icon(LucideIcons300.layers, size: 12.5, color: hint),
      const SizedBox(width: 4),
      Flexible(child: Text(tr('$sources แหล่ง'), maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
      if (when.isNotEmpty) ...[
        Text(' · ', style: style),
        Flexible(child: Text(tr(when), maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
      ],
    ]);
  }
}

/// A soft spiral curling into the corner, with a faint glow behind it.
class _SwirlPainter extends CustomPainter {
  _SwirlPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.5, size.height * 0.5);
    canvas.drawCircle(
      c,
      size.width * 0.5,
      Paint()..shader = RadialGradient(colors: [color.withValues(alpha: color.a * 0.55), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: size.width * 0.5)),
    );
    final path = Path();
    const turns = 2.25;
    const steps = 90;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps * turns * 2 * math.pi;
      final r = size.width * (0.05 + 0.4 * t / (turns * 2 * math.pi));
      final p = c + Offset(math.cos(t + math.pi) * r, math.sin(t + math.pi) * r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SwirlPainter old) => old.color != color;
}

// ------------------------------------------------------------------ picker

/// Colour palette + icon grid + cover style + pin (controlled).
class NotebookAppearancePicker extends StatelessWidget {
  const NotebookAppearancePicker({super.key, required this.value, required this.onChanged});

  final NotebookAppearance value;
  final ValueChanged<NotebookAppearance> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final tint = value.tint(context);
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(tr(text), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        );
    void set(NotebookAppearance next) {
      HapticFeedback.selectionClick();
      onChanged(next);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      label('สี'),
      LayoutBuilder(builder: (context, box) {
        // One row of 10 when the swatches stay >= 28 pt, else two rows of 5; spread edge to edge.
        final perRow = (box.maxWidth - 9 * 8) / 10 >= 28 ? 10 : 5;
        final size = math.min(36.0, (box.maxWidth - (perRow - 1) * 8) / perRow);
        final gap = perRow == 1 ? 0.0 : (box.maxWidth - perRow * size) / (perRow - 1);
        return Wrap(spacing: gap, runSpacing: 10, children: [
          for (final c in kNotebookColors)
            Semantics(
              selected: value.color == c.key,
              button: true,
              label: tr(c.label),
              child: GestureDetector(
                key: ValueKey('notebook-color-${c.key}'),
                onTap: () => set(value.copyWith(color: c.key)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: c.of(theme.brightness),
                    shape: BoxShape.circle,
                    border: Border.all(color: value.color == c.key ? cs.onSurface : Colors.transparent, width: 2.2),
                    boxShadow: value.color == c.key ? [BoxShadow(color: c.of(theme.brightness).withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))] : null,
                  ),
                  child: value.color == c.key ? Icon(NxI.check, size: size * 0.46, color: Colors.white) : null,
                ),
              ),
            ),
        ]);
      }),
      const SizedBox(height: 18),
      label('ไอคอน'),
      LayoutBuilder(builder: (context, c) {
        // 24 icons: rows of 12 / 8 / 6 so the last row is full.
        final perRow = c.maxWidth >= 640 ? 12 : (c.maxWidth >= 330 ? 8 : 6);
        final size = (c.maxWidth - (perRow - 1) * 8) / perRow;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in kNotebookIcons.entries)
            Semantics(
              selected: value.icon == e.key,
              button: true,
              label: e.key,
              child: Material(
                color: value.icon == e.key ? tint.withValues(alpha: dark ? 0.24 : 0.13) : (dark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF4F5F9)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: value.icon == e.key ? tint : Colors.transparent, width: 1.5),
                ),
                child: InkWell(
                  key: ValueKey('notebook-icon-${e.key}'),
                  customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () => set(value.copyWith(icon: e.key)),
                  child: SizedBox(width: size, height: math.min(size, 46), child: Icon(e.value, size: 20, color: value.icon == e.key ? tint : cs.onSurfaceVariant)),
                ),
              ),
            ),
        ]);
      }),
      const SizedBox(height: 18),
      label('แบบปก'),
      NxSlidingSegmented<String>(
        value: value.cover,
        options: const [('book', 'สมุด', LucideIcons300.bookMarked), ('gradient', 'ไล่สี', LucideIcons300.paintbrush), ('minimal', 'เรียบ', LucideIcons300.square)],
        onChanged: (v) => set(value.copyWith(cover: v)),
      ),
      const SizedBox(height: 8),
      SwitchListTile.adaptive(
        key: const ValueKey('notebook-pin-switch'),
        contentPadding: EdgeInsets.zero,
        secondary: Icon(LucideIcons300.pin, color: value.pinned ? tint : cs.onSurfaceVariant),
        title: Text(tr('ปักหมุดไว้บนสุด'), style: const TextStyle(fontWeight: FontWeight.w600)),
        value: value.pinned,
        onChanged: (v) => set(value.copyWith(pinned: v)),
      ),
    ]);
  }
}

/// Live preview at the top of the create / edit / cover sheets.
class NotebookCardPreview extends StatelessWidget {
  const NotebookCardPreview({super.key, required this.info});
  final NotebookCardInfo info;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: SizedBox(
          key: ValueKey(info.look),
          width: 168,
          height: 192,
          child: IgnorePointer(child: NotebookBookCard(key: const ValueKey('notebook-preview-card'), info: info)),
        ),
      ),
    );
  }
}

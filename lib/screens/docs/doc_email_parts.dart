import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../widgets/nx_icons.dart';

/// Parts of the document e-mail composer ([DocEmailSheet]): recipient lines
/// with chips + suggestions, attachment cards, the "sent" check.

final docEmailRe = RegExp(r'^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$');

/// Readable error red on the composer's surface (light / dark).
Color composeErrorColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFF8A8A) : const Color(0xFFC81E3A);

typedef DocEmailSuggestion = ({String email, String label, String source});

/// `a@x.th, Name <b@y.th>; c` → lower-case addresses (empty parts dropped).
List<String> parseRecipients(String raw) => raw
    .split(RegExp(r'[,;\s]+'))
    .map((x) => x.trim().replaceAll(RegExp(r'^.*<|>$'), '').toLowerCase())
    .where((x) => x.isNotEmpty)
    .toList();

const docEmailSourceLabel = {
  'contact': 'ผู้ติดต่อ',
  'customer': 'ลูกค้า',
  'account': 'บัญชีลูกค้า',
  'owner': 'ผู้รับผิดชอบ',
  'authorizer': 'ผู้มีอำนาจลงนาม',
  'engineer': 'ช่าง',
  'sales': 'ฝ่ายขาย',
  'me': 'ฉัน',
  'user': 'ผู้ใช้',
  'recent': 'ล่าสุด',
};

const _palette = [
  Color(0xFF6366F1),
  Color(0xFF0D9488),
  Color(0xFFD97706),
  Color(0xFFE11D48),
  Color(0xFF0284C7),
  Color(0xFF7C3AED),
  Color(0xFF059669),
  Color(0xFFEA580C),
  Color(0xFFDB2777),
  Color(0xFF4F46E5),
];

/// Stable colour per person.
Color recipientColor(String seed) {
  var h = 0x811c9dc5;
  for (final c in seed.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return _palette[h % _palette.length];
}

String _initial(String name, String email) {
  final src = name.trim().isNotEmpty ? name.trim() : email;
  // Skip leading Thai vowels that are written before the consonant.
  final chars = src.characters.where((c) => !'เแโใไ'.contains(c)).toList();
  return (chars.isEmpty ? '?' : chars.first).toUpperCase();
}

class RecipientAvatar extends StatelessWidget {
  const RecipientAvatar({super.key, required this.email, this.name = '', this.size = 32});
  final String email;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = recipientColor(email);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.32 : 0.16), shape: BoxShape.circle),
      child: Text(
        _initial(name, email),
        textScaler: TextScaler.noScaling,
        style: TextStyle(fontSize: size * 0.44, fontWeight: FontWeight.w700, color: Theme.of(context).brightness == Brightness.dark ? Color.lerp(c, Colors.white, 0.55) : Color.lerp(c, Colors.black, 0.15), height: 1.1),
      ),
    );
  }
}

/// One header line of the composer: muted label on the left, content on the right.
class ComposeLine extends StatelessWidget {
  const ComposeLine({super.key, required this.label, required this.child, this.trailing, this.onTapLabel, this.divider = true});
  final String label;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTapLabel;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(border: divider ? Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7))) : null),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onTapLabel,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(top: 13, right: 10),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 44),
                    child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                ),
              ),
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: child)),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// "ถึง" / "สำเนา" / "สำเนาลับ": chips + an inline field. Typing shows
/// suggestions (contacts, people of the record, recent addresses); Enter,
/// comma, semicolon or space adds; invalid addresses turn red; tap a chip
/// to edit or remove it. The parent owns [controller] (text still being
/// typed is sent too).
class RecipientLine extends StatefulWidget {
  const RecipientLine({
    super.key,
    required this.label,
    required this.values,
    required this.onChanged,
    required this.controller,
    this.suggestions = const [],
    this.trailing,
    this.enabled = true,
    this.onTapLabel,
  });
  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final TextEditingController controller;
  final List<DocEmailSuggestion> suggestions;
  final Widget? trailing;
  final bool enabled;
  final VoidCallback? onTapLabel;

  @override
  State<RecipientLine> createState() => _RecipientLineState();
}

class _RecipientLineState extends State<RecipientLine> {
  final _focus = FocusNode();
  TextEditingController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    _ctrl.addListener(_changed);
  }

  @override
  void didUpdateWidget(RecipientLine old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _focusChanged() {
    // Leaving the line keeps what was typed as a chip (red when invalid).
    if (!_focus.hasFocus && _ctrl.text.trim().isNotEmpty) _add(_ctrl.text);
    if (mounted) setState(() {});
  }

  void _add(String raw) {
    final next = [...widget.values];
    for (final p in parseRecipients(raw)) {
      if (!next.contains(p)) next.add(p);
    }
    _ctrl.clear();
    if (next.length != widget.values.length) widget.onChanged(next);
  }

  List<DocEmailSuggestion> get _matches {
    final q = _ctrl.text.trim().toLowerCase();
    final list = widget.suggestions.where((s) => !widget.values.contains(s.email));
    if (q.isEmpty) return list.take(5).toList();
    return list.where((s) => s.email.contains(q) || s.label.toLowerCase().contains(q)).take(5).toList();
  }

  String _nameOf(String e) => widget.suggestions.where((s) => s.email == e && s.label.isNotEmpty).firstOrNull?.label ?? '';

  void _edit(String e) {
    widget.onChanged([...widget.values]..remove(e));
    _ctrl.value = TextEditingValue(text: e, selection: TextSelection(baseOffset: 0, extentOffset: e.length));
    _focus.requestFocus();
  }

  Future<void> _chipTapped(String e) async {
    if (!widget.enabled) return;
    HapticFeedback.selectionClick();
    if (!docEmailRe.hasMatch(e)) return _edit(e);
    final name = _nameOf(e);
    final src = widget.suggestions.where((s) => s.email == e).firstOrNull?.source;
    final act = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: RecipientAvatar(email: e, name: name, size: 44),
                title: Text(name.isEmpty ? e : name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                subtitle: Text([if (name.isNotEmpty) e, if (src != null && docEmailSourceLabel[src] != null) tr(docEmailSourceLabel[src]!)].join(' · ')),
              ),
              const Divider(height: 8),
              ListTile(key: const ValueKey('compose-chip-edit'), leading: const Icon(NxI.pencilSimple), title: Text(tr('แก้ไขอีเมล')), onTap: () => Navigator.pop(ctx, 'edit')),
              ListTile(key: const ValueKey('compose-chip-copy'), leading: const Icon(NxI.copySimple), title: Text(tr('คัดลอกอีเมล')), onTap: () => Navigator.pop(ctx, 'copy')),
              ListTile(
                key: const ValueKey('compose-chip-remove'),
                leading: Icon(NxI.trash, color: theme.colorScheme.error),
                title: Text(tr('เอาผู้รับออก'), style: TextStyle(color: theme.colorScheme.error)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    switch (act) {
      case 'edit':
        _edit(e);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: e));
      case 'remove':
        widget.onChanged([...widget.values]..remove(e));
    }
  }

  Widget _chip(ThemeData theme, ColorScheme cs, String e) {
    final ok = docEmailRe.hasMatch(e);
    final name = _nameOf(e);
    final dark = theme.brightness == Brightness.dark;
    final err = composeErrorColor(context);
    final bg = ok ? cs.surfaceContainerHighest.withValues(alpha: dark ? 0.9 : 0.75) : err.withValues(alpha: dark ? 0.16 : 0.08);
    final fg = ok ? cs.onSurface : err;
    return Tooltip(
      message: e,
      child: Material(
        key: ValueKey('chip-$e'),
        color: bg,
        shape: StadiumBorder(side: ok ? BorderSide.none : BorderSide(color: err.withValues(alpha: 0.5))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => _chipTapped(e),
          onLongPress: () => _chipTapped(e),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(3, 3, 2, 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ok)
                  RecipientAvatar(email: e, name: name, size: 24)
                else
                  SizedBox(width: 24, height: 24, child: Icon(NxI.warningCircle, size: 16, color: err)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    name.isEmpty ? e : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: fg, fontWeight: FontWeight.w500),
                  ),
                ),
                if (widget.enabled)
                  InkResponse(
                    radius: 16,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onChanged([...widget.values]..remove(e));
                    },
                    child: Padding(padding: const EdgeInsets.all(5), child: Icon(NxI.x, size: 14, color: fg.withValues(alpha: 0.7))),
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final matches = _focus.hasFocus && widget.enabled ? _matches : const <DocEmailSuggestion>[];
    final bad = widget.values.where((e) => !docEmailRe.hasMatch(e)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ComposeLine(
          label: widget.label,
          trailing: widget.trailing,
          onTapLabel: widget.onTapLabel ?? () => _focus.requestFocus(),
          divider: matches.isEmpty,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _focus.requestFocus(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final e in widget.values) _chip(theme, cs, e),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 120),
                      child: IntrinsicWidth(
                        child: TextField(
                          controller: _ctrl,
                          focusNode: _focus,
                          enabled: widget.enabled,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enableSuggestions: false,
                          style: theme.textTheme.bodyLarge,
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            filled: false,
                            hintText: widget.values.isEmpty ? tr('พิมพ์ชื่อหรืออีเมล') : null,
                            contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
                          ),
                          onChanged: (v) {
                            if (RegExp(r'[,;\s]$').hasMatch(v)) _add(v);
                          },
                          onSubmitted: (v) {
                            final m = _matches;
                            if (v.trim().isNotEmpty && !docEmailRe.hasMatch(v.trim()) && m.isNotEmpty) {
                              _add(m.first.email);
                            } else {
                              _add(v);
                            }
                            _focus.requestFocus();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                if (bad > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: Text(
                      tr('อีเมลไม่ถูกต้อง — แตะเพื่อแก้ไข'),
                      key: const ValueKey('compose-invalid-hint'),
                      style: theme.textTheme.bodySmall?.copyWith(color: composeErrorColor(context)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (matches.isNotEmpty)
          Container(
            key: const ValueKey('compose-suggestions'),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7))),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final s in matches)
                  InkWell(
                    key: ValueKey('suggest-${s.email}'),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _add(s.email);
                      _focus.requestFocus();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          RecipientAvatar(email: s.email, name: s.label, size: 36),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.label.isEmpty ? s.email : s.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                if (s.label.isNotEmpty)
                                  Text(s.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          if (docEmailSourceLabel[s.source] != null || s.source.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
                              child: Text(tr(docEmailSourceLabel[s.source] ?? s.source), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------ attachments

({IconData icon, Color color}) fileVisual(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'pdf' => (icon: NxI.filePdf, color: const Color(0xFFE5484D)),
    'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' || 'heif' => (icon: NxI.image, color: const Color(0xFF0EA5E9)),
    'doc' || 'docx' || 'rtf' || 'odt' => (icon: NxI.fileDoc, color: const Color(0xFF2563EB)),
    'xls' || 'xlsx' || 'csv' || 'ods' => (icon: NxI.fileXls, color: const Color(0xFF16A34A)),
    'zip' || 'rar' || '7z' => (icon: NxI.fileZip, color: const Color(0xFFA16207)),
    _ => (icon: NxI.fileText, color: const Color(0xFF64748B)),
  };
}

/// A card in the composer's attachment row.
class AttachmentCard extends StatelessWidget {
  const AttachmentCard({
    super.key,
    required this.name,
    required this.meta,
    this.badge,
    this.onTap,
    this.onRemove,
    this.removeKey,
    this.metaKey,
    this.progress,
    this.width = 264,
  });
  final String name;
  final String meta;
  final String? badge;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final Key? removeKey;
  final Key? metaKey;

  /// Upload progress 0..1 while sending (null = not uploading).
  final double? progress;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final v = fileVisual(name);
    final dark = theme.brightness == Brightness.dark;
    return SizedBox(
      width: width,
      child: Material(
        color: dark ? cs.surfaceContainerHigh : cs.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: cs.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 2, 8),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: v.color.withValues(alpha: dark ? 0.22 : 0.12), borderRadius: BorderRadius.circular(10)),
                      child: Icon(v.icon, color: v.color, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (badge != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                                  child: Text(badge!, maxLines: 1, style: theme.textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(
                                  progress != null ? '${(progress! * 100).round()}%' : meta,
                                  key: metaKey,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (onRemove != null)
                      IconButton(
                        key: removeKey,
                        tooltip: tr('เอาไฟล์ออก'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          onRemove!();
                        },
                        icon: Icon(NxI.x, size: 16, color: cs.onSurfaceVariant),
                      )
                    else
                      const SizedBox(width: 8),
                  ],
                ),
              ),
              if (progress != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(value: progress, minHeight: 3, backgroundColor: cs.primary.withValues(alpha: 0.1)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed "add" tile at the end of the attachment row.
class AddAttachmentTile extends StatelessWidget {
  const AddAttachmentTile({super.key, required this.label, this.onTap, this.icon = NxI.plus, this.width});
  final String label;
  final VoidCallback? onTap;
  final IconData icon;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = onTap == null ? cs.outline : cs.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: CustomPaint(
          painter: _DashedBorder(color: c.withValues(alpha: 0.55), radius: 14),
          child: Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: c),
                const SizedBox(width: 6),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge?.copyWith(color: c, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(0.7));
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), p);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

// ------------------------------------------------------------ sent

/// Animated check shown once the e-mail is sent.
class SentCheck extends StatefulWidget {
  const SentCheck({super.key, this.size = 88, this.color});
  final double size;
  final Color? color;

  @override
  State<SentCheck> createState() => _SentCheckState();
}

class _SentCheckState extends State<SentCheck> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _a.value = 1;
    } else if (!_a.isAnimating && _a.value == 0) {
      _a.forward();
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? const Color(0xFF16A34A);
    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) {
        final scale = Curves.easeOutBack.transform((_a.value / 0.55).clamp(0.0, 1.0));
        final draw = Curves.easeOutCubic.transform(((_a.value - 0.35) / 0.65).clamp(0.0, 1.0));
        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.withValues(alpha: 0.14),
              boxShadow: [BoxShadow(color: c.withValues(alpha: 0.18 * scale.clamp(0, 1)), blurRadius: 24, spreadRadius: 2)],
            ),
            child: CustomPaint(painter: _CheckPainter(progress: draw, color: c)),
          ),
        );
      },
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final inner = size.width * 0.62;
    final o = Offset((size.width - inner) / 2, (size.height - inner) / 2);
    canvas.drawCircle(size.center(Offset.zero), inner / 2, Paint()..color = color);
    if (progress <= 0) return;
    final path = Path()
      ..moveTo(o.dx + inner * 0.27, o.dy + inner * 0.52)
      ..lineTo(o.dx + inner * 0.44, o.dy + inner * 0.68)
      ..lineTo(o.dx + inner * 0.74, o.dy + inner * 0.36);
    final m = path.computeMetrics().first;
    canvas.drawPath(
      m.extractPath(0, m.length * progress),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = inner * 0.09
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress || old.color != color;
}

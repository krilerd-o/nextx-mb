import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';

import '../../core/i18n.dart';
import '../../core/notebook/notebook_studio_meta.dart';
import '../../services/notebook/notebook_controller.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import 'notebook_studio_views.dart' show StudioSourceChips;
import 'notebook_widgets.dart';

/// Interactive mind map from `meta.mindmap` (NotebookLM style): a left-to-right
/// tree on a pan / zoom canvas. Every branch expands and collapses on its own
/// (the round badge), "ขยายทั้งหมด" / "ยุบทั้งหมด" do the whole tree, and tapping a
/// topic offers "ถามในแชท" (the question goes into the chat composer).
class MindTreeView extends StatefulWidget {
  const MindTreeView({super.key, required this.c, required this.root, this.sources = const [], this.onDraft, this.initiallyOpen});
  final NotebookController c;
  final MindTreeNode root;
  final List<StudioSourceRef> sources;

  /// "ถามในแชท": puts a question about the node in the chat composer.
  final ValueChanged<String>? onDraft;

  /// Ids open at first (default: the root, so the main branches show).
  final Set<String>? initiallyOpen;

  @override
  State<MindTreeView> createState() => MindTreeViewState();
}

/// Question put in the chat for [n] ("อธิบายเรื่อง … ในหัวข้อ …").
String mindNodeQuestion(MindTreeNode n) {
  final p = n.parent;
  if (p != null && p.parent != null) return 'อธิบายเรื่อง "${n.label}" ในหัวข้อ "${p.label}" จากแหล่งข้อมูล';
  return 'อธิบายเรื่อง "${n.label}" จากแหล่งข้อมูล';
}

class _Layout {
  _Layout(this.rects, this.edges, this.size);
  final Map<String, Rect> rects;
  final List<(MindTreeNode, MindTreeNode)> edges;
  final Size size;
}

class MindTreeViewState extends State<MindTreeView> with SingleTickerProviderStateMixin {
  late Set<String> open = {...(widget.initiallyOpen ?? {widget.root.id})};
  final _tc = TransformationController();
  Size _viewport = Size.zero;
  bool _placed = false;

  static const palette = [Color(0xFF6366F1), Color(0xFF0EA5E9), Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFFEC4899), Color(0xFF8B5CF6), Color(0xFFEF4444), Color(0xFF14B8A6)];
  static const _pad = 28.0, _vGap = 12.0;

  /// Phones: narrower cards so a bit of the next level peeks in (and invites a pan).
  bool get _narrow => _viewport.width > 0 && _viewport.width < 560;
  double get _hGap => _narrow ? 32 : 40;

  late final AnimationController _pan = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  Matrix4Tween? _panTween;

  late final Map<String, MindTreeNode> _byId = {for (final n in widget.root.all) n.id: n};
  late final Map<String, int> _branch = {
    for (final (i, b) in widget.root.children.indexed)
      for (final n in b.all) n.id: i,
  };

  @override
  void dispose() {
    _pan.dispose();
    _tc.dispose();
    super.dispose();
  }

  Color colorOf(MindTreeNode n) => palette[(_branch[n.id] ?? 0) % palette.length];

  double _width(int depth) => _narrow ? (depth == 0 ? 150 : 148) : (depth == 0 ? 176 : 164);

  TextStyle _style(ThemeData theme, int depth) => switch (depth) {
        0 => theme.textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w800, color: Colors.white, height: 1.3),
        1 => theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w800, height: 1.3),
        _ => theme.textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w600, height: 1.35, fontSize: 13),
      };

  _Layout _layout(BuildContext context) {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final rects = <String, Rect>{};
    final edges = <(MindTreeNode, MindTreeNode)>[];
    final colX = <int, double>{};
    double xAt(int depth) => colX[depth] ??= depth == 0 ? _pad : xAt(depth - 1) + _width(depth - 1) + _hGap;

    double heightOf(MindTreeNode n) {
      final inner = _width(n.depth) - 24 - (n.isLeaf ? 0 : 32);
      final tp = TextPainter(
        text: TextSpan(text: n.label, style: _style(theme, n.depth)),
        maxLines: 4,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(maxWidth: inner);
      final h = math.max(n.depth == 0 ? 52.0 : 42.0, tp.height + 22);
      tp.dispose();
      return h;
    }

    void shift(MindTreeNode n, double dy) {
      final r = rects[n.id];
      if (r != null) rects[n.id] = r.shift(Offset(0, dy));
      if (open.contains(n.id)) {
        for (final c in n.children) {
          shift(c, dy);
        }
      }
    }

    // Returns the bottom of [n]'s subtree.
    double place(MindTreeNode n, double top) {
      final h = heightOf(n);
      final w = _width(n.depth);
      final x = xAt(n.depth);
      if (n.isLeaf || !open.contains(n.id)) {
        rects[n.id] = Rect.fromLTWH(x, top, w, h);
        return top + h;
      }
      var y = top;
      for (final c in n.children) {
        edges.add((n, c));
        y = place(c, y) + _vGap;
      }
      var childrenBottom = y - _vGap;
      final first = rects[n.children.first.id]!, last = rects[n.children.last.id]!;
      var ny = (first.center.dy + last.center.dy) / 2 - h / 2;
      if (ny < top) {
        // Taller than its children: push the children down so they centre on it.
        final dy = top - ny;
        for (final c in n.children) {
          shift(c, dy);
        }
        childrenBottom += dy;
        ny = top;
      }
      rects[n.id] = Rect.fromLTWH(x, ny, w, h);
      return math.max(ny + h, childrenBottom);
    }

    final bottom = place(widget.root, _pad);
    var maxX = 0.0;
    for (final r in rects.values) {
      maxX = math.max(maxX, r.right);
    }
    return _Layout(rects, edges, Size(maxX + _pad, bottom + _pad));
  }

  /// Runs [change] on the open set and keeps [anchor] at the same place on screen.
  void _change(String anchor, VoidCallback change) {
    final before = _layout(context).rects[anchor];
    setState(change);
    final after = _layout(context).rects[anchor];
    if (before == null || after == null) return;
    final d = after.topLeft - before.topLeft;
    if (d == Offset.zero) return;
    final m = _tc.value.clone();
    final s = m.getMaxScaleOnAxis();
    m.setTranslationRaw(m.entry(0, 3) - d.dx * s, m.entry(1, 3) - d.dy * s, 0);
    _tc.value = m;
  }

  void toggle(MindTreeNode n) {
    if (n.isLeaf) return;
    HapticFeedback.selectionClick();
    final opening = !open.contains(n.id);
    _change(n.id, () => opening ? open.add(n.id) : open.remove(n.id));
    if (opening) _reveal(n);
  }

  /// After opening [n]: glide so its children are on screen (without pushing [n] off the left).
  void _reveal(MindTreeNode n) {
    final v = _viewport;
    if (v.isEmpty) return;
    final rects = _layout(context).rects;
    final self = rects[n.id];
    final kids = [for (final c in n.children) ?rects[c.id]];
    if (self == null || kids.isEmpty) return;
    final m = _tc.value;
    final s = m.getMaxScaleOnAxis();
    final tx = m.entry(0, 3), ty = m.entry(1, 3);
    final right = kids.map((r) => r.right).reduce(math.max), top = kids.map((r) => r.top).reduce(math.min), bottom = kids.map((r) => r.bottom).reduce(math.max);
    var dx = 0.0, dy = 0.0;
    if (tx + right * s > v.width - 12) dx = math.max(v.width - 12 - (tx + right * s), 12 - (tx + self.left * s));
    if (ty + bottom * s > v.height - 12) dy = v.height - 12 - (ty + bottom * s);
    if (ty + top * s + dy < 12) dy = 12 - (ty + top * s);
    if (dx.abs() < 1 && dy.abs() < 1) return;
    final target = m.clone()..setTranslationRaw(tx + dx, ty + dy, 0);
    _panTween = Matrix4Tween(begin: m.clone(), end: target);
    _pan
      ..removeListener(_onPan)
      ..addListener(_onPan)
      ..forward(from: 0);
  }

  void _onPan() {
    final t = _panTween;
    if (t != null) _tc.value = t.transform(Curves.easeOutCubic.transform(_pan.value));
  }

  void expandAll() {
    HapticFeedback.selectionClick();
    _change(widget.root.id, () => open = {for (final n in widget.root.all) if (!n.isLeaf) n.id});
  }

  void collapseAll() {
    HapticFeedback.selectionClick();
    _change(widget.root.id, () => open = {widget.root.id});
  }

  void _zoom(double f) {
    final v = _viewport;
    final m = _tc.value.clone();
    final s = m.getMaxScaleOnAxis();
    final next = (s * f).clamp(0.35, 2.2);
    final k = next / s;
    final c = Offset(v.width / 2, v.height / 2);
    // Scale around the viewport centre.
    final tx = c.dx - (c.dx - m.entry(0, 3)) * k, ty = c.dy - (c.dy - m.entry(1, 3)) * k;
    _tc.value = Matrix4.identity()
      ..setEntry(0, 0, next)
      ..setEntry(1, 1, next)
      ..setEntry(2, 2, 1)
      ..setTranslationRaw(tx, ty, 0);
  }

  void fit() {
    final l = _layout(context);
    final v = _viewport;
    if (v.isEmpty) return;
    final s = math.min(1.0, math.min(v.width / l.size.width, v.height / l.size.height)).clamp(0.35, 1.0);
    final tx = math.max(0.0, (v.width - l.size.width * s) / 2), ty = (v.height - l.size.height * s) / 2;
    _tc.value = Matrix4.identity()
      ..setEntry(0, 0, s)
      ..setEntry(1, 1, s)
      ..setTranslationRaw(tx, ty, 0);
  }

  /// First frame: the root in view, vertically centred.
  void _placeInitial(_Layout l) {
    if (_placed || _viewport.isEmpty) return;
    _placed = true;
    final root = l.rects[widget.root.id]!;
    final ty = l.size.height <= _viewport.height ? (_viewport.height - l.size.height) / 2 : _viewport.height / 2 - root.center.dy;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tc.value = Matrix4.identity()..setTranslationRaw(0, ty.clamp(-l.size.height + 80, _viewport.height / 2), 0);
    });
  }

  Future<void> _openNode(MindTreeNode n) async {
    HapticFeedback.selectionClick();
    final color = n.depth == 0 ? const Color(0xFFEC4899) : colorOf(n);
    await showAppBottomSheet<void>(
      context: context,
      title: null,
      child: Builder(builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final path = n.path;
        return Column(key: const ValueKey('mindtree-sheet'), mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (path.length > 1)
            Text(path.sublist(0, path.length - 1).join('  ›  '), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 6), child: Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle))),
            const SizedBox(width: 10),
            Expanded(child: Text(n.label, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.3))),
          ]),
          if (!n.isLeaf)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2),
              child: Text(tr('${n.children.length} หัวข้อย่อย'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
          if (n.effectiveSourceIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(tr('จากแหล่งข้อมูล'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
            const SizedBox(height: 6),
            StudioSourceChips(c: widget.c, sources: widget.sources, ids: n.effectiveSourceIds),
          ],
          const SizedBox(height: 18),
          if (widget.onDraft != null)
            FilledButton.icon(
              key: const ValueKey('mindtree-ask'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: kNotebookAccent),
              onPressed: () {
                Navigator.pop(ctx);
                widget.onDraft!(tr(mindNodeQuestion(n)));
              },
              icon: const Icon(LucideIcons300.messagesSquare, size: 18),
              label: Text(tr('ถามในแชท')),
            ),
          if (!n.isLeaf) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('mindtree-sheet-toggle'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              onPressed: () {
                Navigator.pop(ctx);
                toggle(n);
              },
              icon: Icon(open.contains(n.id) ? LucideIcons300.chevronsDownUp : LucideIcons300.chevronsUpDown, size: 18),
              label: Text(tr(open.contains(n.id) ? 'ยุบกิ่งนี้' : 'ขยายกิ่งนี้')),
            ),
          ],
        ]);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final total = widget.root.size - 1;
    final allOpen = widget.root.all.where((n) => !n.isLeaf).every((n) => open.contains(n.id));
    return Column(key: const ValueKey('notebook-mindtree'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _pill(context, key: 'mindtree-expand-all', icon: LucideIcons300.chevronsUpDown, label: 'ขยายทั้งหมด', onTap: allOpen ? null : expandAll),
          _pill(context, key: 'mindtree-collapse-all', icon: LucideIcons300.chevronsDownUp, label: 'ยุบทั้งหมด', onTap: open.length <= 1 && open.contains(widget.root.id) ? null : collapseAll),
          Text(tr('$total หัวข้อ · แตะหัวข้อเพื่อถามในแชท'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          _viewport = box.biggest;
          final l = _layout(context);
          _placeInitial(l);
          return Stack(children: [
            Positioned.fill(
              child: InteractiveViewer(
                key: const ValueKey('mindtree-canvas'),
                transformationController: _tc,
                constrained: false,
                minScale: 0.35,
                maxScale: 2.2,
                boundaryMargin: EdgeInsets.symmetric(horizontal: box.maxWidth * 0.6, vertical: box.maxHeight * 0.6),
                child: SizedBox(
                  width: math.max(l.size.width, box.maxWidth),
                  height: math.max(l.size.height, box.maxHeight),
                  child: Stack(children: [
                    Positioned.fill(child: CustomPaint(painter: _EdgePainter(edges: l.edges, rects: l.rects, colorOf: (n) => colorOf(n), dot: cs.outlineVariant.withValues(alpha: dark ? 0.18 : 0.35)))),
                    for (final e in l.rects.entries) _node(context, _byId[e.key]!, e.value),
                  ]),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12 + MediaQuery.paddingOf(context).bottom,
              child: Container(
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF1C1D26) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.3 : 0.06), blurRadius: 10, offset: const Offset(0, 3))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _tool(context, 'mindtree-zoom-in', 'ซูมเข้า', LucideIcons300.zoomIn, () => _zoom(1.25)),
                  Container(width: 22, height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
                  _tool(context, 'mindtree-zoom-out', 'ซูมออก', LucideIcons300.zoomOut, () => _zoom(0.8)),
                  Container(width: 22, height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
                  _tool(context, 'mindtree-fit', 'พอดีจอ', LucideIcons300.scan, fit),
                ]),
              ),
            ),
          ]);
        }),
      ),
    ]);
  }

  Widget _tool(BuildContext context, String key, String tip, IconData icon, VoidCallback onTap) => Tooltip(
        message: tr(tip),
        child: InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(width: 42, height: 40, child: Icon(icon, size: 19, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );

  Widget _pill(BuildContext context, {required String key, required IconData icon, required String label, VoidCallback? onTap}) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: dark ? Colors.white.withValues(alpha: 0.07) : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey(key),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 15, color: kNotebookAccent),
              const SizedBox(width: 6),
              Text(tr(label), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _node(BuildContext context, MindTreeNode n, Rect r) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final color = colorOf(n);
    final isOpen = open.contains(n.id);
    final root = n.depth == 0;
    final Color fill = root ? Colors.transparent : (n.depth == 1 ? Color.alphaBlend(color.withValues(alpha: dark ? 0.26 : 0.12), dark ? const Color(0xFF1C1D26) : Colors.white) : (dark ? const Color(0xFF1C1D26) : Colors.white));
    final border = root ? Colors.transparent : (n.depth == 1 ? color.withValues(alpha: 0.6) : color.withValues(alpha: 0.35));
    final badge = n.isLeaf
        ? null
        : Semantics(
            button: true,
            label: tr(isOpen ? 'ยุบ' : 'ขยาย'),
            child: GestureDetector(
              key: ValueKey('mindtree-toggle-${n.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => toggle(n),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: root ? Colors.white.withValues(alpha: 0.25) : (isOpen ? color.withValues(alpha: dark ? 0.3 : 0.14) : color),
                  ),
                  child: isOpen
                      ? Icon(NxI.caretLeft, size: 14, color: root ? Colors.white : color)
                      : Text('+${n.children.length}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1)),
                ),
              ),
            ),
          );
    return Positioned(
      key: ValueKey('mindtree-pos-${n.id}'),
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        builder: (context, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(-12 * (1 - t), 0), child: child)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(root ? 18 : 14),
            gradient: root ? const LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFFEC4899)]) : null,
            boxShadow: [
              BoxShadow(color: (root ? const Color(0xFFEC4899) : Colors.black).withValues(alpha: root ? 0.28 : (dark ? 0.25 : 0.05)), blurRadius: root ? 16 : 8, offset: const Offset(0, 3)),
            ],
          ),
          child: Material(
            color: fill,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(root ? 18 : 14), side: BorderSide(color: border, width: n.depth == 1 ? 1.4 : 1)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('mindtree-node-${n.id}'),
              onTap: () => _openNode(n),
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 0, n.isLeaf ? 12 : 4, 0),
                child: Row(children: [
                  if (n.depth >= 2) ...[Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 6)],
                  Expanded(
                    child: Text(
                      n.label,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: _style(theme, n.depth).copyWith(color: root ? Colors.white : (n.depth == 1 ? (dark ? Colors.white : Color.lerp(color, Colors.black, 0.45)) : cs.onSurface)),
                    ),
                  ),
                  ?badge,
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({required this.edges, required this.rects, required this.colorOf, required this.dot});
  final List<(MindTreeNode, MindTreeNode)> edges;
  final Map<String, Rect> rects;
  final Color Function(MindTreeNode) colorOf;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    // Dotted canvas.
    final d = Paint()..color = dot;
    for (var x = 12.0; x < size.width; x += 24) {
      for (var y = 12.0; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 0.9, d);
      }
    }
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in edges) {
      final ra = rects[a.id], rb = rects[b.id];
      if (ra == null || rb == null) continue;
      final from = Offset(ra.right, ra.center.dy), to = Offset(rb.left, rb.center.dy);
      final mid = (from.dx + to.dx) / 2;
      p.color = colorOf(b).withValues(alpha: 0.6);
      canvas.drawPath(
        Path()
          ..moveTo(from.dx, from.dy)
          ..cubicTo(mid, from.dy, mid, to.dy, to.dx, to.dy),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) => true;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/home_layout.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_icons.dart';
import 'home_boxes.dart' show kHomeWidgetGap;
import 'home_widgets.dart';

/// Columns of the Home grid: phone 2, tablet / open foldable 3, wide 4.
int homeGridColumns(double width) => width < 600 ? 2 : width < 1000 ? 3 : 4;

/// Home widgets laid out in rows (half = one column, full = whole row), with
/// the iPhone-style edit mode: long-press → wiggle, ⊖ hide, ½/full, drag.
class HomeWidgetGrid extends StatefulWidget {
  const HomeWidgetGrid({
    super.key,
    required this.entries,
    required this.build,
    required this.editing,
    required this.wiggle,
    required this.onStartEditing,
    required this.onMove,
    required this.onHide,
    required this.onResize,
    this.onDragUpdate,
    this.onDragEnd,
    this.sliver = false,
  });

  /// Lay the rows out as a lazy [SliverList] (Home's scroll view): each widget row is built
  /// when it nears the screen and then kept alive (no reload when scrolled back). Edit mode
  /// uses the plain column (dragging needs every cell present).
  final bool sliver;

  final List<HomeEntry> entries;

  /// Content of a widget, or null when it has nothing to show (no access / no data).
  final Widget? Function(HomeEntry e) build;
  final bool editing;
  final Animation<double> wiggle;
  final VoidCallback onStartEditing;

  /// Move [id] to where [beforeId] is now.
  final void Function(String id, String beforeId) onMove;
  final ValueChanged<String> onHide;
  final ValueChanged<String> onResize;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragEnd;

  @override
  State<HomeWidgetGrid> createState() => _HomeWidgetGridState();
}

class _HomeWidgetGridState extends State<HomeWidgetGrid> {
  final Map<String, GlobalKey> _keys = {};
  String? _dragging;

  GlobalKey _key(String id) => _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'home-cell-$id'));

  @override
  Widget build(BuildContext context) {
    if (widget.sliver) {
      return SliverLayoutBuilder(builder: (context, c) {
        final rows = _rows(c.crossAxisExtent);
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _KeepAliveRow(key: rows[i].key, child: rows[i]),
            childCount: rows.length,
            // Rows keep their element (and loaded data) when others move or hide.
            findChildIndexCallback: (key) {
              for (var i = 0; i < rows.length; i++) {
                if (rows[i].key == key) return i;
              }
              return null;
            },
            addRepaintBoundaries: true,
          ),
        );
      });
    }
    return LayoutBuilder(builder: (context, c) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _rows(c.maxWidth));
    });
  }

  /// One widget per Home row (a full-width widget, or up to [homeGridColumns] half charts).
  List<Widget> _rows(double maxWidth) {
    {
      final c = BoxConstraints(maxWidth: maxWidth);
      final cols = homeGridColumns(c.maxWidth);
      const gap = 12.0;
      final cellW = (c.maxWidth - gap * (cols - 1)) / cols;
      final rows = <Widget>[];
      var row = <Widget>[];
      var used = 0;

      void flush() {
        if (row.isEmpty) return;
        final children = <Widget>[];
        for (var i = 0; i < row.length; i++) {
          if (i > 0) children.add(const SizedBox(width: gap));
          children.add(row[i]);
        }
        rows.add(Padding(
          key: ValueKey('home-row-${row.map((w) => w.key).join('+')}'),
          padding: const EdgeInsets.only(top: kHomeWidgetGap),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ));
        row = [];
        used = 0;
      }

      for (final e in widget.entries) {
        final content = widget.build(e);
        if (content == null && !widget.editing) continue;
        final chart = HomeLayout.isChart(e.id);
        final half = chart && e.size == HomeSize.half;
        final span = half ? 1 : cols;
        final cell = _cell(e, content, width: half ? cellW : c.maxWidth);
        if (!chart && !widget.editing) {
          // Classic sections bring their own spacing.
          flush();
          rows.add(KeyedSubtree(key: ValueKey('home-row-${e.id}'), child: KeyedSubtree(key: _key(e.id), child: _draggable(e, content!, c.maxWidth))));
          continue;
        }
        if (used + span > cols) flush();
        row.add(SizedBox(key: ValueKey(e.id), width: half ? cellW : c.maxWidth, child: cell));
        used += span;
        if (used >= cols) flush();
      }
      flush();
      return rows;
    }
  }

  Widget _cell(HomeEntry e, Widget? content, {required double width}) {
    final body = widget.editing ? _EditFrame(entry: e, content: content, onHide: widget.onHide, onResize: widget.onResize) : content!;
    return KeyedSubtree(key: _key(e.id), child: _draggable(e, body, width));
  }

  Widget _draggable(HomeEntry e, Widget child, double width) {
    final info = HomeWidgetInfo.of(e.id);
    final phase = (e.id.hashCode % 628) / 100.0;
    final wiggling = widget.editing && _dragging != e.id && MediaQuery.maybeDisableAnimationsOf(context) != true;
    Widget shown = wiggling
        ? AnimatedBuilder(
            animation: widget.wiggle,
            child: child,
            builder: (_, c) => Transform.rotate(
              angle: widget.wiggle.isAnimating ? math.sin(widget.wiggle.value * 2 * math.pi + phase) * 0.014 : 0,
              child: c,
            ),
          )
        : child;
    final target = DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        if (d.data != e.id) {
          HapticFeedback.selectionClick();
          widget.onMove(d.data, e.id);
        }
        return true;
      },
      builder: (_, _, _) => shown,
    );
    return LongPressDraggable<String>(
      key: ValueKey('home-drag-${e.id}'),
      data: e.id,
      // One delay for both modes: Draggable keeps the recognizer it was built with.
      delay: const Duration(milliseconds: 380),
      hapticFeedbackOnStart: true,
      maxSimultaneousDrags: 1,
      onDragStarted: () {
        setState(() => _dragging = e.id);
        if (!widget.editing) widget.onStartEditing();
      },
      onDragUpdate: (d) => widget.onDragUpdate?.call(d.globalPosition),
      onDragEnd: (_) {
        setState(() => _dragging = null);
        widget.onDragEnd?.call();
      },
      onDraggableCanceled: (_, _) {
        if (mounted) setState(() => _dragging = null);
        widget.onDragEnd?.call();
      },
      feedback: _Feedback(info: info, width: width, height: _heightOf(e.id)),
      childWhenDragging: _Ghost(height: _heightOf(e.id)),
      child: target,
    );
  }

  double _heightOf(String id) {
    final box = _keys[id]?.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) return math.max(64, math.min(box.size.height, 360));
    return 120;
  }
}

/// Keeps a built Home row alive once it has been on screen: scrolling back does not rebuild
/// it (or make its box load again).
class _KeepAliveRow extends StatefulWidget {
  const _KeepAliveRow({super.key, required this.child});
  final Widget child;

  @override
  State<_KeepAliveRow> createState() => _KeepAliveRowState();
}

class _KeepAliveRowState extends State<_KeepAliveRow> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Lifted copy under the finger: same size, scaled a little, soft shadow.
class _Feedback extends StatelessWidget {
  const _Feedback({required this.info, required this.width, required this.height});
  final HomeWidgetInfo info;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Transform.scale(
      scale: 1.04,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Color.alphaBlend(info.color.withValues(alpha: 0.10), cs.surface),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: info.color.withValues(alpha: 0.35)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 28, offset: const Offset(0, 12))],
          ),
          child: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(info.icon, color: info.color),
              const SizedBox(width: 8),
              Flexible(child: Text(tr(info.title), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Ghost extends StatelessWidget {
  const _Ghost({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.primary.withValues(alpha: 0.35), width: 1.5),
      ),
    );
  }
}

/// Edit-mode chrome around a widget: name, ⊖, ½ / full, drag hint.
class _EditFrame extends StatelessWidget {
  const _EditFrame({required this.entry, required this.content, required this.onHide, required this.onResize});
  final HomeEntry entry;
  final Widget? content;
  final ValueChanged<String> onHide;
  final ValueChanged<String> onResize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final info = HomeWidgetInfo.of(entry.id);
    final chart = HomeLayout.isChart(entry.id);
    Widget? body = content;
    // Classic sections start with their own gap; inside the frame it is noise.
    if (!chart && body is Column && body.children.isNotEmpty && body.children.first is SizedBox) {
      final rest = body.children.skip(1).toList();
      body = rest.isEmpty ? null : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rest);
    }
    return Stack(clipBehavior: Clip.none, children: [
      // Taps on a widget in edit mode do nothing (and don't count as "outside").
      GestureDetector(
        // Opaque: the content ignores touches, so the frame itself must catch
        // the press that starts a drag.
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: chart
            ? IgnorePointer(child: body ?? const SizedBox(height: 80))
            : Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: info.color.withValues(alpha: 0.30)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(NxI.dotsSixVertical, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Icon(info.icon, size: 16, color: info.color),
                    const SizedBox(width: 6),
                    Expanded(child: Text(tr(info.title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                  ]),
                  if (body == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 20),
                      child: Text(tr('ยังไม่มีข้อมูลให้แสดงตอนนี้ — แสดงเมื่อมีข้อมูล'),
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ClipRect(child: IgnorePointer(child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: body))),
                    ),
                ]),
              ),
      ),
      Positioned(
        left: -6,
        top: -6,
        child: _RoundBtn(
          key: ValueKey('home-hide-${entry.id}'),
          tooltip: tr('ซ่อน'),
          icon: NxI.circleMinus,
          color: const Color(0xFFEF4444),
          onTap: () {
            HapticFeedback.mediumImpact();
            onHide(entry.id);
          },
        ),
      ),
      if (HomeLayout.resizable(entry.id))
        Positioned(
          right: -6,
          top: -6,
          child: _RoundBtn(
            key: ValueKey('home-size-${entry.id}'),
            tooltip: tr(entry.size == HomeSize.half ? 'ขยายเต็มแถว' : 'ย่อครึ่งแถว'),
            icon: entry.size == HomeSize.half ? NxI.arrowsLeftRight : NxI.minimize,
            color: cs.primary,
            onTap: () {
              HapticFeedback.selectionClick();
              onResize(entry.id);
            },
          ),
        ),
    ]);
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({super.key, required this.tooltip, required this.icon, required this.color, required this.onTap});
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: CircleBorder(side: BorderSide(color: cs.surface, width: 2)),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 30, height: 30, child: Icon(icon, size: 16, color: Colors.white)),
        ),
      ),
    );
  }
}

/// Bar shown while arranging: ยกเลิก · title · เสร็จ.
class HomeEditBar extends StatelessWidget {
  const HomeEditBar({super.key, required this.onCancel, required this.onDone, required this.onAdd});
  final VoidCallback onCancel;
  final VoidCallback onDone;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.inverseSurface,
      elevation: 6,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(99),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(children: [
          TextButton(
            key: const ValueKey('home-edit-cancel'),
            onPressed: onCancel,
            style: TextButton.styleFrom(foregroundColor: cs.onInverseSurface),
            child: Text(tr('ยกเลิก')),
          ),
          Expanded(
            child: Text(tr('จัดวางหน้าหลัก'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(color: cs.onInverseSurface, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            key: const ValueKey('home-edit-add'),
            tooltip: tr('เพิ่มวิดเจ็ต'),
            onPressed: onAdd,
            icon: Icon(NxI.plus, color: cs.onInverseSurface),
          ),
          FilledButton(
            key: const ValueKey('home-edit-done'),
            onPressed: onDone,
            style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary, visualDensity: VisualDensity.compact),
            child: Text(tr('เสร็จ')),
          ),
        ]),
      ),
    );
  }
}

/// "+ เพิ่มวิดเจ็ต" card at the end of the page in edit mode.
class HomeAddWidgetCard extends StatelessWidget {
  const HomeAddWidgetCard({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: InkWell(
        key: const ValueKey('home-add-widget'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.primary.withValues(alpha: 0.45), width: 1.5),
            color: cs.primary.withValues(alpha: 0.05),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(NxI.plus, color: cs.primary),
            const SizedBox(width: 8),
            Text(tr('เพิ่มวิดเจ็ต'), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

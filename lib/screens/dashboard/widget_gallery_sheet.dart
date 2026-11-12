import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/home_layout.dart';
import '../../core/i18n.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_sliding_segmented.dart';
import '../../widgets/nx_surface_card.dart';
import 'home_charts.dart';
import 'home_widgets.dart';

/// "เพิ่มวิดเจ็ต": widgets the user may see (menu permissions), filtered by
/// ทั้งหมด | ยังไม่เพิ่ม | เพิ่มแล้ว and grouped; charts show a small preview.
/// Returns the entry to add (null = closed).
Future<HomeEntry?> showWidgetGallery(BuildContext context, {required Set<String> onPage}) {
  return showNxSnapSheet<HomeEntry>(
    context: context,
    title: tr('เพิ่มวิดเจ็ต'),
    snaps: const [0.7, 0.92],
    builder: (ctx, controller) => _Gallery(controller: controller, onPage: onPage),
  );
}

enum _GalleryFilter { all, notAdded, added }

class _Gallery extends StatefulWidget {
  const _Gallery({required this.controller, required this.onPage});
  final ScrollController controller;
  final Set<String> onPage;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  _GalleryFilter _filter = _GalleryFilter.all;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final session = context.read<AppConfig>().session;
    // Only widgets about menus this user can open.
    final ids = [
      ...HomeLayout.charts.map((c) => c.id),
      ...HomeLayout.defaultOrder,
    ].where((id) => homeWidgetAllowed(session, id)).where((id) => switch (_filter) {
          _GalleryFilter.all => true,
          _GalleryFilter.notAdded => !widget.onPage.contains(id),
          _GalleryFilter.added => widget.onPage.contains(id),
        });
    final byGroup = <String, List<HomeWidgetInfo>>{};
    for (final id in ids) {
      final info = HomeWidgetInfo.of(id);
      (byGroup[info.group] ??= []).add(info);
    }
    return ListView(
      key: const ValueKey('widget-gallery'),
      controller: widget.controller,
      padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.paddingOf(context).bottom + 24),
      children: [
        KeyedSubtree(
          key: const ValueKey('gallery-filter'),
          child: NxSlidingSegmented<_GalleryFilter>(
            value: _filter,
            options: const [
              (_GalleryFilter.all, 'ทั้งหมด', null),
              (_GalleryFilter.notAdded, 'ยังไม่เพิ่ม', null),
              (_GalleryFilter.added, 'เพิ่มแล้ว', null),
            ],
            onChanged: (f) => setState(() => _filter = f),
          ),
        ),
        const SizedBox(height: 10),
        Text(tr('แตะ "เพิ่ม" แล้ววิดเจ็ตจะไปอยู่ท้ายหน้าหลัก ลากเพื่อจัดตำแหน่งได้'),
            maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        if (byGroup.isEmpty)
          Padding(
            key: const ValueKey('gallery-empty'),
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text(
              tr(_filter == _GalleryFilter.added ? 'ยังไม่ได้เพิ่มวิดเจ็ต' : 'เพิ่มครบทุกวิดเจ็ตแล้ว'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        for (final (g, label) in kHomeWidgetGroups)
          if (byGroup[g] != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
              child: Text(tr(label), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ),
            for (final info in byGroup[g]!) _GalleryTile(key: ValueKey('gallery-${info.id}'), info: info, added: widget.onPage.contains(info.id)),
          ],
      ],
    );
  }
}

class _GalleryTile extends StatefulWidget {
  const _GalleryTile({super.key, required this.info, required this.added});
  final HomeWidgetInfo info;
  final bool added;

  @override
  State<_GalleryTile> createState() => _GalleryTileState();
}

class _GalleryTileState extends State<_GalleryTile> {
  late HomeSize _size = HomeLayout.defaultSizeOf(widget.info.id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final info = widget.info;
    final added = widget.added;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NxSurfaceCard(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: info.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(info.icon, size: 20, color: info.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Flexible(
                    child: Text(tr(info.title), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (info.isChart) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: info.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                      child: Text(tr('กราฟ'), style: TextStyle(fontSize: 10.5, color: info.color, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(tr(info.hint),
                    key: ValueKey('gallery-hint-${info.id}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(width: 8),
            added
                ? Container(
                    key: ValueKey('gallery-added-${info.id}'),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(99)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(NxI.check, size: 14, color: cs.primary),
                      const SizedBox(width: 4),
                      Text(tr('เพิ่มแล้ว'), style: theme.textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
                    ]),
                  )
                : FilledButton.icon(
                    key: ValueKey('gallery-add-${info.id}'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context, HomeEntry(info.id, size: info.isChart ? _size : HomeSize.full));
                    },
                    icon: const Icon(NxI.plus, size: 16),
                    label: Text(tr('เพิ่ม')),
                  ),
          ]),
          // Charts not on the page yet: a small live preview and the size choice.
          if (info.isChart && !added) ...[
            const SizedBox(height: 10),
            IgnorePointer(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: _size == HomeSize.half ? 0.5 : 1,
                  child: HomeChartCard(entry: HomeEntry(info.id, size: _size), sample: sampleChartData(info.id)),
                ),
              ),
            ),
            if (info.resizable) ...[
              const SizedBox(height: 8),
              Row(children: [
                Text(tr('ขนาด'), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                const Spacer(),
                SegmentedButton<HomeSize>(
                  key: ValueKey('gallery-size-${info.id}'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  segments: [
                    ButtonSegment(value: HomeSize.half, label: Text(tr('½'))),
                    ButtonSegment(value: HomeSize.full, label: Text(tr('เต็ม'))),
                  ],
                  selected: {_size},
                  onSelectionChanged: (s) => setState(() => _size = s.first),
                ),
              ]),
            ],
          ],
        ]),
      ),
    );
  }
}

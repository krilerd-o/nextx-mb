import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/home_layout.dart';
import '../../core/i18n.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import 'home_charts.dart';
import 'home_widgets.dart';

/// "เพิ่มวิดเจ็ต": widgets the user may add, grouped, each with a preview.
/// Returns the entry to add (null = closed).
Future<HomeEntry?> showWidgetGallery(BuildContext context, {required Set<String> onPage}) {
  return showNxSnapSheet<HomeEntry>(
    context: context,
    title: tr('เพิ่มวิดเจ็ต'),
    snaps: const [0.7, 0.92],
    builder: (ctx, controller) => _Gallery(controller: controller, onPage: onPage),
  );
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.controller, required this.onPage});
  final ScrollController controller;
  final Set<String> onPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final session = context.read<AppConfig>().session;
    final ids = [
      ...HomeLayout.charts.map((c) => c.id),
      ...HomeLayout.defaultOrder,
    ].where((id) => homeWidgetAllowed(session, id)).toList();
    final byGroup = <String, List<HomeWidgetInfo>>{};
    for (final id in ids) {
      final info = HomeWidgetInfo.of(id);
      (byGroup[info.group] ??= []).add(info);
    }
    return ListView(
      key: const ValueKey('widget-gallery'),
      controller: controller,
      padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.paddingOf(context).bottom + 24),
      children: [
        Text(tr('แตะ "เพิ่ม" แล้ววิดเจ็ตจะไปอยู่ท้ายหน้าหลัก ลากเพื่อจัดตำแหน่งได้'),
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        for (final (g, label) in kHomeWidgetGroups)
          if (byGroup[g] != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
              child: Text(tr(label), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ),
            for (final info in byGroup[g]!) _GalleryTile(info: info, added: onPage.contains(info.id)),
          ],
      ],
    );
  }
}

class _GalleryTile extends StatefulWidget {
  const _GalleryTile({required this.info, required this.added});
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
    return Container(
      key: ValueKey('gallery-${info.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (info.isChart)
          IgnorePointer(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: _size == HomeSize.half ? 0.56 : 1,
                child: HomeChartCard(
                  entry: HomeEntry(info.id, size: _size),
                  sample: sampleChartData(info.id),
                ),
              ),
            ),
          )
        else
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: info.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
              child: Icon(info.icon, color: info.color),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(tr(info.title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text(tr(info.hint), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
          if (info.resizable && !widget.added) ...[
            const SizedBox(width: 8),
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
          ],
          const SizedBox(width: 8),
          widget.added
              ? Chip(
                  avatar: Icon(NxI.check, size: 14, color: cs.primary),
                  label: Text(tr('เพิ่มแล้ว')),
                  visualDensity: VisualDensity.compact,
                )
              : FilledButton.icon(
                  key: ValueKey('gallery-add-${info.id}'),
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context, HomeEntry(info.id, size: info.isChart ? _size : HomeSize.full));
                  },
                  icon: const Icon(NxI.plus, size: 16),
                  label: Text(tr('เพิ่ม')),
                ),
        ]),
      ]),
    );
  }
}

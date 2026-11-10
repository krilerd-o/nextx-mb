import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/home_layout.dart';
import '../../core/i18n.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import 'home_chart_data.dart';
import 'home_widgets.dart';
import 'widget_gallery_sheet.dart';

/// "ปรับแต่งหน้าหลัก" (Settings and Home): reorder, remove and add widgets,
/// chart size / period / ของฉัน-ทีม. Same [HomeLayout] as Home's edit mode.
class HomeLayoutEditorScreen extends StatefulWidget {
  const HomeLayoutEditorScreen({super.key});

  @override
  State<HomeLayoutEditorScreen> createState() => _HomeLayoutEditorScreenState();
}

class _HomeLayoutEditorScreenState extends State<HomeLayoutEditorScreen> {
  late List<HomeEntry> _entries = List.of(HomeLayout.instance.entries);

  @override
  void initState() {
    super.initState();
    final config = context.read<AppConfig>();
    HomeLayout.instance.load(config.businessScope, legacyScope: config.prefsScope).then((_) {
      if (mounted) setState(() => _entries = List.of(HomeLayout.instance.entries));
    });
  }

  void _move(int i, int d) {
    final j = i + d;
    if (j < 0 || j >= _entries.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      final e = _entries.removeAt(i);
      _entries.insert(j, e);
    });
  }

  Future<void> _add() async {
    final e = await showWidgetGallery(context, onPage: {for (final x in _entries) x.id});
    if (e != null && mounted) setState(() => _entries = [..._entries.where((x) => x.id != e.id), e]);
  }

  Future<void> _chartOptions(int i) async {
    final e = _entries[i];
    final meta = HomeLayout.chartMeta(e.id)!;
    final team = meta.teamable && canSeeTeam(context.read<AppConfig>().session);
    final next = await showAppBottomSheet<HomeEntry>(
      context: context,
      title: tr(meta.title),
      child: _ChartOptions(entry: e, meta: meta, team: team),
    );
    if (next != null && mounted) setState(() => _entries[i] = next);
  }

  String _summary(HomeEntry e) {
    final meta = HomeLayout.chartMeta(e.id);
    if (meta == null) return tr(HomeLayout.sections[e.id]?.$2 ?? '');
    return [
      tr(e.size == HomeSize.half ? 'ครึ่งแถว' : 'เต็มแถว'),
      if (meta.periods.isNotEmpty) tr(kChartPeriodLabels[e.period ?? meta.defaultPeriod] ?? ''),
      if (meta.teamable) tr(e.team ? 'ทีม' : 'ของฉัน'),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final session = context.select((AppConfig c) => c.session);
    return Scaffold(
      appBar: const NxAppHeader(title: 'ปรับแต่งหน้าหลัก', subtitle: 'ลากเพื่อเรียง เพิ่มหรือเอาวิดเจ็ตออก'),
      body: Column(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              key: const ValueKey('home-editor-list'),
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: _entries.length,
              footer: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OutlinedButton.icon(
                  key: const ValueKey('home-editor-add'),
                  onPressed: _add,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
                  icon: const Icon(NxI.plus, size: 18),
                  label: Text(tr('เพิ่มวิดเจ็ต')),
                ),
              ),
              onReorder: (a, b) {
                HapticFeedback.selectionClick();
                setState(() {
                  if (b > a) b -= 1;
                  final e = _entries.removeAt(a);
                  _entries.insert(b, e);
                });
              },
              proxyDecorator: (child, _, anim) => AnimatedBuilder(
                animation: anim,
                builder: (_, c) => Transform.scale(
                  scale: 1 + 0.03 * anim.value,
                  child: Material(elevation: 6 * anim.value, borderRadius: BorderRadius.circular(18), child: c),
                ),
                child: child,
              ),
              itemBuilder: (context, i) {
                final e = _entries[i];
                final info = HomeWidgetInfo.of(e.id);
                final allowed = homeWidgetAllowed(session, e.id);
                return Padding(
                  key: ValueKey('editor-${e.id}'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                  color: cs.surfaceContainerHighest.withValues(alpha: allowed ? 0.6 : 0.3),
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.only(left: 6, right: 4),
                    onTap: info.isChart ? () => _chartOptions(i) : null,
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: Padding(padding: const EdgeInsets.all(8), child: Icon(NxI.dotsSixVertical, color: cs.onSurfaceVariant)),
                    ),
                    title: Row(children: [
                      Icon(info.icon, size: 18, color: allowed ? info.color : cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Flexible(child: Text(tr(info.title), style: theme.textTheme.titleSmall)),
                      if (info.isChart) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: info.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                          child: Text(tr('กราฟ'), style: TextStyle(fontSize: 10.5, color: info.color, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ]),
                    subtitle: Text(allowed ? _summary(e) : tr('ไม่มีสิทธิ์ดูข้อมูลนี้ — จะไม่แสดงบนหน้าหลัก'),
                        style: theme.textTheme.bodySmall),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: tr('ขึ้น'),
                        visualDensity: VisualDensity.compact,
                        onPressed: i == 0 ? null : () => _move(i, -1),
                        icon: const Icon(NxI.caretUp, size: 18),
                      ),
                      IconButton(
                        tooltip: tr('ลง'),
                        visualDensity: VisualDensity.compact,
                        onPressed: i == _entries.length - 1 ? null : () => _move(i, 1),
                        icon: const Icon(NxI.caretDown, size: 18),
                      ),
                      IconButton(
                        key: ValueKey('editor-remove-${e.id}'),
                        tooltip: tr('เอาออก'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _entries.removeAt(i)),
                        icon: const Icon(NxI.circleMinus, size: 20, color: Color(0xFFEF4444)),
                      ),
                    ]),
                  ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('home-editor-reset'),
                    onPressed: () => setState(() => _entries = HomeLayout.defaultEntries()),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
                    child: Text(tr('ค่าเริ่มต้น')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const ValueKey('home-editor-save'),
                    onPressed: () async {
                      await HomeLayout.instance.saveEntries(context.read<AppConfig>().businessScope, _entries);
                      if (context.mounted) Navigator.pop(context, true);
                    },
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
                    child: Text(tr('บันทึก')),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Size, default period and ของฉัน | ทีม of one chart.
class _ChartOptions extends StatefulWidget {
  const _ChartOptions({required this.entry, required this.meta, required this.team});
  final HomeEntry entry;
  final HomeChartMeta meta;
  final bool team;

  @override
  State<_ChartOptions> createState() => _ChartOptionsState();
}

class _ChartOptionsState extends State<_ChartOptions> {
  late HomeEntry _e = widget.entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Text(tr(t), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        );
    final meta = widget.meta;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (meta.resizable) ...[
        label('ขนาด'),
        SegmentedButton<HomeSize>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: HomeSize.half, label: Text(tr('ครึ่งแถว'))),
            ButtonSegment(value: HomeSize.full, label: Text(tr('เต็มแถว'))),
          ],
          selected: {_e.size},
          onSelectionChanged: (s) => setState(() => _e = _e.copyWith(size: s.first)),
        ),
      ],
      if (meta.periods.isNotEmpty) ...[
        label('ช่วงเวลาเริ่มต้น'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in meta.periods)
            ChoiceChip(
              key: ValueKey('opt-period-$p'),
              label: Text(tr(kChartPeriodLabels[p] ?? p)),
              selected: (_e.period ?? meta.defaultPeriod) == p,
              onSelected: (_) => setState(() => _e = _e.copyWith(period: p)),
            ),
        ]),
      ],
      if (widget.team) ...[
        label('ข้อมูลของ'),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: false, label: Text(tr('ของฉัน'))),
            ButtonSegment(value: true, label: Text(tr('ทีม'))),
          ],
          selected: {_e.team},
          onSelectionChanged: (s) => setState(() => _e = _e.copyWith(team: s.first)),
        ),
      ],
      const SizedBox(height: 20),
      FilledButton(
        key: const ValueKey('opt-apply'),
        onPressed: () => Navigator.pop(context, _e),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
        child: Text(tr('ใช้ค่านี้')),
      ),
    ]);
  }
}

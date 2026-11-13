import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/home_layout.dart';
import '../../core/i18n.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_surface_card.dart';
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
  /// Widgets this user may see, in order (what the list edits).
  List<HomeEntry> _entries = const [];

  /// Saved widgets the user has no permission for: never listed, but kept in
  /// the saved layout (with the ids that came before them) so they come back
  /// in place when the permission does.
  List<(List<String>, HomeEntry)> _kept = const [];

  /// Permissions the list was split with (menus may still be loading when the page opens).
  Object? _splitFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Menus arrived (or changed) after opening: split again, keeping the user's order.
    final s = context.watch<AppConfig>().session;
    final now = (s.menusLoaded, s.menuKeys, s.isSuperadmin);
    if (_splitFor != null && _splitFor != now) _split(_merged());
  }

  void _split(List<HomeEntry> all) {
    final session = context.read<AppConfig>().session;
    _splitFor = (session.menusLoaded, session.menuKeys, session.isSuperadmin);
    final shown = <HomeEntry>[];
    final kept = <(List<String>, HomeEntry)>[];
    for (var i = 0; i < all.length; i++) {
      if (homeWidgetAllowed(session, all[i].id)) {
        shown.add(all[i]);
      } else {
        kept.add(([for (var j = i - 1; j >= 0; j--) all[j].id], all[i]));
      }
    }
    _entries = shown;
    _kept = kept;
  }

  /// [_entries] with the hidden ones put back right after the nearest widget
  /// that preceded them (new widgets still go last).
  List<HomeEntry> _merged() {
    final out = List.of(_entries);
    for (final (before, e) in _kept) {
      if (out.any((x) => x.id == e.id)) continue;
      var at = 0;
      for (final id in before) {
        final k = out.indexWhere((x) => x.id == id);
        if (k >= 0) {
          at = k + 1;
          break;
        }
      }
      out.insert(at, e);
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _split(HomeLayout.instance.entries);
    final config = context.read<AppConfig>();
    HomeLayout.instance.load(config.businessScope, legacyScope: config.prefsScope).then((_) {
      if (mounted) setState(() => _split(HomeLayout.instance.entries));
    });
  }

  void _moveTo(int i, int j) {
    if (j < 0 || j >= _entries.length || j == i) return;
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
              header: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                child: Row(children: [
                  Text(tr('วิดเจ็ตบนหน้าหลัก'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(99)),
                    child: Text('${_entries.length}', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                  ),
                ]),
              ),
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
              onReorderItem: (a, b) {
                HapticFeedback.selectionClick();
                setState(() {
                  final e = _entries.removeAt(a);
                  _entries.insert(b, e);
                });
              },
              proxyDecorator: (child, _, anim) => AnimatedBuilder(
                animation: anim,
                builder: (_, c) => Transform.scale(
                  scale: 1 + 0.03 * anim.value,
                  child: Material(color: Colors.transparent, elevation: 6 * anim.value, borderRadius: BorderRadius.circular(18), child: c),
                ),
                child: child,
              ),
              itemBuilder: (context, i) {
                final e = _entries[i];
                return _EditorRow(
                  key: ValueKey('editor-${e.id}'),
                  index: i,
                  count: _entries.length,
                  entry: e,
                  summary: _summary(e),
                  onTap: HomeWidgetInfo.of(e.id).isChart ? () => _chartOptions(i) : null,
                  onMove: (to) => _moveTo(i, to),
                  onRemove: () => setState(() => _entries.removeAt(i)),
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
                    onPressed: () => setState(() => _split(HomeLayout.defaultEntries())),
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
                      await HomeLayout.instance.saveEntries(context.read<AppConfig>().businessScope, _merged());
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

enum _MoveAction { top, up, down, bottom }

/// One widget on the page: grip, tinted icon, title (+ กราฟ), one-line
/// summary, then ⋮ (move / chart options) and remove.
class _EditorRow extends StatelessWidget {
  const _EditorRow({
    super.key,
    required this.index,
    required this.count,
    required this.entry,
    required this.summary,
    required this.onTap,
    required this.onMove,
    required this.onRemove,
  });

  final int index;
  final int count;
  final HomeEntry entry;
  final String summary;
  final VoidCallback? onTap;
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final info = HomeWidgetInfo.of(entry.id);
    final tint = info.color;
    final first = index == 0;
    final last = index == count - 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NxSurfaceCard(
        radius: 18,
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
        child: Row(children: [
          ReorderableDragStartListener(
            key: ValueKey('editor-grip-${entry.id}'),
            index: index,
            child: Padding(padding: const EdgeInsets.all(8), child: Icon(NxI.dotsSixVertical, size: 20, color: cs.onSurfaceVariant)),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(info.icon, size: 20, color: tint),
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
              Text(
                summary,
                key: ValueKey('editor-summary-${entry.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ]),
          ),
          PopupMenuButton<Object>(
            key: ValueKey('editor-menu-${entry.id}'),
            tooltip: tr('ตัวเลือก'),
            icon: Icon(NxI.dotsThreeVertical, size: 20, color: cs.onSurfaceVariant),
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelected: (v) {
              switch (v) {
                case _MoveAction.top:
                  onMove(0);
                case _MoveAction.up:
                  onMove(index - 1);
                case _MoveAction.down:
                  onMove(index + 1);
                case _MoveAction.bottom:
                  onMove(count - 1);
                case 'options':
                  onTap?.call();
              }
            },
            itemBuilder: (_) => [
              if (onTap != null) ...[
                _menuItem('options', NxI.gear, 'ตั้งค่ากราฟ'),
                const PopupMenuDivider(),
              ],
              _menuItem(_MoveAction.top, NxI.chevronsUp, 'ย้ายไปบนสุด', enabled: !first),
              _menuItem(_MoveAction.up, NxI.caretUp, 'ย้ายขึ้น', enabled: !first),
              _menuItem(_MoveAction.down, NxI.caretDown, 'ย้ายลง', enabled: !last),
              _menuItem(_MoveAction.bottom, NxI.chevronsDown, 'ย้ายไปล่างสุด', enabled: !last),
            ],
          ),
          IconButton(
            key: ValueKey('editor-remove-${entry.id}'),
            tooltip: tr('เอาออก'),
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(NxI.circleMinus, size: 20, color: Color(0xFFEF4444)),
          ),
        ]),
      ),
    );
  }

  PopupMenuItem<Object> _menuItem(Object value, IconData icon, String label, {bool enabled = true}) => PopupMenuItem<Object>(
        key: ValueKey('editor-menu-$value-${entry.id}'),
        value: value,
        enabled: enabled,
        height: 44,
        child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 12), Text(tr(label))]),
      );
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

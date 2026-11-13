import '../../core/nx_number.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../widgets/nx_skeleton.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_config.dart';
import '../../core/app_theme.dart' show NxAtmosphereTokens;
import '../../core/effects.dart';
import '../../core/entity_modules.dart';
import '../../core/i18n.dart';
import '../../core/menu_access.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/recent_records.dart';
import '../../core/thai_time.dart';
import '../../core/workspace_models.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_icons.dart';
import '../notifications/notification_center_screen.dart' show relativeTime;
import 'team_overview_card.dart' show compactBaht, salesFigures;

// ─────────────────────────── shared helpers ───────────────────────────

/// Workspace types shown in "งานค้าง" / "งานของฉัน": real work only
/// (no Epic, no Checklist; Smart Checklists live inside a task).
const kWorkTypes = {'task', 'subtask', 'bug', 'story'};

bool isWorkType(Map<String, dynamic> item) {
  if (item['row_kind'] == 'epic' || item['item_type'] == 'epic' || item['_kind'] == 'epic') return false;
  final t = '${item['type'] ?? 'task'}'.toLowerCase();
  return kWorkTypes.contains(t);
}

String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Small per-user UI memory (collapsed boxes, chosen period).
class HomePrefs {
  static String _k(BuildContext c, String key) => 'nx_home_${context2scope(c)}_$key';
  static String context2scope(BuildContext c) => c.read<AppConfig>().prefsScope;

  static Future<String?> get(BuildContext c, String key) async {
    final k = _k(c, key);
    try {
      return (await SharedPreferences.getInstance()).getString(k);
    } catch (_) {
      return null;
    }
  }

  static Future<void> set(BuildContext c, String key, String value) async {
    final k = _k(c, key);
    try {
      await (await SharedPreferences.getInstance()).setString(k, value);
    } catch (_) {}
  }
}

// ─────────────────────────── one card style ───────────────────────────

/// Corner radius of every Home card.
const double kHomeCardRadius = 24;

/// Soft, wide shadow of the Home cards (dark mode: a deeper, tighter one). Always painted outside
/// any clip (see [HomeCardShadow]) so it is never cut into a flat band.
List<BoxShadow> homeCardShadows(bool dark) => dark
    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.34), offset: const Offset(0, 8), blurRadius: 22, spreadRadius: -4)]
    : const [
        BoxShadow(color: Color(0x0A0F172A), offset: Offset(0, 1), blurRadius: 2),
        BoxShadow(color: Color(0x120F172A), offset: Offset(0, 12), blurRadius: 30, spreadRadius: -8),
      ];

/// The one Home card look — frosted glass: a milky, slightly translucent fill that is brighter at
/// the top, a light rim catching the light, 24 radius and the soft shadow.
BoxDecoration homeCardDecoration(BuildContext context, {double radius = kHomeCardRadius}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final base = NxAtmosphereTokens.of(context).cardElevated;
  return BoxDecoration(
    color: base.withValues(alpha: dark ? 0.72 : 0.80),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: dark
          ? [Color.lerp(base, Colors.white, 0.07)!.withValues(alpha: 0.86), base.withValues(alpha: 0.70)]
          : [Colors.white.withValues(alpha: 0.94), Colors.white.withValues(alpha: 0.72)],
    ),
    borderRadius: BorderRadius.circular(radius),
    boxShadow: homeCardShadows(dark),
    border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.09 : 0.85), width: dark ? 1 : 1.2),
  );
}

/// [homeCardDecoration] without its shadow, for an [Ink] inside a Material (ink is clipped to
/// the Material's rectangle, so its shadow would show as a flat band). Pair with [HomeCardShadow].
BoxDecoration homeCardFill(BuildContext context, {double radius = kHomeCardRadius}) =>
    homeCardDecoration(context, radius: radius).copyWith(boxShadow: const []);

/// Paints the Home card shadow outside a tappable (Material + Ink) card. With [frost] the card
/// also blurs what is behind it (only the blur is clipped to the card; the shadow stays outside).
class HomeCardShadow extends StatelessWidget {
  const HomeCardShadow({super.key, required this.child, this.radius = kHomeCardRadius, this.frost = false});
  final Widget child;
  final double radius;
  final bool frost;

  @override
  Widget build(BuildContext context) {
    var body = child;
    if (frost && Effects.of(context) != EffectsLevel.off) {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: body),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: homeCardShadows(Theme.of(context).brightness == Brightness.dark),
      ),
      child: body,
    );
  }
}

/// Header row of a home box: icon, title, count badge, collapse arrow.
class HomeBoxHeader extends StatelessWidget {
  const HomeBoxHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    this.count,
    this.collapsed = false,
    this.onToggle,
  });

  final IconData icon;
  final String title;
  final Color color;
  final int? count;
  final bool collapsed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onToggle == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onToggle!();
            },
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(tr(title), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          if (count != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
              child: Text(nxInt(count), style: theme.textTheme.labelLarge?.copyWith(color: Colors.white)),
            ),
          if (onToggle != null) ...[
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(NxI.caretDown, size: 18, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Box frame used by the home cards: the shared [homeCardDecoration]; [color]
/// is the box's accent (its header icon carries it).
class HomeBoxFrame extends StatelessWidget {
  const HomeBoxFrame({super.key, required this.color, required this.child, this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 12)});
  final Color color;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: homeCardDecoration(context),
      child: child,
    );
  }
}

/// One-line chip row (single choice).
class HomeChips<T> extends StatelessWidget {
  const HomeChips({super.key, required this.options, required this.value, required this.onChanged, this.keyPrefix = 'chip'});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final (v, label) in options)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              key: ValueKey('$keyPrefix-$v'),
              label: Text(tr(label)),
              selected: v == value,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              labelStyle: TextStyle(color: v == value ? Colors.white : null, fontWeight: FontWeight.w600),
              onSelected: (_) {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
            ),
          ),
      ]),
    );
  }
}

// ─────────────────────────── periods ───────────────────────────

enum NxPeriod { today, week, month, quarter, year }

const kPeriodLabels = <(NxPeriod, String)>[
  (NxPeriod.today, 'วันนี้'),
  (NxPeriod.week, 'สัปดาห์นี้'),
  (NxPeriod.month, 'เดือนนี้'),
  (NxPeriod.quarter, 'ไตรมาสนี้'),
  (NxPeriod.year, 'ปีนี้'),
];

/// Thai calendar range of [p] that contains [now] (week = Monday–Sunday).
(DateTime, DateTime) periodRange(NxPeriod p, DateTime now) {
  final d = DateTime(now.year, now.month, now.day);
  switch (p) {
    case NxPeriod.today:
      return (d, d);
    case NxPeriod.week:
      final mon = d.subtract(Duration(days: d.weekday - 1));
      return (mon, mon.add(const Duration(days: 6)));
    case NxPeriod.month:
      return (DateTime(d.year, d.month, 1), DateTime(d.year, d.month + 1, 0));
    case NxPeriod.quarter:
      final q0 = ((d.month - 1) ~/ 3) * 3 + 1;
      return (DateTime(d.year, q0, 1), DateTime(d.year, q0 + 3, 0));
    case NxPeriod.year:
      return (DateTime(d.year, 1, 1), DateTime(d.year, 12, 31));
  }
}

NxPeriod _periodFrom(String? s, NxPeriod fallback) =>
    NxPeriod.values.firstWhere((e) => e.name == s, orElse: () => fallback);

// ─────────────────────────── งานของฉัน ───────────────────────────

enum MyWorkRange { yesterday, today, tomorrow, week }

const kMyWorkLabels = <(MyWorkRange, String)>[
  (MyWorkRange.yesterday, 'เมื่อวาน'),
  (MyWorkRange.today, 'วันนี้'),
  (MyWorkRange.tomorrow, 'พรุ่งนี้'),
  (MyWorkRange.week, 'สัปดาห์นี้'),
];

(DateTime, DateTime) myWorkRange(MyWorkRange r, DateTime now) {
  final d = DateTime(now.year, now.month, now.day);
  return switch (r) {
    MyWorkRange.yesterday => (d.subtract(const Duration(days: 1)), d.subtract(const Duration(days: 1))),
    MyWorkRange.today => (d, d),
    MyWorkRange.tomorrow => (d.add(const Duration(days: 1)), d.add(const Duration(days: 1))),
    MyWorkRange.week => periodRange(NxPeriod.week, now),
  };
}

/// "งานของฉัน": my open tasks due in the chosen range (default today).
class MyWorkBox extends StatefulWidget {
  const MyWorkBox({super.key, this.revision = 0});
  final int revision;

  @override
  State<MyWorkBox> createState() => _MyWorkBoxState();
}

class _MyWorkBoxState extends State<MyWorkBox> {
  MyWorkRange _range = MyWorkRange.today;
  List<Map<String, dynamic>>? _items;
  bool _collapsed = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    () async {
      final saved = await HomePrefs.get(context, 'mywork_collapsed');
      if (mounted && saved == '1') setState(() => _collapsed = true);
    }();
    _load();
  }

  @override
  void didUpdateWidget(MyWorkBox old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision) _load();
  }

  Future<void> _load() async {
    final config = context.read<AppConfig>();
    final seq = ++_seq;
    final (from, to) = myWorkRange(_range, thaiNow());
    try {
      final rows = await config.apiClient.getWorkspaceItems(
        assigneeId: config.session.userId,
        dueFrom: ymd(from),
        dueTo: ymd(to),
        types: kWorkTypes.join(','),
        excludeDone: true,
        excludeEpic: true,
        limit: 20,
      );
      if (!mounted || seq != _seq) return;
      setState(() => _items = rows.where(isWorkType).toList());
    } catch (_) {
      if (mounted && seq == _seq) setState(() => _items = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const color = Color(0xFF3B82F6);
    final items = _items;
    return HomeBoxFrame(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeBoxHeader(
            key: const ValueKey('mywork-header'),
            icon: NxI.checkSquare,
            title: 'งานของฉัน',
            color: color,
            count: items?.length,
            collapsed: _collapsed,
            onToggle: () {
              setState(() => _collapsed = !_collapsed);
              HomePrefs.set(context, 'mywork_collapsed', _collapsed ? '1' : '0');
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            alignment: Alignment.topCenter,
            child: _collapsed
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 10),
                      HomeChips<MyWorkRange>(
                        keyPrefix: 'mywork',
                        options: kMyWorkLabels,
                        value: _range,
                        onChanged: (r) {
                          setState(() {
                            _range = r;
                            _items = null;
                          });
                          _load();
                        },
                      ),
                      const SizedBox(height: 4),
                      if (items == null)
                        const Padding(padding: EdgeInsets.fromLTRB(14, 6, 14, 0), child: NxSkeletonBox())
                      else if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(tr('ไม่มีงานในช่วงนี้'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                        )
                      else ...[
                        for (final it in items.take(6)) _WorkLine(item: it),
                        if (items.length > 6)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => context.push(AppRoutes.workspaceHome),
                              child: Text(tr('ดูทั้งหมด ${items.length}')),
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// One compact line: type icon · title · board · status.
class _WorkLine extends StatelessWidget {
  const _WorkLine({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = wsTypeStyle(wsType(item));
    final status = '${item['status_label_th'] ?? item['status_name'] ?? ''}';
    final board = '${item['board_name'] ?? item['board_code'] ?? ''}';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: item['board_id'] == null || item['id'] == null
          ? null
          : () => context.push(AppRoutes.task('${item['board_id']}', '${item['id']}')),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(style.icon, size: 17, color: style.color),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${item['title'] ?? '—'}', style: theme.textTheme.titleSmall),
                  if (board.isNotEmpty)
                    TextSpan(text: '  $board', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (status.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(status, style: theme.textTheme.labelSmall),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── เปิดล่าสุด ───────────────────────────

/// Recently opened records as a swipeable row of small cards.
class RecentStrip extends StatelessWidget {
  const RecentStrip({super.key});

  static Color colorOf(String module) => switch (module) {
        'lead' => const Color(0xFF8B5CF6),
        'deal' => const Color(0xFF10B981),
        'quotation' => const Color(0xFFF59E0B),
        'account' => const Color(0xFF3B82F6),
        'contact' => const Color(0xFF0EA5E9),
        'case' => const Color(0xFFEF4444),
        'activity' => const Color(0xFFEC4899),
        _ => const Color(0xFF64748B),
      };

  static IconData iconOf(String module) => switch (module) {
        'lead' => NxI.users,
        'deal' => NxI.handshake,
        'quotation' => NxI.receipt,
        'account' => NxI.buildings,
        'contact' => NxI.addressBook,
        'case' => NxI.headset,
        'activity' => NxI.calendarBlank,
        'job' => NxI.wrench,
        _ => NxI.note,
      };

  @override
  Widget build(BuildContext context) {
    final session = context.read<AppConfig>().session;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ValueListenableBuilder<List<Map<String, String>>>(
      valueListenable: RecentRecords.instance.items,
      builder: (context, recent, _) {
        final allowed = [
          for (final r in recent)
            if (MenuAccess.allow(session, EntityModules.menuKeyOf(r['module'] ?? ''))) r,
        ].take(10).toList();
        if (allowed.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Text(tr('เปิดล่าสุด'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SizedBox(
              // Room for the cards' soft shadow; grows with the text size.
              height: 112 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4) + 24,
              child: ListView.separated(
                clipBehavior: Clip.none,
                padding: const EdgeInsets.only(bottom: 24),
                scrollDirection: Axis.horizontal,
                itemCount: allowed.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final r = allowed[i];
                  final m = r['module'] ?? '';
                  final c = colorOf(m);
                  return InkWell(
                    key: ValueKey('recent-$i'),
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => context.push(
                      m == 'activity' ? AppRoutes.activity(r['id'] ?? '') : AppRoutes.crmRecord(m, r['id'] ?? ''),
                    ),
                    child: Container(
                      width: 148,
                      padding: const EdgeInsets.all(12),
                      decoration: homeCardDecoration(context, radius: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
                              child: Icon(iconOf(m), size: 15, color: c),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                tr(EntityModules.titleOf(m)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(color: c, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Text(
                              r['title'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(height: 1.25),
                            ),
                          ),
                          if ((r['at'] ?? '').isNotEmpty)
                            Text(
                              tr(relativeTime(r['at'])),
                              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────── ยอดขาย / เคส ───────────────────────────

class _Figure {
  const _Figure(this.label, this.value, {this.color, this.hint});
  final String label;
  final String value;
  final Color? color;
  final String? hint;
}

class _FigureGrid extends StatelessWidget {
  const _FigureGrid({required this.figures});
  final List<_Figure> figures;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 16) / 3;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final f in figures)
            Container(
              width: w,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: (f.color ?? cs.primary).withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: f.color),
                  ),
                  Text(tr(f.label), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall),
                  if (f.hint != null)
                    Text(f.hint!, maxLines: 1, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
        ],
      );
    });
  }
}

/// Shared shell of the sales / case boxes: header, period chips, figures.
class _PeriodBox extends StatefulWidget {
  const _PeriodBox({
    super.key,
    required this.prefKey,
    required this.title,
    required this.icon,
    required this.color,
    required this.fallback,
    required this.load,
    this.onOpen,
    this.revision = 0,
  });

  final String prefKey;
  final String title;
  final IconData icon;
  final Color color;
  final NxPeriod fallback;
  final Future<List<_Figure>> Function(ApiClient api, String from, String to, String? me) load;
  final VoidCallback? onOpen;
  final int revision;

  @override
  State<_PeriodBox> createState() => _PeriodBoxState();
}

class _PeriodBoxState extends State<_PeriodBox> {
  late NxPeriod _period = widget.fallback;
  List<_Figure>? _figs;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    () async {
      final saved = await HomePrefs.get(context, '${widget.prefKey}_period');
      if (!mounted) return;
      _period = _periodFrom(saved, widget.fallback);
      _load();
    }();
  }

  @override
  void didUpdateWidget(_PeriodBox old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision) _load();
  }

  Future<void> _load() async {
    final api = context.read<AppConfig>().apiClient;
    final seq = ++_seq;
    final (from, to) = periodRange(_period, thaiNow());
    try {
      final me = context.read<AppConfig>().session.userId;
      final f = await widget.load(api, ymd(from), ymd(to), (me == null || me.isEmpty) ? null : me);
      if (mounted && seq == _seq) setState(() => _figs = f);
    } catch (_) {
      if (mounted && seq == _seq) setState(() => _figs = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final figs = _figs;
    return HomeBoxFrame(
      color: widget.color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: HomeBoxHeader(icon: widget.icon, title: widget.title, color: widget.color)),
            if (widget.onOpen != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: widget.onOpen,
                icon: Icon(NxI.caretRight, size: 18, color: cs.onSurfaceVariant),
              ),
          ]),
          const SizedBox(height: 10),
          HomeChips<NxPeriod>(
            keyPrefix: widget.prefKey,
            options: kPeriodLabels,
            value: _period,
            onChanged: (p) {
              setState(() {
                _period = p;
                _figs = null;
              });
              HomePrefs.set(context, '${widget.prefKey}_period', p.name);
              _load();
            },
          ),
          const SizedBox(height: 10),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: figs == null
                ? const Padding(padding: EdgeInsets.fromLTRB(12, 4, 12, 0), child: NxSkeletonBox(rows: 2))
                : figs.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(tr('ยังไม่มีข้อมูลในช่วงนี้'), style: TextStyle(color: cs.onSurfaceVariant)),
                      )
                    : _FigureGrid(figures: figs),
          ),
        ],
      ),
    );
  }
}

num _n(Object? v) => num.tryParse('${v ?? ''}') ?? 0;

/// ยอดขาย (default เดือนนี้).
class SalesPeriodBox extends StatelessWidget {
  const SalesPeriodBox({super.key, this.revision = 0, this.onOpen});
  final int revision;
  final VoidCallback? onOpen;

  /// [me] = the signed-in user: the box shows *my* sales, not the whole team.
  static Future<List<_Figure>> loadFigures(ApiClient api, String from, String to, {String? me}) async {
    final data = await api.getSalesDashboard(dateFrom: from, dateTo: to, userId: me);
    return [
      for (final f in salesFigures(data)) _Figure(f.label, f.value, hint: f.hint, color: const Color(0xFF10B981)),
    ];
  }

  @override
  Widget build(BuildContext context) => _PeriodBox(
        key: const ValueKey('home-sales'),
        prefKey: 'sales',
        title: 'ยอดขาย',
        icon: NxI.handshake,
        color: const Color(0xFF10B981),
        fallback: NxPeriod.month,
        load: (api, f, t, me) => loadFigures(api, f, t, me: me),
        onOpen: onOpen,
        revision: revision,
      );
}

/// เคส (default สัปดาห์นี้): ทั้งหมด / เปิด / กำลังดำเนินการ / ปิด / ค้าง / รอปิด + SLA.
class CasePeriodBox extends StatelessWidget {
  const CasePeriodBox({super.key, this.revision = 0, this.onOpen});
  final int revision;
  final VoidCallback? onOpen;

  /// [me] = the signed-in user: only cases this user owns.
  static Future<List<_Figure>> loadFigures(ApiClient api, String from, String to, {String? me}) async {
    try {
      final s = await api.getCaseSummary(dateFrom: from, dateTo: to, owner: me);
      final k = s['kpis'] is Map ? Map<String, dynamic>.from(s['kpis'] as Map) : const <String, dynamic>{};
      final byStatus = <String, num>{
        for (final r in (s['by_status'] as List? ?? const []).whereType<Map>()) '${r['key']}': _n(r['count']),
      };
      final working = (byStatus['in_progress'] ?? 0) + (byStatus['accepted'] ?? 0) + (byStatus['forwarded'] ?? 0);
      String? sla;
      try {
        final p = await api.getCasePerformance(dateFrom: from, dateTo: to, owner: me);
        final pk = p['kpis'] is Map ? p['kpis'] as Map : p;
        if (pk['sla_pct'] != null) sla = '${_n(pk['sla_pct']).round()}%';
      } catch (_) {}
      return [
        _Figure('เคสทั้งหมด', nxInt(k['opened']), color: const Color(0xFF6366F1)),
        _Figure('เคสที่เปิด', nxInt(k['open_now']), color: const Color(0xFF3B82F6)),
        _Figure('กำลังดำเนินการ', nxInt(working), color: const Color(0xFFF59E0B)),
        _Figure('เคสที่ปิด', nxInt(k['closed']), color: const Color(0xFF10B981)),
        _Figure('เคสค้าง', nxInt(k['overdue_now']), color: const Color(0xFFEF4444)),
        _Figure('รอปิด', nxInt(byStatus['waiting'] ?? 0), color: const Color(0xFF8B5CF6)),
        if (sla != null) _Figure('SLA', sla, color: const Color(0xFF0EA5E9)),
      ];
    } on ApiException catch (_) {
      // No service-dashboard menu: counts by status + light SLA summary.
    } on ApiEnvelopeException catch (_) {}
    final d = await api.getCaseDashboard(dateFrom: from, dateTo: to, userId: me);
    final rows = (d['byStatus'] as List? ?? const []).whereType<Map>().toList();
    final total = rows.fold<num>(0, (a, r) => a + _n(r['value']));
    String? sla;
    // The light SLA summary counts the whole team; skip it on a "mine" box.
    if (me == null) try {
      final from0 = DateTime.parse(from);
      final days = thaiNow().difference(from0).inDays + 1;
      final h = await api.getCaseSlaSummary(days: days.clamp(1, 365));
      if (h['compliance_pct'] != null) sla = '${_n(h['compliance_pct']).round()}%';
    } catch (_) {}
    return [
      _Figure('เคสทั้งหมด', nxInt(total), color: const Color(0xFF6366F1)),
      for (final r in rows.take(4)) _Figure('${r['name'] ?? '—'}', nxInt(r['value'])),
      if (sla != null) _Figure('SLA', sla, color: const Color(0xFF0EA5E9)),
    ];
  }

  @override
  Widget build(BuildContext context) => _PeriodBox(
        key: const ValueKey('home-cases'),
        prefKey: 'cases',
        title: 'เคส',
        icon: NxI.headset,
        color: const Color(0xFFEF4444),
        fallback: NxPeriod.week,
        load: (api, f, t, me) => loadFigures(api, f, t, me: me),
        onOpen: onOpen,
        revision: revision,
      );
}

/// ฿ value helper kept for callers formatting amounts.
String bahtShort(Object? v) => compactBaht(v);

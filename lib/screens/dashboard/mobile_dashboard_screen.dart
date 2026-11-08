import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons_500.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/entity_modules.dart';
import '../../core/menu_access.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../services/unread_service.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_workspace_switcher.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_streaming_text.dart';
import '../../core/thai_time.dart';
import '../../core/workspace_models.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import 'home_layout_editor.dart';
import '../../core/home_layout.dart';
import '../../core/recent_records.dart';
import '../../widgets/nx_refresh.dart';
import 'home_birthday_box.dart';
import 'home_boxes.dart';
import '../hr/attendance_punch_sheet.dart';

/// Thai greeting for the hour of day.
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'สวัสดีตอนเช้า';
  if (h < 17) return 'สวัสดีตอนบ่าย';
  return 'สวัสดีตอนเย็น';
}

const _thaiMonths = [
  'ม.ค.',
  'ก.พ.',
  'มี.ค.',
  'เม.ย.',
  'พ.ค.',
  'มิ.ย.',
  'ก.ค.',
  'ส.ค.',
  'ก.ย.',
  'ต.ค.',
  'พ.ย.',
  'ธ.ค.',
];
const _thaiDays = [
  'จันทร์',
  'อังคาร',
  'พุธ',
  'พฤหัสบดี',
  'ศุกร์',
  'เสาร์',
  'อาทิตย์',
];

String thaiLongDate(DateTime d) => L10n.isEn
    ? '${tr(_thaiDays[d.weekday - 1])}, ${d.day} ${tr(_thaiMonths[d.month - 1])} ${d.year}'
    : 'วัน${_thaiDays[d.weekday - 1]}ที่ ${d.day} ${_thaiMonths[d.month - 1]} ${uiYear(d.year)}';

String _hhmm(dynamic raw) {
  final d = parseThai(raw?.toString() ?? '');
  if (d == null) return '';
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Module counts on the home summary that map to an in-app list.
const _statModules = <String, IconData>{
  'lead': NxI.users,
  'deal': NxI.handshake,
  'quotation': NxI.receipt,
  'account': NxI.buildings,
  'contact': NxI.addressBook,
  'case': NxI.headset,
  'job': NxI.wrench,
};

class MobileDashboardScreen extends StatefulWidget {
  const MobileDashboardScreen({super.key});

  @override
  State<MobileDashboardScreen> createState() => _MobileDashboardScreenState();
}

class _MobileDashboardScreenState extends State<MobileDashboardScreen> {
  Map<String, dynamic>? _attendance;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _work;
  int _whatsNew = 0;
  bool _loading = true;
  bool _refreshing = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
    RecentRecords.instance.load(context.read<AppConfig>().prefsScope);
    HomeLayout.instance.load(context.read<AppConfig>().prefsScope);
    HomeLayout.instance.addListener(_onLayout);
  }

  void _onLayout() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    HomeLayout.instance.removeListener(_onLayout);
    super.dispose();
  }

  Future<void> _openHomeEditor() async {
    await nxPush<bool>(context, const HomeLayoutEditorScreen(), root: true);
  }

  /// Overdue appointments (same query as Calendar → ค้าง), newest-due first.
  List<Map<String, dynamic>> _overdue = const [];
  bool _pendingLoaded = false;
  int _overdueTotal = 0;

  /// Overdue Workspace work (Task / Subtask / Bug / Story only — no Epic or Checklist).
  List<Map<String, dynamic>> _overdueWork = const [];

  Future<void> _loadOverdueWork() async {
    final config = context.read<AppConfig>();
    if (!MenuAccess.allow(config.session, MenuAccess.workspace)) return;
    try {
      final r = await config.apiClient.getHomeWork(bucket: 'overdue', limit: 30);
      final items = extractMapList(r['items'] ?? r['work']).where((e) => e['status_is_done'] != true && isWorkType(e)).toList();
      if (mounted) setState(() => _overdueWork = items);
    } catch (_) {}
  }

  Future<void> _loadOverdue() async {
    _loadOverdueWork();
    final config = context.read<AppConfig>();
    if (!MenuAccess.any(config.session, const [MenuAccess.calendar, MenuAccess.pending])) {
      // Workspace-only users still get the (empty or task-only) box.
      if (MenuAccess.allow(config.session, MenuAccess.workspace) && mounted) setState(() => _pendingLoaded = true);
      return;
    }
    try {
      final page = await config.apiClient.getEntityList('activity', limit: 10, extra: const {
        'overdue': '1',
        'sort': 'date_start',
        'order': 'asc',
        'cols': 'id,subject,date_start,date_end,status,activitytype,location,account_name,contact_name,smownerid',
        'with_total': '1',
      });
      if (!mounted) return;
      setState(() {
        _overdue = page.items;
        _overdueTotal = page.total ?? page.items.length;
        _pendingLoaded = true;
      });
    } catch (_) {}
  }

  /// Pending work in one list: overdue activities + open Workspace tasks,
  /// most overdue first.
  List<_PendingItem> _pendingItems() {
    final now = thaiNow();
    final out = <_PendingItem>[
      for (final a in _overdue)
        _PendingItem(
          kind: 'activity',
          title: '${a['subject'] ?? entityTitle(a, module: 'activity')}',
          detail: [a['account_name'], a['contact_name'], a['location']]
              .where((e) => e != null && '$e'.isNotEmpty)
              .join(' · '),
          due: parseWall(a['date_start']),
          route: a['id'] == null ? null : AppRoutes.activity('${a['id']}'),
        ),
      for (final t in _overdueWork)
        _PendingItem(
          kind: 'task',
          type: wsType(t),
          title: '${t['title'] ?? '—'}',
          detail: [
            if ('${t['board_name'] ?? ''}'.isNotEmpty) '${t['board_name']}',
            if ('${t['board_code'] ?? ''}'.isNotEmpty) '${t['board_code']}-${t['item_no'] ?? ''}',
            '${t['status_label_th'] ?? t['status_name'] ?? ''}',
          ].where((e) => e.isNotEmpty).join(' · '),
          due: parseThai(t['due_at']),
          route: t['board_id'] == null || t['id'] == null ? null : AppRoutes.task('${t['board_id']}', '${t['id']}'),
        ),
    ];
    out.sort((a, b) {
      final ad = a.due ?? now.add(const Duration(days: 3650));
      final bd = b.due ?? now.add(const Duration(days: 3650));
      return ad.compareTo(bd);
    });
    return out;
  }

  int _pendingTotal() => _overdueTotal + _overdueWork.length;

  int _revision = 0; // bumps on pull-to-refresh → boxes with their own data reload

  Future<void> _load() async {
    _revision++;
    final had = _summary != null || _attendance != null || _work != null;
    setState(() {
      _loading = !had;
      _refreshing = had;
      _error = null;
    });
    final config = context.read<AppConfig>();
    final api = config.apiClient;
    final session = config.session;
    Object? firstError;
    Future<Object?> guard(Future<Object?> f) async {
      try {
        return await f;
      } catch (e) {
        firstError ??= e;
        return null;
      }
    }

    final results = await Future.wait<Object?>([
      MenuAccess.allow(session, MenuAccess.attendance)
          ? guard(api.getAttendanceSummary())
          : Future<Object?>.value(),
      guard(api.getHomeSummary()),
      MenuAccess.allow(session, MenuAccess.workspace)
          ? guard(api.getHomeWork(limit: 8))
          : Future<Object?>.value(),
      guard(UnreadNotifications.instance.refresh(api).then((_) => null)),
      Future<Object?>.value(), // sales: own box with a period filter
      Future<Object?>.value(), // cases: own box with a period filter
      api.getWhatsNewUnread().then<Object?>((n) => n).catchError((_) => 0),
    ]);
    if (!mounted) return;
    setState(() {
      _attendance = results[0] as Map<String, dynamic>?;
      _summary = results[1] as Map<String, dynamic>?;
      _work = results[2] as Map<String, dynamic>?;
      _whatsNew = (results[6] as int?) ?? 0;
      _error = (_summary == null && _attendance == null && _work == null)
          ? firstError
          : null;
      _loading = false;
      _refreshing = false;
    });
    _loadOverdue();
    _loadSparks();
  }

  /// New records per day for the last 7 days (Thai days), per stat module.
  final Map<String, List<int>> _sparks = {};

  Future<void> _loadSparks() async {
    final config = context.read<AppConfig>();
    final session = config.session;
    final api = config.apiClient;
    final today = thaiNow();
    final t0 = DateTime(today.year, today.month, today.day);
    for (final module in _statModules.keys) {
      if (!MenuAccess.allow(session, EntityModules.menuKeyOf(module))) continue;
      try {
        // One tiny COUNT per day (limit 1 + with_total) — cheap even on huge tables.
        String ymd(DateTime d) =>
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final days = await Future.wait([
          for (var i = 6; i >= 0; i--)
            () async {
              final d = ymd(t0.subtract(Duration(days: i)));
              final page = await api.getEntityList(
                module,
                limit: 1,
                extra: {
                  'period_field': 'createdtime',
                  'period_preset': 'custom',
                  'period_start': d,
                  'period_end': d,
                  'with_total': '1',
                  'cols': 'id',
                },
              );
              return page.total ?? page.items.length;
            }(),
        ]);
        if (!mounted) return;
        setState(() => _sparks[module] = days);
      } catch (_) {
        // Sparklines are a nicety; the tile still shows its total.
      }
    }
  }

  int _count(Map<String, dynamic>? m, String key) =>
      int.tryParse(m?[key]?.toString() ?? '') ?? 0;



  List<Map<String, dynamic>> _upcoming() {
    final now = thaiNow().subtract(const Duration(hours: 1));
    final all = extractMapList(_summary?['activities']);
    return all
        .where((a) {
          final d = parseWall(a['date_start']);
          return d == null || d.isAfter(now);
        })
        .take(4)
        .toList();
  }

  /// Short plain-language summary of the day (streamed word by word).
  String _brief(Map<String, dynamic>? counts, dynamic clockIn) {
    final parts = <String>[];
    final overdue = _count(counts, 'overdue');
    final today = _count(counts, 'today');
    final next = _upcoming();
    if (clockIn == null &&
        MenuAccess.allow(
          context.read<AppConfig>().session,
          MenuAccess.attendance,
        )) {
      parts.add('ยังไม่ได้ลงเวลาเข้างาน');
    }
    if (today > 0) parts.add('มีงานครบกำหนดวันนี้ $today รายการ');
    if (overdue > 0) parts.add('งานเลยกำหนด $overdue รายการ ควรเคลียร์ก่อน');
    if (next.isNotEmpty) {
      final a = next.first;
      parts.add(
        'นัดถัดไป "${a['subject'] ?? 'กิจกรรม'}" เวลา ${_hhmm(a['date_start'])}',
      );
    }
    if (parts.isEmpty)
      return 'วันนี้ยังไม่มีงานค้างหรือนัดหมาย ลองถาม AI ให้ช่วยวางแผนหรือสรุปลูกค้าที่ควรติดตาม';
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final session = context.select((AppConfig c) => c.session);
    final bp = NxBreakpoint.of(context);
    final now = thaiNow();

    final clockIn = _attendance?['clock_in_at'] ?? _attendance?['clock_in'];
    final clockOut = _attendance?['clock_out_at'] ?? _attendance?['clock_out'];
    final counts = _work?['counts'] is Map
        ? Map<String, dynamic>.from(_work!['counts'] as Map)
        : null;
    final stats = _summary?['stats'] is Map
        ? Map<String, dynamic>.from(_summary!['stats'] as Map)
        : const <String, dynamic>{};

    final quick = <_QuickAction>[
      if (MenuAccess.allow(session, MenuAccess.attendance))
        const _QuickAction(NxI.clock, 'ลงเวลา', AppRoutes.attendance),
      if (MenuAccess.allow(session, MenuAccess.leave))
        const _QuickAction(NxI.calendarCheck, 'ขอลา', AppRoutes.leaveRequest),
      if (MenuAccess.allow(session, MenuAccess.quotation) ||
          MenuAccess.allow(session, MenuAccess.leaveManagement))
        const _QuickAction(NxI.checkCircle, 'รออนุมัติ', AppRoutes.approvals),
      if (MenuAccess.allow(session, MenuAccess.chat))
        const _QuickAction(NxI.chatCircle, 'แชท', AppRoutes.chatHome),
      if (MenuAccess.anyCalendar(session))
        const _QuickAction(NxI.calendarBlank, 'ปฏิทิน', AppRoutes.calendar),
      if (MenuAccess.allow(session, MenuAccess.job))
        const _QuickAction(NxI.wrench, 'งานบริการ', AppRoutes.jobs),
      if (MenuAccess.allow(session, MenuAccess.mailbox))
        const _QuickAction(NxI.envelope, 'เมล', AppRoutes.mail),
      if (MenuAccess.allow(session, MenuAccess.ai))
        const _QuickAction(NxI.robot, 'AI', AppRoutes.aiChat),
    ];

    final statTiles = [
      for (final e in _statModules.entries)
        if (stats.containsKey(e.key) &&
            MenuAccess.allow(session, EntityModules.menuKeyOf(e.key)))
          (e.key, e.value, _count(stats, e.key)),
    ];

    // Glass header floats over the page; content scrolls up beneath it.
    final pad = bp.scrollPadding(context, inShell: true);
    return NxScrollScaffold(
      insetBody: false,
      header: NxAppHeader.hub(
        actions: [
          // Search everything (customers, documents, tasks, chat, mail, menus).
          IconButton(
            key: const ValueKey('home-search'),
            tooltip: tr('ค้นหาทุกอย่าง'),
            icon: const Icon(NxI.magnifyingGlass),
            onPressed: () => context.push(AppRoutes.globalSearch),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          final listPad = pad.copyWith(
            // +12: greeting starts clear of the header's blur tail.
            top: pad.top + 12 + NxScrollScaffold.topInset(context),
          );
          final sections = <String, List<Widget>>{
            'today': [
              const SizedBox(height: 12),
              _TodayCard(
                showAttendance: MenuAccess.allow(
                  session,
                  MenuAccess.attendance,
                ),
                clockIn: clockIn,
                clockOut: clockOut,
                onPunch: (inn) async {
                  final r = await showAttendancePunchSheet(context, clockIn: inn, clockedInAt: parseThai(clockIn));
                  if (r != null && mounted) _load();
                },
                next: _upcoming().isEmpty ? null : _upcoming().first,
                overdue: _count(counts, 'overdue'),
                today: _count(counts, 'today'),
                upcoming: _count(counts, 'upcoming'),
                hasWork: counts != null,
              ),
            ],
            'pending': [
              if (_pendingItems().isNotEmpty) ...[
                const SizedBox(height: 20),
                _PendingBox(items: _pendingItems(), total: _pendingTotal()),
              ] else if (_pendingLoaded) ...[
                const SizedBox(height: 20),
                const _NoPending(),
              ],
            ],
            'birthdays': [HomeBirthdayBox(revision: _revision)],
            'ai': [
              if (MenuAccess.allow(session, MenuAccess.ai)) ...[
                const SizedBox(height: 12),
                _AiBriefCard(text: _brief(counts, clockIn)),
              ],
            ],
            'quick': [
              if (quick.isNotEmpty) ...[
                const SizedBox(height: 20),
                _QuickGrid(actions: quick),
              ],
            ],
            'work': [
              if (MenuAccess.allow(session, MenuAccess.workspace)) ...[
                const SizedBox(height: 20),
                MyWorkBox(revision: _revision),
              ],
            ],
            'upcoming': [
              if (_upcoming().length > 1) ...[
                const SizedBox(height: 24),
                _SectionTitle(
                  'กิจกรรมถัดไป',
                  action: 'ปฏิทิน',
                  onAction: () => context.push(AppRoutes.calendar),
                ),
                for (final a in _upcoming().skip(1))
                  _ListRow(
                    icon: NxI.calendarBlank,
                    title:
                        a['subject']?.toString() ??
                        entityTitle(a, module: 'activity'),
                    subtitle: [
                      _hhmm(a['date_start']),
                      a['location']?.toString() ?? '',
                    ].where((e) => e.isNotEmpty).join(' · '),
                    onTap: a['id'] == null
                        ? null
                        : () => context.push(
                            AppRoutes.activity(a['id'].toString()),
                          ),
                  ),
              ],
            ],
            'recent': [const RecentStrip()],
            'stats': [
              if (statTiles.isNotEmpty) ...[
                const SizedBox(height: 24),
                const _SectionTitle('ภาพรวม'),
                _StatGrid(
                  children: [
                    for (final (module, icon, n) in statTiles)
                      _StatCard(
                        label: EntityModules.titleOf(module),
                        value: n,
                        icon: icon,
                        spark: _sparks[module],
                        onTap: () => context.push(
                          EntityModules.isFsm(module)
                              ? AppRoutes.fsmModule(module)
                              : AppRoutes.crmModule(module),
                        ),
                      ),
                  ],
                ),
              ],
            ],
            'sales': [
              if (MenuAccess.any(session, const ['deal', 'quotation'])) ...[
                const SizedBox(height: 20),
                SalesPeriodBox(revision: _revision, onOpen: () => context.push(AppRoutes.crmModule('deal'))),
              ],
              if (MenuAccess.allow(session, 'case')) ...[
                const SizedBox(height: 16),
                CasePeriodBox(revision: _revision, onOpen: () => context.push(AppRoutes.crmModule('case'))),
              ],
              const SizedBox(height: 24),
            ],
          };
          return Stack(
            children: [
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 360,
                child: _PastelHero(),
              ),
              Column(
                children: [
                  if (_refreshing)
                    SizedBox(height: NxScrollScaffold.topInset(context)),
                  if (_refreshing) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: _loading
                        ? ListView(
                            padding: listPad,
                            children: const [NxSkeletonKpiGrid()],
                          )
                        : NxRefresh(
                            edgeOffset: NxScrollScaffold.topInset(context),
                            color: cs.primary,
                            onRefresh: _load,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: _refreshing ? pad : listPad,
                              children: [
                                Text(
                                  '${tr(greetingFor(now))}${session.displayName != null ? ' ${session.displayName}' : ''}',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  tr(thaiLongDate(now)),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const NxWorkspaceSwitcher(),
                                if (_error != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(
                                      tr(formatApiError(_error!)),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: cs.error),
                                    ),
                                  ),
                                if (_whatsNew > 0) ...[
                                  const SizedBox(height: 12),
                                  NxSurfaceCard(
                                    radius: 20,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    onTap: () async {
                                      await context.push(AppRoutes.whatsNew);
                                      if (mounted) _load();
                                    },
                                    child: Row(
                                      children: [
                                        Icon(
                                          NxI.sparkleFill,
                                          color: cs.primary,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            tr('มีอะไรใหม่ $_whatsNew รายการ'),
                                            style: theme.textTheme.titleSmall,
                                          ),
                                        ),
                                        Icon(
                                          NxI.caretRight,
                                          size: 16,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                // Sections in the user's order (Home → ปรับแต่งหน้าหลัก).
                                for (final key
                                    in HomeLayout.instance.visibleOrder)
                                  ...?sections[key],
                                const SizedBox(height: 20),
                                Center(
                                  child: TextButton.icon(
                                    onPressed: _openHomeEditor,
                                    icon: const Icon(NxI.squaresFour, size: 18),
                                    label: Text(tr('ปรับแต่งหน้าหลัก')),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Soft pastel cloud behind the greeting (reference: onboarding video).
class _PastelHero extends StatelessWidget {
  const _PastelHero();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final a = dark ? 0.22 : 0.32;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bg.withValues(alpha: 0), bg],
            stops: const [0.45, 1],
          ),
        ),
        position: DecorationPosition.foreground,
        child: Stack(
          children: [
            Positioned(
              top: -80,
              left: -60,
              child: _blob(280, const Color(0xFFF9A8D4).withValues(alpha: a)),
            ),
            Positioned(
              top: -40,
              right: -70,
              child: _blob(260, cs.primary.withValues(alpha: a * 0.9)),
            ),
            Positioned(
              top: 120,
              left: 80,
              child: _blob(
                220,
                const Color(0xFF93C5FD).withValues(alpha: a * 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _blob(double size, Color c) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)]),
    ),
  );
}

/// One card for "today": attendance, next appointment and work counts.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.showAttendance,
    required this.clockIn,
    required this.clockOut,
    required this.next,
    required this.overdue,
    required this.today,
    required this.upcoming,
    required this.hasWork,
    this.onPunch,
  });

  /// Opens the clock in / out window (true = clock in).
  final void Function(bool clockIn)? onPunch;

  final bool showAttendance;
  final dynamic clockIn;
  final dynamic clockOut;
  final Map<String, dynamic>? next;
  final int overdue;
  final int today;
  final int upcoming;
  final bool hasWork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final inAt = _hhmm(clockIn);
    final outAt = _hhmm(clockOut);
    final String status;
    final String cta;
    if (clockIn == null) {
      status = 'ยังไม่ได้ลงเวลาเข้างาน';
      cta = 'ลงเวลาเข้า';
    } else if (clockOut == null) {
      status = 'เข้างาน $inAt';
      cta = 'ลงเวลาออก';
    } else {
      status = 'เข้า $inAt · ออก $outAt';
      cta = 'ประวัติ';
    }
    final rows = <Widget>[];
    if (showAttendance) {
      rows.add(
        Row(
          children: [
            clockIn == null ? _dot(cs.primary, NxI.clock, cs) : _dot(const Color(0xFF16A34A), NxI.checkCircle, cs),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('ลงเวลาวันนี้'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    tr(status),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.onSurface,
                foregroundColor: cs.surface,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                minimumSize: const Size(0, 40),
              ),
              key: const ValueKey('home-punch'),
              onPressed: () => clockOut != null || onPunch == null ? context.push(AppRoutes.attendance) : onPunch!(clockIn == null),
              child: Text(tr(cta)),
            ),
          ],
        ),
      );
    }
    final n = next;
    if (n != null) {
      if (rows.isNotEmpty) rows.add(const Divider(height: 24));
      rows.add(
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: n['id'] == null
              ? null
              : () => context.push(AppRoutes.activity(n['id'].toString())),
          child: Row(
            children: [
              _dot(const Color(0xFFF59E0B), NxI.calendarBlank, cs),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('นัดถัดไป · ${_hhmm(n['date_start'])}'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      tr(
                        n['subject']?.toString() ??
                            entityTitle(n, module: 'activity'),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((n['location']?.toString() ?? '').isNotEmpty)
                      Text(
                        tr(n['location'].toString()),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              Icon(NxI.caretRight, size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      );
    }
    if (hasWork) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 14));
      rows.add(
        Row(
          children: [
            Expanded(child: _CountPill('เลยกำหนด', overdue, cs.error)),
            const SizedBox(width: 8),
            Expanded(
              child: _CountPill('วันนี้', today, const Color(0xFFF59E0B)),
            ),
            const SizedBox(width: 8),
            Expanded(child: _CountPill('กำลังมา', upcoming, cs.primary)),
          ],
        ),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return NxSurfaceCard(
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  static Widget _dot(Color c, IconData icon, ColorScheme cs) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, color: c, size: 20),
  );
}

/// Day summary that streams in word by word, with a shortcut to the AI chat.
class _AiBriefCard extends StatelessWidget {
  const _AiBriefCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NxSurfaceCard(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      onTap: () => context.push(AppRoutes.aiChat),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  colors: [Color(0xFFEC4899), Color(0xFF6366F1)],
                ).createShader(r),
                child: const Icon(
                  NxI.sparkleFill,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                tr('สรุปวันนี้'),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                tr('ถาม AI'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(NxI.caretRight, size: 14, color: cs.primary),
            ],
          ),
          const SizedBox(height: 8),
          NxStreamingText(
            tr(text),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction(this.icon, this.label, this.route);
  final IconData icon;
  final String label;
  final String route;

  /// Bolder stroke + own colour so shortcuts read clearly in light mode.
  static const Map<String, (IconData, Color)> _styles = {
    'ลงเวลา': (LucideIcons500.clock, Color(0xFF6366F1)),
    'ขอลา': (LucideIcons500.calendarCheck, Color(0xFF0D9488)),
    'รออนุมัติ': (LucideIcons500.circleCheck, Color(0xFF16A34A)),
    'แชท': (LucideIcons500.messageCircle, Color(0xFF0284C7)),
    'ปฏิทิน': (LucideIcons500.calendar, Color(0xFFD97706)),
    'งานบริการ': (LucideIcons500.wrench, Color(0xFFEA580C)),
    'เมล': (LucideIcons500.mail, Color(0xFFE11D48)),
    'AI': (LucideIcons500.bot, Color(0xFF7C3AED)),
  };

  IconData get boldIcon => _styles[label]?.$1 ?? icon;
  Color colorIn(ColorScheme cs) => _styles[label]?.$2 ?? cs.primary;
}

class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.actions});
  final List<_QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 560 ? 8 : 4;
        final w = c.maxWidth / cols;
        return Wrap(
          children: [
            for (final a in actions)
              SizedBox(
                width: w,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.push(a.route),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: a
                                .colorIn(cs)
                                .withValues(
                                  alpha: theme.brightness == Brightness.dark
                                      ? 0.22
                                      : 0.12,
                                ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: a.colorIn(cs).withValues(alpha: 0.18),
                            ),
                          ),
                          child: Icon(
                            a.boldIcon,
                            size: 24,
                            color: a.colorIn(cs),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr(a.label),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tr(title),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(tr(action!))),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('$value'),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(tr(label), style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NxSurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      tr(subtitle!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                NxI.caretRight,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 720 ? 4 : (c.maxWidth >= 340 ? 2 : 1);
        const gap = 12.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: w, child: child),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
    this.spark,
  });
  final String label;
  final int value;
  final IconData icon;
  final VoidCallback? onTap;

  /// New per day, oldest → today (7 values).
  final List<int>? spark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NxSurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            child: Icon(icon, size: 20, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('$value'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  tr(label),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (spark != null && spark!.any((v) => v > 0))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 54,
                          height: 18,
                          child: CustomPaint(
                            painter: _SparkPainter(
                              spark!,
                              theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '+${spark!.fold(0, (a, b) => a + b)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiny line chart for a stat tile.
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);
  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
    final dx = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final p = Offset(
        i * dx,
        size.height - 2 - (values[i] / maxV) * (size.height - 4),
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.values != values || old.color != color;
}


class _PendingItem {
  const _PendingItem({required this.kind, required this.title, this.detail = '', this.due, this.route, this.type});
  final String kind; // activity | task
  final String? type; // workspace item type (task / subtask / bug / story)
  final String title;
  final String detail;
  final DateTime? due;
  final String? route;
}

/// "งานค้าง": overdue activities + open Workspace tasks in one card, with a
/// red/amber rail per item and how late it is.
class _PendingBox extends StatefulWidget {
  const _PendingBox({required this.items, required this.total});
  final List<_PendingItem> items;
  final int total;

  @override
  State<_PendingBox> createState() => _PendingBoxState();
}

class _PendingBoxState extends State<_PendingBox> {
  String _kind = 'all';
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    () async {
      final saved = await HomePrefs.get(context, 'pending_collapsed');
      if (mounted && saved == '1') setState(() => _collapsed = true);
    }();
  }

  String _late(DateTime? due) {
    if (due == null) return tr('ไม่กำหนดส่ง');
    final now = thaiNow();
    final d0 = DateTime(now.year, now.month, now.day);
    final dd = DateTime(due.year, due.month, due.day);
    final days = d0.difference(dd).inDays;
    if (days > 0) return tr('เลยกำหนด $days วัน');
    if (days == 0) return tr('ครบกำหนดวันนี้');
    return tr('อีก ${-days} วัน');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final acts = widget.items.where((e) => e.kind == 'activity').length;
    final tasks = widget.items.where((e) => e.kind == 'task').length;
    final shown = widget.items.where((e) => _kind == 'all' || e.kind == _kind).take(5).toList();
    final now = thaiNow();
    Widget chip(String k, String label, int n) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text('${tr(label)} $n'),
            selected: _kind == k,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => setState(() => _kind = k),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.alphaBlend(cs.error.withValues(alpha: 0.08), cs.surface), cs.surface],
        ),
        border: Border.all(color: cs.error.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeBoxHeader(
            key: const ValueKey('pending-header'),
            icon: NxI.warningCircle,
            title: 'งานค้าง',
            color: cs.error,
            count: widget.total,
            collapsed: _collapsed,
            onToggle: () {
              setState(() => _collapsed = !_collapsed);
              HomePrefs.set(context, 'pending_collapsed', _collapsed ? '1' : '0');
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            alignment: Alignment.topCenter,
            child: _collapsed
                ? const SizedBox(width: double.infinity)
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              chip('all', 'ทั้งหมด', widget.items.length),
              if (acts > 0) chip('activity', 'กิจกรรม', acts),
              if (tasks > 0) chip('task', 'Workspace', tasks),
            ]),
          ),
          const SizedBox(height: 6),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                for (final it in shown)
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: it.route == null ? null : () => context.push(it.route!),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 38,
                            decoration: BoxDecoration(
                              color: it.due != null && it.due!.isBefore(DateTime(now.year, now.month, now.day))
                                  ? cs.error
                                  : const Color(0xFFF59E0B),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            it.kind == 'activity' ? NxI.calendarBlank : wsTypeStyle(it.type ?? 'task').icon,
                            size: 18,
                            color: it.kind == 'activity' ? cs.onSurfaceVariant : wsTypeStyle(it.type ?? 'task').color,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                                Text(
                                  [_late(it.due), if (it.detail.isNotEmpty) it.detail].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Icon(NxI.caretRight, size: 16, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (acts > 0)
                TextButton(onPressed: () => context.push(AppRoutes.calendar), child: Text(tr('กิจกรรมค้างทั้งหมด'))),
              if (tasks > 0)
                TextButton(onPressed: () => context.push(AppRoutes.workspaceHome), child: Text(tr('งาน Workspace'))),
            ],
          ),
                  ]),
          ),
        ],
      ),
    );
  }
}


/// Empty state of the pending box: nothing overdue.
class _NoPending extends StatelessWidget {
  const _NoPending();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const green = Color(0xFF10B981);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: green.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(NxI.checkCircle, color: green),
          const SizedBox(width: 10),
          Expanded(child: Text(tr('ไม่มีงานค้าง — เคลียร์ครบแล้ว'), style: theme.textTheme.titleSmall)),
        ],
      ),
    );
  }
}

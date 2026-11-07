import 'package:flutter/material.dart';
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
import 'team_overview_card.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_streaming_text.dart';

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

String thaiLongDate(DateTime d) =>
    'วัน${_thaiDays[d.weekday - 1]}ที่ ${d.day} ${_thaiMonths[d.month - 1]} ${d.year + 543}';

String _hhmm(dynamic raw) {
  final d = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
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
  Map<String, dynamic>? _sales;
  Map<String, dynamic>? _cases;
  int _whatsNew = 0;
  bool _loading = true;
  bool _refreshing = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
      MenuAccess.any(session, const ['deal', 'quotation'])
          ? guard(api.getSalesDashboard())
          : Future<Object?>.value(),
      MenuAccess.allow(session, 'case')
          ? guard(api.getCaseDashboard())
          : Future<Object?>.value(),
      api.getWhatsNewUnread().then<Object?>((n) => n).catchError((_) => 0),
    ]);
    if (!mounted) return;
    setState(() {
      _attendance = results[0] as Map<String, dynamic>?;
      _summary = results[1] as Map<String, dynamic>?;
      _work = results[2] as Map<String, dynamic>?;
      _sales = results[4] as Map<String, dynamic>?;
      _cases = results[5] as Map<String, dynamic>?;
      _whatsNew = (results[6] as int?) ?? 0;
      _error = (_summary == null && _attendance == null && _work == null)
          ? firstError
          : null;
      _loading = false;
      _refreshing = false;
    });
  }

  int _count(Map<String, dynamic>? m, String key) =>
      int.tryParse(m?[key]?.toString() ?? '') ?? 0;

  List<Map<String, dynamic>> _workItems() {
    final items = extractMapList(_work?['items'] ?? _work?['work']);
    return items.where((e) => e['status_is_done'] != true).take(5).toList();
  }

  List<Map<String, dynamic>> _upcoming() {
    final now = DateTime.now().subtract(const Duration(hours: 1));
    final all = extractMapList(_summary?['activities']);
    return all
        .where((a) {
          final d = DateTime.tryParse(a['date_start']?.toString() ?? '');
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
    final now = DateTime.now();

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
          IconButton(
            icon: const Icon(NxI.arrowCounterClockwise),
            tooltip: 'รีเฟรช',
            onPressed: _load,
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          final listPad = pad.copyWith(
            // +12: greeting starts clear of the header's blur tail.
            top: pad.top + 12 + NxScrollScaffold.topInset(context),
          );
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
                        : RefreshIndicator(
                            edgeOffset: NxScrollScaffold.topInset(context),
                            color: cs.primary,
                            onRefresh: _load,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: _refreshing ? pad : listPad,
                              children: [
                                Text(
                                  '${greetingFor(now)}${session.displayName != null ? ' ${session.displayName}' : ''}',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  thaiLongDate(now),
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
                                      formatApiError(_error!),
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
                                            'มีอะไรใหม่ $_whatsNew รายการ',
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
                                const SizedBox(height: 16),
                                _TodayCard(
                                  showAttendance: MenuAccess.allow(
                                    session,
                                    MenuAccess.attendance,
                                  ),
                                  clockIn: clockIn,
                                  clockOut: clockOut,
                                  next: _upcoming().isEmpty
                                      ? null
                                      : _upcoming().first,
                                  overdue: _count(counts, 'overdue'),
                                  today: _count(counts, 'today'),
                                  upcoming: _count(counts, 'upcoming'),
                                  hasWork: counts != null,
                                ),
                                if (MenuAccess.allow(
                                  session,
                                  MenuAccess.ai,
                                )) ...[
                                  const SizedBox(height: 12),
                                  _AiBriefCard(text: _brief(counts, clockIn)),
                                ],
                                if (quick.isNotEmpty) ...[
                                  const SizedBox(height: 20),
                                  _QuickGrid(actions: quick),
                                ],
                                if (counts != null &&
                                    _workItems().isNotEmpty) ...[
                                  const SizedBox(height: 24),
                                  _SectionTitle(
                                    'งานของฉัน',
                                    action: 'ทั้งหมด',
                                    onAction: () =>
                                        context.push(AppRoutes.workspaceHome),
                                  ),
                                  for (final it in _workItems())
                                    _WorkRow(item: it),
                                ],
                                if (_upcoming().length > 1) ...[
                                  const SizedBox(height: 24),
                                  _SectionTitle(
                                    'กิจกรรมถัดไป',
                                    action: 'ปฏิทิน',
                                    onAction: () =>
                                        context.push(AppRoutes.calendar),
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
                                              AppRoutes.activity(
                                                a['id'].toString(),
                                              ),
                                            ),
                                    ),
                                ],
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
                                          onTap: () => context.push(
                                            EntityModules.isFsm(module)
                                                ? AppRoutes.fsmModule(module)
                                                : AppRoutes.crmModule(module),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                                if (salesFigures(_sales).isNotEmpty ||
                                    caseFigures(_cases).isNotEmpty) ...[
                                  const SizedBox(height: 24),
                                  const _SectionTitle('ยอดขายและเคส'),
                                  TeamOverviewCard(
                                    sales: _sales,
                                    cases: _cases,
                                    onOpenSales: () => context.push(
                                      AppRoutes.crmModule('deal'),
                                    ),
                                    onOpenCases: () => context.push(
                                      AppRoutes.crmModule('case'),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 24),
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
  });

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
            _dot(cs.primary, NxI.clock, cs),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ลงเวลาวันนี้',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    status,
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
              onPressed: () => context.push(AppRoutes.attendance),
              child: Text(cta),
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
                      'นัดถัดไป · ${_hhmm(n['date_start'])}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      n['subject']?.toString() ??
                          entityTitle(n, module: 'activity'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((n['location']?.toString() ?? '').isNotEmpty)
                      Text(
                        n['location'].toString(),
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
                'สรุปวันนี้',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                'ถาม AI',
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
            text,
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
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(a.icon, color: cs.onPrimaryContainer),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          a.label,
                          style: theme.textTheme.labelMedium,
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
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
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
            '$value',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _WorkRow extends StatelessWidget {
  const _WorkRow({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final code = item['board_code']?.toString() ?? '';
    final no = item['item_no']?.toString() ?? '';
    final board = item['board_id']?.toString();
    final id = item['id']?.toString();
    return _ListRow(
      icon: NxI.kanban,
      title: item['title']?.toString() ?? '—',
      subtitle: [
        if (code.isNotEmpty) '$code-$no',
        item['status_label_th']?.toString() ??
            item['status_name']?.toString() ??
            '',
        if (item['due_at'] != null) 'ส่ง ${item['due_at']}',
      ].where((e) => e.isNotEmpty).join(' · '),
      onTap: board == null || id == null
          ? null
          : () => context.push(AppRoutes.task(board, id)),
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
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
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
  });
  final String label;
  final int value;
  final IconData icon;
  final VoidCallback? onTap;

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
                  '$value',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

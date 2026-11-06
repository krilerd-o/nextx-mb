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
import '../../widgets/nx_surface_card.dart';
import '../../widgets/nx_icons.dart';

/// Thai greeting for the hour of day.
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'สวัสดีตอนเช้า';
  if (h < 17) return 'สวัสดีตอนบ่าย';
  return 'สวัสดีตอนเย็น';
}

const _thaiMonths = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
const _thaiDays = ['จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์', 'อาทิตย์'];

String thaiLongDate(DateTime d) => 'วัน${_thaiDays[d.weekday - 1]}ที่ ${d.day} ${_thaiMonths[d.month - 1]} ${d.year + 543}';

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
      MenuAccess.allow(session, MenuAccess.attendance) ? guard(api.getAttendanceSummary()) : Future<Object?>.value(),
      guard(api.getHomeSummary()),
      MenuAccess.allow(session, MenuAccess.workspace) ? guard(api.getHomeWork(limit: 8)) : Future<Object?>.value(),
      guard(UnreadNotifications.instance.refresh(api).then((_) => null)),
    ]);
    if (!mounted) return;
    setState(() {
      _attendance = results[0] as Map<String, dynamic>?;
      _summary = results[1] as Map<String, dynamic>?;
      _work = results[2] as Map<String, dynamic>?;
      _error = (_summary == null && _attendance == null && _work == null) ? firstError : null;
      _loading = false;
      _refreshing = false;
    });
  }

  int _count(Map<String, dynamic>? m, String key) => int.tryParse(m?[key]?.toString() ?? '') ?? 0;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = context.watch<AppConfig>();
    final session = config.session;
    final bp = NxBreakpoint.of(context);
    final now = DateTime.now();

    final clockIn = _attendance?['clock_in_at'] ?? _attendance?['clock_in'];
    final clockOut = _attendance?['clock_out_at'] ?? _attendance?['clock_out'];
    final counts = _work?['counts'] is Map ? Map<String, dynamic>.from(_work!['counts'] as Map) : null;
    final stats = _summary?['stats'] is Map ? Map<String, dynamic>.from(_summary!['stats'] as Map) : const <String, dynamic>{};

    final quick = <_QuickAction>[
      if (MenuAccess.allow(session, MenuAccess.attendance))
        const _QuickAction(NxI.clock, 'ลงเวลา', AppRoutes.attendance),
      if (MenuAccess.allow(session, MenuAccess.leave)) const _QuickAction(NxI.calendarCheck, 'ขอลา', AppRoutes.leaveRequest),
      if (MenuAccess.allow(session, MenuAccess.quotation) || MenuAccess.allow(session, MenuAccess.leaveManagement))
        const _QuickAction(NxI.checkCircle, 'รออนุมัติ', AppRoutes.approvals),
      if (MenuAccess.allow(session, MenuAccess.chat)) const _QuickAction(NxI.chatCircle, 'แชท', AppRoutes.chatHome),
      if (MenuAccess.anyCalendar(session)) const _QuickAction(NxI.calendarBlank, 'ปฏิทิน', AppRoutes.calendar),
      if (MenuAccess.allow(session, MenuAccess.job)) const _QuickAction(NxI.wrench, 'งานบริการ', AppRoutes.jobs),
      if (MenuAccess.allow(session, MenuAccess.mailbox)) const _QuickAction(NxI.envelope, 'เมล', AppRoutes.mail),
      if (MenuAccess.allow(session, MenuAccess.ai)) const _QuickAction(NxI.robot, 'AI', AppRoutes.aiChat),
    ];

    final statTiles = [
      for (final e in _statModules.entries)
        if (stats.containsKey(e.key) && MenuAccess.allow(session, EntityModules.menuKeyOf(e.key)))
          (e.key, e.value, _count(stats, e.key)),
    ];

    return Column(
      children: [
        NxAppHeader.hub(
          actions: [
            IconButton(icon: const Icon(NxI.arrowCounterClockwise), tooltip: 'รีเฟรช', onPressed: _load),
          ],
        ),
        if (_refreshing) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _loading
              ? ListView(
                  padding: bp.scrollPadding(context, inShell: true),
                  children: const [NxSkeletonKpiGrid()],
                )
              : RefreshIndicator(
                  color: cs.primary,
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: bp.scrollPadding(context, inShell: true),
                    children: [
                      Text(
                        '${greetingFor(now)}${session.displayName != null ? ' ${session.displayName}' : ''}',
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [thaiLongDate(now), if (session.businessName != null) session.businessName!].join(' · '),
                        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(formatApiError(_error!), style: theme.textTheme.bodySmall?.copyWith(color: cs.error)),
                        ),
                      if (MenuAccess.allow(session, MenuAccess.attendance)) ...[
                        const SizedBox(height: 16),
                        _AttendanceCard(clockIn: clockIn, clockOut: clockOut),
                      ],
                      if (quick.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _QuickGrid(actions: quick),
                      ],
                      if (counts != null) ...[
                        const SizedBox(height: 24),
                        _SectionTitle('งานของฉัน', action: 'ทั้งหมด', onAction: () => context.push(AppRoutes.workspaceHome)),
                        Row(
                          children: [
                            Expanded(child: _CountPill('เลยกำหนด', _count(counts, 'overdue'), cs.error)),
                            const SizedBox(width: 8),
                            Expanded(child: _CountPill('วันนี้', _count(counts, 'today'), const Color(0xFFF59E0B))),
                            const SizedBox(width: 8),
                            Expanded(child: _CountPill('กำลังมา', _count(counts, 'upcoming'), cs.primary)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final it in _workItems()) _WorkRow(item: it),
                      ],
                      if (_upcoming().isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _SectionTitle('กิจกรรมถัดไป', action: 'ปฏิทิน', onAction: () => context.push(AppRoutes.calendar)),
                        for (final a in _upcoming())
                          _ListRow(
                            icon: NxI.calendarBlank,
                            title: a['subject']?.toString() ?? entityTitle(a, module: 'activity'),
                            subtitle: [
                              _hhmm(a['date_start']),
                              a['location']?.toString() ?? '',
                            ].where((e) => e.isNotEmpty).join(' · '),
                            onTap: a['id'] == null ? null : () => context.push(AppRoutes.activity(a['id'].toString())),
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
                                  EntityModules.isFsm(module) ? AppRoutes.fsmModule(module) : AppRoutes.crmModule(module),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({this.clockIn, this.clockOut});
  final dynamic clockIn;
  final dynamic clockOut;

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
      status = 'เข้างานเวลา $inAt';
      cta = 'ลงเวลาออก';
    } else {
      status = 'เข้า $inAt · ออก $outAt';
      cta = 'ดูประวัติ';
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [cs.primary, Color.lerp(cs.primary, cs.tertiary, 0.6)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: cs.onPrimary.withValues(alpha: 0.18),
            child: Icon(NxI.clock, color: cs.onPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ลงเวลาวันนี้', style: theme.textTheme.labelLarge?.copyWith(color: cs.onPrimary.withValues(alpha: 0.85))),
                const SizedBox(height: 2),
                Text(status, style: theme.textTheme.titleMedium?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(backgroundColor: cs.onPrimary, foregroundColor: cs.primary),
            onPressed: () => context.push(AppRoutes.attendance),
            child: Text(cta),
          ),
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
    return LayoutBuilder(builder: (context, c) {
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
                        decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(16)),
                        child: Icon(a.icon, color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(height: 6),
                      Text(a.label, style: theme.textTheme.labelMedium, textAlign: TextAlign.center, maxLines: 1),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    });
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
          Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
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
          Text('$value', style: theme.textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
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
        item['status_label_th']?.toString() ?? item['status_name']?.toString() ?? '',
        if (item['due_at'] != null) 'ส่ง ${item['due_at']}',
      ].where((e) => e.isNotEmpty).join(' · '),
      onTap: board == null || id == null ? null : () => context.push(AppRoutes.task(board, id)),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({required this.icon, required this.title, this.subtitle, this.onTap});
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
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            if (onTap != null) Icon(NxI.caretRight, size: 18, color: theme.colorScheme.onSurfaceVariant),
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
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 720 ? 4 : (c.maxWidth >= 340 ? 2 : 1);
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final child in children) SizedBox(width: w, child: child)],
      );
    });
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, this.onTap});
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
                Text('$value', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

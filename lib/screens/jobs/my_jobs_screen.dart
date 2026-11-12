import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/i18n.dart';
import '../../core/journey_rules.dart' show canonicalJobStatus, jobStatusLabel;
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../../core/service_journey.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_refresh.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_scroll_tabs.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_split_view.dart';
import '../calendar/activity_detail_screen.dart';
import '../crm/entity_detail_screen.dart';
import '../journey/status_followups.dart' show journeyErrorText;
import 'job_inspection_screen.dart';

/// Which list a job belongs to on "My Service Job".
enum MyJobBucket { today, active, upcoming, unscheduled, done }

/// Plan date of a job (Thai wall clock) — plan start, else due.
DateTime? myJobDate(Map<String, dynamic> r) =>
    r['plan_start'] != null ? parseThaiField(r['plan_start'], 'plan_start') : parseThaiField(r['due_datetime'], 'due_datetime');

/// Today = due today or overdue; active = in progress (any day);
/// upcoming = later; unscheduled = no date; done = completed / cancelled.
MyJobBucket myJobBucket(Map<String, dynamic> r, DateTime now) {
  final st = canonicalJobStatus(r['job_status']);
  if (st == 'Completed' || st == 'Cancelled') return MyJobBucket.done;
  if (st == 'In Progress') return MyJobBucket.active;
  final d = myJobDate(r);
  if (d == null) return MyJobBucket.unscheduled;
  final day = DateTime(d.year, d.month, d.day);
  final t0 = DateTime(now.year, now.month, now.day);
  return day.isAfter(t0) ? MyJobBucket.upcoming : MyJobBucket.today;
}

bool myJobOverdue(Map<String, dynamic> r, DateTime now) {
  final d = myJobDate(r);
  if (d == null) return false;
  final st = canonicalJobStatus(r['job_status']);
  if (st == 'Completed' || st == 'Cancelled') return false;
  return DateTime(d.year, d.month, d.day).isBefore(DateTime(now.year, now.month, now.day));
}

/// "My Service Job" — the technician's own day: only jobs assigned to me,
/// grouped Today / In progress / Upcoming / Not scheduled / Done, with the
/// things you do in the field on each card (navigate, call, check in,
/// inspection). The "Job" menu is the whole team's work orders.
class MyJobsScreen extends StatefulWidget {
  const MyJobsScreen({super.key});

  @override
  State<MyJobsScreen> createState() => _MyJobsScreenState();
}

class _MyJobsScreenState extends State<MyJobsScreen> {
  static const _hintKey = 'nx_my_jobs_hint_v1';
  List<Map<String, dynamic>>? _jobs;
  List<Map<String, dynamic>> _awaiting = const [];
  final Set<String> _accepting = {};
  Object? _error;
  MyJobBucket? _tab;
  String _q = '';
  bool _searching = false;
  bool _hint = false;
  bool _journey = false;
  Map<String, dynamic>? _selected;

  @override
  void initState() {
    super.initState();
    _load();
    SharedPreferences.getInstance().then((p) {
      if (mounted && p.getBool(_hintKey) != true) setState(() => _hint = true);
    });
  }

  Future<void> _load() async {
    final api = context.read<AppConfig>().apiClient;
    try {
      final list = await api.getMyJobs(limit: 200, includeDone: true);
      if (!mounted) return;
      setState(() {
        _jobs = list;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    _journey = await ServiceJourney.supported(api);
    if (!_journey) return;
    try {
      final a = await api.getJobsAwaitingMe();
      if (mounted) setState(() => _awaiting = a);
    } catch (_) {}
  }

  Future<void> _closeHint() async {
    setState(() => _hint = false);
    try {
      (await SharedPreferences.getInstance()).setBool(_hintKey, true);
    } catch (_) {}
  }

  Future<void> _accept(Map<String, dynamic> j) async {
    final id = strId(j['id']);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _accepting.add(id));
    try {
      await context.read<AppConfig>().apiClient.jobWorkflowAction(id, 'accept');
      HapticFeedback.mediumImpact();
      messenger.showSnackBar(SnackBar(content: Text(tr('รับงานแล้ว — กำลังดำเนินการ'))));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr(journeyErrorText(e)))));
    } finally {
      if (mounted) setState(() => _accepting.remove(id));
    }
  }

  void _open(Map<String, dynamic> row) {
    if (NxBreakpoint.of(context).twoPane) {
      setState(() => _selected = row);
      return;
    }
    nxPush<void>(context, EntityDetailScreen(module: 'job', row: row)).then((_) => _load());
  }

  void _explain() {
    showAppBottomSheet<void>(
      context: context,
      title: tr('งานช่างของฉัน ต่างจาก ใบสั่งงาน อย่างไร'),
      child: Builder(builder: (ctx) {
        final theme = Theme.of(ctx);
        Widget row(IconData icon, String title, String body) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 22, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(tr(body), style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
                  ]),
                ),
              ]),
            );
        return Column(mainAxisSize: MainAxisSize.min, children: [
          row(NxI.hammer, 'งานช่างของฉัน (My Service Job)', 'เฉพาะงานที่มอบหมายให้คุณ จัดตามวัน: วันนี้ กำลังทำ ถัดไป — มีปุ่มนำทาง โทรหาลูกค้า เช็คอิน และตรวจรับในการ์ด เหมาะกับช่างหน้างาน'),
          row(NxI.wrench, 'ใบสั่งงาน (Job)', 'ใบสั่งงานทั้งหมดของทีม ใช้สร้าง มอบหมาย ค้นหา และติดตามงานทุกใบ เหมาะกับหัวหน้าหรือผู้ประสานงาน'),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('my-jobs-open-all'),
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/fsm/job');
              },
              icon: const Icon(NxI.wrench, size: 16),
              label: Text(tr('ไปที่ใบสั่งงานทั้งหมด')),
            ),
          ),
        ]);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = thaiNow();
    final jobs = _jobs;
    final q = _q.trim().toLowerCase();
    final shown = jobs == null
        ? const <Map<String, dynamic>>[]
        : [
            for (final r in jobs)
              if (q.isEmpty ||
                  '${r['job_no'] ?? ''} ${r['job_name'] ?? ''} ${r['customer_name'] ?? ''} ${r['site_address_snapshot'] ?? ''} ${r['location_name_snapshot'] ?? ''}'
                      .toLowerCase()
                      .contains(q))
                r,
          ];
    final byBucket = {for (final b in MyJobBucket.values) b: <Map<String, dynamic>>[]};
    for (final r in shown) {
      byBucket[myJobBucket(r, now)]!.add(r);
    }
    for (final l in byBucket.values) {
      l.sort((a, b) {
        final da = myJobDate(a), db = myJobDate(b);
        if (da == null || db == null) return da == null ? 1 : -1;
        return da.compareTo(db);
      });
    }
    byBucket[MyJobBucket.done]!.sort((a, b) => '${b['modifiedtime'] ?? ''}'.compareTo('${a['modifiedtime'] ?? ''}'));
    const order = [MyJobBucket.today, MyJobBucket.active, MyJobBucket.upcoming, MyJobBucket.unscheduled, MyJobBucket.done];
    final tab = _tab ?? order.firstWhere((b) => byBucket[b]!.isNotEmpty, orElse: () => MyJobBucket.today);
    final labels = {
      MyJobBucket.today: 'วันนี้',
      MyJobBucket.active: 'กำลังทำ',
      MyJobBucket.upcoming: 'ถัดไป',
      MyJobBucket.unscheduled: 'ยังไม่นัด',
      MyJobBucket.done: 'เสร็จแล้ว',
    };
    final list = byBucket[tab]!;
    final overdue = (jobs ?? const []).where((r) => myJobOverdue(r, now)).length;

    final body = NxRefresh(
      onRefresh: _load,
      child: ListView(
        key: const ValueKey('my-jobs-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: NxBreakpoint.of(context).scrollPadding(context),
        children: [
          if (_hint) _HintCard(onClose: _closeHint, onMore: _explain),
          if (_searching)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                key: const ValueKey('my-jobs-search'),
                autofocus: true,
                decoration: InputDecoration(
                  hintText: tr('ค้นหาเลขงาน / ลูกค้า / สถานที่'),
                  prefixIcon: const Icon(NxI.magnifyingGlass, size: 18),
                  suffixIcon: IconButton(
                    icon: const Icon(NxI.x, size: 18),
                    onPressed: () => setState(() {
                      _q = '';
                      _searching = false;
                    }),
                  ),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
          _Summary(
            today: byBucket[MyJobBucket.today]!.length,
            active: byBucket[MyJobBucket.active]!.length,
            overdue: overdue,
            awaiting: _awaiting.length,
          ),
          const SizedBox(height: 12),
          if (_awaiting.isNotEmpty) _awaitingCard(context),
          NxScrollTabs(
            keyPrefix: 'my-jobs-tab-',
            labels: [for (final b in order) labels[b]!],
            badges: [for (final b in order) byBucket[b]!.length],
            index: order.indexOf(tab),
            onChanged: (i) => setState(() => _tab = order[i]),
          ),
          const SizedBox(height: 12),
          if (jobs == null && _error == null) const NxSkeletonList(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Text(tr(formatApiError(_error!)), textAlign: TextAlign.center),
                TextButton(onPressed: _load, child: Text(tr('ลองใหม่'))),
              ]),
            ),
          if (jobs != null && list.isEmpty)
            _Empty(text: switch (tab) {
              MyJobBucket.today => 'วันนี้ไม่มีงาน — ดูงานถัดไปได้ที่แท็บ "ถัดไป"',
              MyJobBucket.active => 'ยังไม่มีงานที่กำลังทำ',
              MyJobBucket.upcoming => 'ยังไม่มีงานนัดล่วงหน้า',
              MyJobBucket.unscheduled => 'ทุกงานมีวันนัดแล้ว',
              MyJobBucket.done => 'ยังไม่มีงานที่ปิดใน 7 วันที่ผ่านมา',
            }),
          for (final r in list)
            _JobCard(
              row: r,
              now: now,
              journey: _journey,
              accepting: _accepting.contains(strId(r['id'])),
              onOpen: () => _open(r),
              onAccept: () => _accept(r),
            ),
        ],
      ),
    );

    return NxScrollScaffold(
      header: NxAppHeader(
        title: 'งานช่างของฉัน',
        actions: [
          IconButton(
            key: const ValueKey('my-jobs-search-btn'),
            tooltip: tr('ค้นหา'),
            icon: const Icon(NxI.magnifyingGlass),
            onPressed: () => setState(() => _searching = !_searching),
          ),
          IconButton(
            key: const ValueKey('my-jobs-help'),
            tooltip: tr('ต่างจากใบสั่งงานอย่างไร'),
            icon: const Icon(NxI.info),
            onPressed: _explain,
          ),
        ],
      ),
      body: NxSplitView(
        onClose: () => setState(() => _selected = null),
        list: body,
        detail: _selected == null
            ? null
            : EntityDetailScreen(
                key: ValueKey(_selected!['id']),
                module: 'job',
                row: _selected!,
                embedded: true,
                onDeleted: () => setState(() => _selected = null),
              ),
      ),
    );
  }

  Widget _awaitingCard(BuildContext context) {
    final theme = Theme.of(context);
    const amber = Color(0xFFD97706);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: const ValueKey('jobs-awaiting-me'),
        color: amber.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: amber.withValues(alpha: 0.35))),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(NxI.bellRinging, color: amber, size: 18),
              const SizedBox(width: 8),
              Text(tr('รอคุณรับงาน (${_awaiting.length})'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ]),
            for (final j in _awaiting)
              ListTile(
                key: ValueKey('awaiting-${j['id']}'),
                contentPadding: EdgeInsets.zero,
                title: Text('${j['job_no'] ?? ''} ${j['job_name'] ?? ''}'.trim(), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text([j['customer_name'], if (j['plan_start'] != null) thaiDate(j['plan_start'])].where((e) => e != null && '$e'.isNotEmpty).join(' · ')),
                onTap: () => _open(j),
                trailing: _accepting.contains(strId(j['id']))
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : FilledButton(
                        key: ValueKey('accept-${j['id']}'),
                        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () => _accept(j),
                        child: Text(tr('รับงาน')),
                      ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.onClose, required this.onMore});
  final VoidCallback onClose;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: const ValueKey('my-jobs-hint'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(NxI.info, size: 20, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('หน้านี้แสดงเฉพาะงานที่มอบหมายให้คุณ'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr('ดูและจัดการงานของทั้งทีมได้ที่เมนู "ใบสั่งงาน"'), style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
            TextButton(onPressed: onMore, style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact), child: Text(tr('ต่างกันอย่างไร'))),
          ]),
        ),
        IconButton(key: const ValueKey('my-jobs-hint-close'), icon: const Icon(NxI.x, size: 18), onPressed: onClose),
      ]),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.today, required this.active, required this.overdue, required this.awaiting});
  final int today, active, overdue, awaiting;

  @override
  Widget build(BuildContext context) {
    Widget tile(String key, IconData icon, String label, int n, Color c) => Expanded(
          child: Container(
            key: ValueKey('my-jobs-kpi-$key'),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 18, color: c),
              const SizedBox(height: 6),
              Text('$n', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: c)),
              Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
            ]),
          ),
        );
    return Row(children: [
      tile('today', NxI.calendarCheck, 'วันนี้', today, const Color(0xFF2563EB)),
      const SizedBox(width: 8),
      tile('active', NxI.wrench, 'กำลังทำ', active, const Color(0xFF7C3AED)),
      const SizedBox(width: 8),
      tile('overdue', NxI.warning, 'เลยกำหนด', overdue, const Color(0xFFDC2626)),
      const SizedBox(width: 8),
      tile('awaiting', NxI.bellRinging, 'รอรับ', awaiting, const Color(0xFFD97706)),
    ]);
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(children: [
        Icon(NxI.checkCircle, size: 40, color: cs.outline),
        const SizedBox(height: 10),
        Text(tr(text), textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

Color _statusColor(String st) => switch (st) {
      'In Progress' => const Color(0xFF7C3AED),
      'Waiting' => const Color(0xFFD97706),
      'Completed' => const Color(0xFF16A34A),
      'Cancelled' => const Color(0xFF64748B),
      _ => const Color(0xFF2563EB),
    };

class _JobCard extends StatelessWidget {
  const _JobCard({required this.row, required this.now, required this.journey, required this.accepting, required this.onOpen, required this.onAccept});
  final Map<String, dynamic> row;
  final DateTime now;
  final bool journey;
  final bool accepting;
  final VoidCallback onOpen;
  final VoidCallback onAccept;

  String get _address => '${row['site_address_snapshot'] ?? ''}'.trim().isNotEmpty
      ? '${row['site_address_snapshot']}'.trim()
      : '${row['location_name_snapshot'] ?? ''}'.trim();
  String get _phone => '${row['customer_mobile'] ?? ''}'.replaceAll(RegExp(r'[^0-9+]'), '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final st = canonicalJobStatus(row['job_status']);
    final color = _statusColor(st);
    final d = myJobDate(row);
    final overdue = myJobOverdue(row, now);
    final t0 = DateTime(now.year, now.month, now.day);
    String two(int n) => n.toString().padLeft(2, '0');
    final dayLabel = d == null
        ? tr('ยังไม่นัด')
        : DateTime(d.year, d.month, d.day) == t0
            ? tr('วันนี้')
            : DateTime(d.year, d.month, d.day) == t0.add(const Duration(days: 1))
                ? tr('พรุ่งนี้')
                : '${d.day}/${d.month}';
    final hasTime = d != null && '${row['plan_start'] ?? row['due_datetime']}'.length > 10;
    final customer = '${row['customer_name'] ?? ''}'.trim();
    final contact = '${row['customer_contact_name'] ?? ''}'.trim();
    final id = strId(row['id']);
    final canAccept = journey && (st == 'Open' || st == 'Waiting');

    Widget action(String key, IconData icon, String label, VoidCallback? onTap) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ActionChip(
            key: ValueKey('my-job-$key-$id'),
            avatar: Icon(icon, size: 16),
            label: Text(tr(label)),
            visualDensity: VisualDensity.compact,
            onPressed: onTap,
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: ValueKey('my-job-$id'),
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkWell(
          onTap: onOpen,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: overdue ? cs.error.withValues(alpha: 0.5) : cs.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    width: 74,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    color: color.withValues(alpha: 0.08),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(hasTime ? '${two(d.hour)}:${two(d.minute)}' : '—', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: color)),
                      const SizedBox(height: 2),
                      Text(dayLabel, style: theme.textTheme.labelSmall?.copyWith(color: overdue ? cs.error : cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(child: Text('${row['job_no'] ?? ''}', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
                            child: Text(jobStatusLabel(row['job_status']), style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
                          ),
                          if (overdue) ...[
                            const SizedBox(width: 6),
                            Text(tr('เลยกำหนด'), key: ValueKey('my-job-overdue-$id'), style: theme.textTheme.labelSmall?.copyWith(color: cs.error, fontWeight: FontWeight.w800)),
                          ],
                        ]),
                        const SizedBox(height: 4),
                        Text(entityTitle(row, module: 'job'), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.3)),
                        if (customer.isNotEmpty || contact.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(children: [
                            Icon(NxI.buildings, size: 14, color: cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Expanded(child: Text([customer, contact].where((e) => e.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)),
                          ]),
                        ],
                        if (_address.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(NxI.mapPin, size: 14, color: cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Expanded(child: Text(_address, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(height: 1.35))),
                          ]),
                        ],
                      ]),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Row(children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        if (_address.isNotEmpty)
                          action('nav', NxI.navigationArrow, 'นำทาง', () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(_address)}'), mode: LaunchMode.externalApplication)),
                        if (_phone.isNotEmpty) action('call', NxI.phone, 'โทร', () => launchUrl(Uri.parse('tel:$_phone'))),
                        if (strId(row['related_activity_id']).isNotEmpty)
                          action('checkin', NxI.clock, 'เช็คอิน', () => nxPush<void>(context, ActivityDetailScreen(row: {'id': strId(row['related_activity_id'])}))),
                        action('inspect', NxI.clipboardText, 'ตรวจรับ', () => nxPush<void>(context, JobInspectionScreen(job: row))),
                      ]),
                    ),
                  ),
                  if (canAccept)
                    accepting
                        ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                        : FilledButton(
                            key: ValueKey('my-job-accept-$id'),
                            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                            onPressed: onAccept,
                            child: Text(tr('รับงาน')),
                          )
                  else
                    FilledButton.tonal(
                      key: ValueKey('my-job-open-$id'),
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: onOpen,
                      child: Text(tr(st == 'Completed' ? 'ดูงาน' : 'เปิดงาน')),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

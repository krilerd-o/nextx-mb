import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../widgets/nx_skeleton.dart';
import '../../core/activity_guests.dart' show activityTypeLabel;
import '../../core/app_config.dart';
import '../../core/entity_display.dart' show userDisplayName;
import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_icons.dart';
import '../fsm/contract_flows.dart' show pickUser;
import 'status_followups.dart';

/// "สร้างกิจกรรมของงาน" (Gen Activity): pick a template or one site visit,
/// set the start / spacing / duration / owner / subject prefix, then CONFIRM
/// a preview of exactly what will be created.
///
/// `POST /api/field-service/jobs/:id/generate-activities` accepts
/// `{template_id | items, overrides: {itemKey: {skip, subject, date_start,
/// date_end, owner_user_id}}}` (NEXTX `jobActivityGenService.js`) and has no
/// dry-run. So the preview is computed here from the template, and every
/// included activity is sent with its own `date_start` / `date_end` /
/// `owner_user_id` override: the server creates exactly the previewed rows.

const kGenOwnerRules = ['job_owner', 'creator', 'user', 'matched_technician'];

/// One template item, cleaned the way the server's `sanitizeItems` does.
class JobGenItem {
  const JobGenItem({
    required this.key,
    required this.subject,
    this.type = 'Task',
    this.description = '',
    this.offsetDays = 0,
    this.startTime = '',
    this.durationMin = 60,
    this.allDay = false,
    this.ownerRule = 'job_owner',
    this.ownerUserId,
  });

  final String key;
  final String subject;
  final String type;
  final String description;
  final int offsetDays;

  /// `HH:MM` or empty (= the start time chosen for the run).
  final String startTime;
  final int durationMin;
  final bool allDay;
  final String ownerRule;
  final String? ownerUserId;

  Map<String, dynamic> toJson() => {
        'key': key,
        'subject': subject,
        'activitytype': type,
        if (description.isNotEmpty) 'description': description,
        'offset_days': offsetDays,
        'start_time': startTime,
        'duration_min': durationMin,
        'all_day': allDay,
        'owner_rule': ownerRule,
        if (ownerUserId != null) 'owner_user_id': int.tryParse(ownerUserId!) ?? ownerUserId,
      };
}

int _clampInt(Object? v, int dflt, int min, int max) {
  final n = v is num ? v : num.tryParse('${v ?? ''}');
  if (n == null || !n.isFinite) return dflt;
  return n.truncate().clamp(min, max);
}

String _cut(Object? v, int max) {
  final s = '${v ?? ''}'.trim();
  return s.length > max ? s.substring(0, max) : s;
}

/// Template `items` → [JobGenItem]s (server `sanitizeItems`: key `a{i+1}`
/// when missing, type `Task`, duration 60, offset 0, owner `job_owner`).
List<JobGenItem> jobGenItems(Object? raw) {
  final list = raw is List ? raw : const [];
  return [
    for (var i = 0; i < list.length; i++)
      () {
        final it = list[i] is Map ? Map<String, dynamic>.from(list[i] as Map) : <String, dynamic>{};
        final time = _cut(it['start_time'], 5);
        final rule = kGenOwnerRules.contains(it['owner_rule']) ? it['owner_rule'] as String : 'job_owner';
        final uid = _clampInt(it['owner_user_id'], 0, 0, 1 << 31);
        final key = _cut(it['key'], 40);
        final type = _cut(it['activitytype'], 50);
        return JobGenItem(
          key: key.isEmpty ? 'a${i + 1}' : key,
          subject: _cut(it['subject'], 255),
          type: type.isEmpty ? 'Task' : type,
          description: '${it['description'] ?? ''}',
          offsetDays: _clampInt(it['offset_days'], 0, -365, 3650),
          startTime: RegExp(r'^\d{2}:\d{2}$').hasMatch(time) ? time : '',
          durationMin: _clampInt(it['duration_min'], 60, 5, 60 * 24 * 14),
          allDay: it['all_day'] == true || it['all_day'] == 1,
          ownerRule: rule,
          ownerUserId: rule == 'user' && uid > 0 ? '$uid' : null,
        );
      }(),
  ];
}

/// `{{job_no}}` / `{{job_name}}` / `{{customer_name}}` / `{{job_type}}` (server `interpolateJobVars`).
String interpolateJobVars(String text, Map<String, dynamic> job) => text.replaceAllMapped(
      RegExp(r'\{\{\s*(job_no|job_name|customer_name|job_type)\s*\}\}'),
      (m) => '${job[m.group(1)] ?? ''}',
    );

/// Start of the run by default — the server's `jobBaseDate`: plan start →
/// due date → today 09:00 (Bangkok).
DateTime jobGenBaseDate(Map<String, dynamic> row, {DateTime? now}) {
  final d = parseThaiField(row['plan_start'], 'plan_start', module: 'job') ?? parseThaiField(row['due_datetime'], 'due_datetime', module: 'job');
  if (d != null) return DateTime(d.year, d.month, d.day, d.hour, d.minute);
  final n = now ?? thaiNow();
  return DateTime(n.year, n.month, n.day, 9);
}

/// `YYYY-MM-DD HH:MM:00` — naive Bangkok wall clock, as the server writes.
String genWall(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:00';
}

/// How the activities are spread from the start.
/// `template`: offset days + time of each item (server rule);
/// `chain`: one after another from the start time;
/// `days`: one per [JobGenOptions.gapDays] days at the start time.
class JobGenOptions {
  JobGenOptions({required this.start, this.spacing = 'template', this.gapDays = 1, this.durationMin, this.ownerAll, this.prefix = ''});
  DateTime start;
  String spacing;
  int gapDays;

  /// null: each item's own duration.
  int? durationMin;

  /// One owner for every activity; null: the item's owner rule.
  String? ownerAll;
  String prefix;
}

class JobGenRow {
  const JobGenRow({required this.item, required this.order, required this.subject, required this.start, required this.end, required this.ownerId, required this.skip});
  final JobGenItem item;
  final int order;
  final String subject;
  final DateTime start;
  final DateTime end;
  final String ownerId;
  final bool skip;
  bool get allDay => item.allDay;
}

/// The preview: what `generate-activities` will create, in order.
List<JobGenRow> planJobActivities(
  List<JobGenItem> items,
  JobGenOptions o, {
  required Map<String, dynamic> job,
  required String jobOwnerId,
  required String meId,
  String? matchedId,
  Map<String, String> ownerOf = const {},
  Set<String> skipped = const {},
}) {
  final out = <JobGenRow>[];
  final base = o.start;
  var cursor = base;
  var n = 0;
  final fallbackOwner = jobOwnerId.isNotEmpty ? jobOwnerId : meId;
  for (final it in items) {
    final skip = skipped.contains(it.key);
    final dur = Duration(minutes: o.durationMin ?? it.durationMin);
    DateTime start;
    switch (o.spacing) {
      case 'chain':
        start = cursor;
      case 'days':
        start = base.add(Duration(days: n * o.gapDays));
      default:
        start = DateTime(base.year, base.month, base.day + it.offsetDays, base.hour, base.minute);
        if (it.startTime.isNotEmpty) {
          final p = it.startTime.split(':');
          start = DateTime(start.year, start.month, start.day, int.parse(p[0]), int.parse(p[1]));
        }
    }
    DateTime end;
    if (it.allDay) {
      start = DateTime(start.year, start.month, start.day);
      end = DateTime(start.year, start.month, start.day, 23, 59);
    } else {
      end = start.add(dur);
    }
    if (!skip) {
      n++;
      if (o.spacing == 'chain') cursor = it.allDay ? DateTime(start.year, start.month, start.day + 1, base.hour, base.minute) : end;
    }
    final owner = ownerOf[it.key] ??
        o.ownerAll ??
        switch (it.ownerRule) {
          'creator' => meId,
          'user' => it.ownerUserId ?? fallbackOwner,
          'matched_technician' => matchedId ?? fallbackOwner,
          _ => fallbackOwner,
        };
    final raw = '${o.prefix}${it.subject}';
    out.add(JobGenRow(item: it, order: out.length + 1, subject: interpolateJobVars(raw, job).trim(), start: start, end: end, ownerId: owner, skip: skip));
  }
  return out;
}

/// The request body for [planJobActivities]' rows.
Map<String, dynamic> jobGenBody({Object? templateId, required List<JobGenItem> items, required List<JobGenRow> rows, String prefix = ''}) {
  final overrides = <String, dynamic>{
    for (final r in rows)
      r.item.key: r.skip
          ? {'skip': true}
          : {
              'date_start': genWall(r.start),
              'date_end': genWall(r.end),
              if (r.ownerId.isNotEmpty) 'owner_user_id': int.tryParse(r.ownerId) ?? r.ownerId,
              if (prefix.isNotEmpty) 'subject': '$prefix${r.item.subject}',
            },
  };
  return {
    if (templateId != null) 'template_id': templateId else 'items': [for (final i in items) i.toJson()],
    'overrides': overrides,
  };
}

const _thDays = ['จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];
const _thMonths = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];

String _two(int n) => n.toString().padLeft(2, '0');

/// `ศ. 14 พ.ย. 2569` / `Fri 14 Nov 2026`.
String genDay(DateTime d) => '${tr(_thDays[d.weekday - 1])} ${d.day} ${tr(_thMonths[d.month - 1])} ${uiYear(d.year)}';

String genHm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// `ศ. 14 พ.ย. 2569 · 09:00–10:00` (end on another day: with its date).
String genWhen(JobGenRow r) {
  if (r.allDay) return '${genDay(r.start)} · ${tr('ทั้งวัน')}';
  final sameDay = r.start.year == r.end.year && r.start.month == r.end.month && r.start.day == r.end.day;
  return sameDay ? '${genDay(r.start)} · ${genHm(r.start)}–${genHm(r.end)}' : '${genDay(r.start)} ${genHm(r.start)} – ${genDay(r.end)} ${genHm(r.end)}';
}

IconData genTypeIcon(String t) => switch (t) {
      'Visit' => NxI.mapPin,
      'Call' => NxI.phone,
      'Meeting' => NxI.users,
      'Task' => NxI.checkSquare,
      _ => NxI.calendarCheck,
    };

String _durLabel(int m) => m % 60 == 0 ? tr('${m ~/ 60} ชม.') : tr('$m นาที');

/// Opens the Gen Activity page; true when activities were created.
Future<bool> showJobActivityGenSheet(BuildContext context, {required String jobId, Map<String, dynamic> row = const {}}) async {
  final ok = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => JobActivityGenScreen(jobId: jobId, row: row)),
  );
  return ok == true;
}

class JobActivityGenScreen extends StatefulWidget {
  const JobActivityGenScreen({super.key, required this.jobId, this.row = const {}});
  final String jobId;
  final Map<String, dynamic> row;

  @override
  State<JobActivityGenScreen> createState() => _JobActivityGenScreenState();
}

class _JobActivityGenScreenState extends State<JobActivityGenScreen> {
  static const _single = '__single__';

  int _step = 0;
  bool _loading = true;
  String? _loadError;
  List<Map<String, dynamic>> _templates = const [];
  List<Map<String, dynamic>> _users = const [];
  String? _matchedId;

  /// Template id, or [_single].
  String? _pick;
  late JobGenOptions _o;
  final _subject = TextEditingController();
  final _prefix = TextEditingController();
  String _type = 'Visit';
  final Map<String, String> _ownerOf = {};
  final Set<String> _skipped = {};
  bool _busy = false;
  int? _created;

  Map<String, dynamic> get _job => widget.row;
  String get _jobOwnerId => '${_job['smownerid'] ?? ''}'.trim();
  String get _meId => context.read<AppConfig>().session.userId ?? '';
  DateTime get _defaultStart => jobGenBaseDate(_job);

  @override
  void initState() {
    super.initState();
    _o = JobGenOptions(start: _defaultStart);
    _subject.text = tr('เข้าหน้างาน');
    _load();
  }

  @override
  void dispose() {
    _subject.dispose();
    _prefix.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AppConfig>().apiClient;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final t = await api.getJobActivityTemplates();
      _templates = [for (final x in t) if (jobGenItems(x['items']).isNotEmpty) x];
    } catch (e) {
      _loadError = journeyErrorText(e);
    }
    try {
      _users = await api.getUsersCached();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _ensureMatched(List<JobGenItem> items) async {
    if (_matchedId != null || !items.any((i) => i.ownerRule == 'matched_technician')) return;
    try {
      final data = await context.read<AppConfig>().apiClient.matchJobUsers(widget.jobId);
      final list = extractMapList(data['candidates'] ?? data);
      final members = {for (final u in _users) '${u['user_id'] ?? u['id']}'};
      for (final c in list) {
        final id = '${c['user_id'] ?? c['id'] ?? ''}';
        if ((c['score'] is num ? c['score'] as num : 0) > 0 && (members.isEmpty || members.contains(id))) {
          _matchedId = id;
          break;
        }
      }
    } catch (_) {}
    _matchedId ??= '';
    if (mounted) setState(() {});
  }

  Map<String, dynamic>? get _template => _pick == null || _pick == _single ? null : _templates.where((t) => '${t['id']}' == _pick).firstOrNull;

  List<JobGenItem> get _items {
    final t = _template;
    if (t != null) return jobGenItems(t['items']);
    if (_pick == _single) {
      return [
        JobGenItem(
          key: 'k1',
          subject: _subject.text.trim(),
          type: _type,
          durationMin: _o.durationMin ?? 60,
          startTime: genHm(_o.start),
          ownerRule: 'job_owner',
        ),
      ];
    }
    return const [];
  }

  List<JobGenRow> get _rows => planJobActivities(
        _items,
        _o..prefix = _template == null ? '' : _prefix.text,
        job: _job,
        jobOwnerId: _jobOwnerId,
        meId: _meId,
        matchedId: (_matchedId ?? '').isEmpty ? null : _matchedId,
        ownerOf: _ownerOf,
        skipped: _skipped,
      );

  String _userName(String id) {
    if (id.isEmpty) return tr('ยังไม่ระบุ');
    for (final u in _users) {
      if ('${u['user_id'] ?? u['id']}' == id) return userDisplayName(u);
    }
    if (id == _jobOwnerId) {
      final n = '${_job['smownerid_name'] ?? _job['owner_name'] ?? ''}'.trim();
      if (n.isNotEmpty) return n;
    }
    if (id == _meId) return context.read<AppConfig>().session.displayName ?? tr('ฉัน');
    return '#$id';
  }

  void _choose(String pick) {
    setState(() {
      _pick = pick;
      _ownerOf.clear();
      _skipped.clear();
      _o = JobGenOptions(start: _o.start, spacing: pick == _single ? 'chain' : 'template', durationMin: pick == _single ? 60 : null);
      _prefix.clear();
      _step = 1;
    });
    _ensureMatched(_items);
  }

  Future<void> _submit() async {
    final rows = _rows;
    final n = rows.where((r) => !r.skip).length;
    if (n == 0 || _busy) return;
    final body = jobGenBody(templateId: _template == null ? null : (_template!['id']), items: _items, rows: rows, prefix: _template == null ? '' : _prefix.text);
    setState(() => _busy = true);
    try {
      final r = await context.read<AppConfig>().apiClient.generateJobActivities(widget.jobId, body);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _created = r['created'] is num ? (r['created'] as num).toInt() : ((r['activity_ids'] as List?)?.length ?? n);
        _step = 3;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(journeyErrorText(e)))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final jobLabel = ['${_job['job_no'] ?? ''}', '${_job['job_name'] ?? ''}'].where((e) => e.trim().isNotEmpty).join(' · ');
    return PopScope(
      canPop: _step == 0 || _step == 3,
      onPopInvokedWithResult: (did, _) {
        if (!did && !_busy) setState(() => _step = _step - 1);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const ValueKey('gen-close'),
            tooltip: tr('ปิด'),
            icon: const Icon(NxI.x),
            onPressed: () => Navigator.of(context).pop(_step == 3),
          ),
          titleSpacing: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('สร้างกิจกรรมของงาน'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            if (jobLabel.isNotEmpty) Text(jobLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
        body: Column(children: [
          if (_step < 3) _stepper(theme),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey('gen-step-$_step'),
                child: switch (_step) {
                  0 => _pickStep(theme),
                  1 => _optionsStep(theme),
                  2 => _confirmStep(theme),
                  _ => _doneStep(theme),
                },
              ),
            ),
          ),
        ]),
        bottomNavigationBar: _step == 0 ? null : _bottomBar(theme),
      ),
    );
  }

  Widget _stepper(ThemeData theme) {
    final cs = theme.colorScheme;
    const labels = ['รูปแบบ', 'ตั้งค่า', 'ยืนยัน'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) Expanded(child: Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 6), color: i <= _step ? cs.primary : cs.outlineVariant)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: i <= _step ? cs.primary : cs.surfaceContainerHighest),
              child: i < _step
                  ? Icon(NxI.check, size: 14, color: cs.onPrimary)
                  : Text('${i + 1}', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: i <= _step ? cs.onPrimary : cs.onSurfaceVariant)),
            ),
            const SizedBox(width: 6),
            Text(tr(labels[i]), style: theme.textTheme.labelLarge?.copyWith(fontWeight: i == _step ? FontWeight.w800 : FontWeight.w500, color: i == _step ? cs.onSurface : cs.onSurfaceVariant)),
          ]),
        ],
      ]),
    );
  }

  Widget _section(ThemeData theme, String title, {String? hint, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(tr(hint), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 8),
        child,
      ]),
    );
  }

  BoxDecoration _cardDeco(ColorScheme cs, {bool selected = false}) => BoxDecoration(
        color: selected ? cs.primary.withValues(alpha: 0.08) : cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.7), width: selected ? 1.6 : 1),
      );

  // ---------------------------------------------------------------- step 1

  Widget _pickStep(ThemeData theme) {
    final cs = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _choiceCard(
          theme,
          key: const ValueKey('gen-pick-single'),
          icon: NxI.mapPin,
          title: tr('กิจกรรมเดียว (เข้าหน้างาน)'),
          subtitle: tr('นัดเข้าหน้างาน 1 ครั้ง — ตั้งหัวข้อ เวลา และผู้รับผิดชอบเอง'),
          badge: tr('1 กิจกรรม'),
          onTap: () => _choose(_single),
        ),
        const SizedBox(height: 18),
        Text(tr('จากเทมเพลต'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (_loading)
          const NxSkeletonRows(key: ValueKey('job-activity-templates-skeleton'), count: 3, padded: false, top: 0, leading: NxSkelLeading.icon, leadingSize: 40, trailing: NxSkelTrailing.chevron)
        else if (_loadError != null)
          Container(
            key: const ValueKey('gen-templates-error'),
            padding: const EdgeInsets.all(14),
            decoration: _cardDeco(cs),
            child: Row(children: [
              Icon(NxI.warningCircle, color: cs.error),
              const SizedBox(width: 10),
              Expanded(child: Text('${tr('โหลดเทมเพลตไม่สำเร็จ')} — ${tr(_loadError!)}', style: theme.textTheme.bodyMedium)),
              TextButton(onPressed: _load, child: Text(tr('ลองใหม่'))),
            ]),
          )
        else if (_templates.isEmpty)
          Container(
            key: const ValueKey('gen-templates-empty'),
            padding: const EdgeInsets.all(14),
            decoration: _cardDeco(cs),
            child: Row(children: [
              Icon(NxI.info, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr('ยังไม่มีเทมเพลตกิจกรรม — ผู้ดูแลตั้งได้ที่เว็บ: ตั้งค่า → ใบสั่งงาน → เทมเพลตกิจกรรม'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ]),
          )
        else
          for (final t in _templates) ...[
            _templateCard(theme, t),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _choiceCard(ThemeData theme, {required Key key, required IconData icon, required String title, String? subtitle, String? badge, required VoidCallback onTap, Widget? extra}) {
    final cs = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: _cardDeco(cs),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 20, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ]),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                  child: Text(badge, style: theme.textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
                ),
              ],
            ]),
            ?extra,
          ]),
        ),
      ),
    );
  }

  Widget _templateCard(ThemeData theme, Map<String, dynamic> t) {
    final cs = theme.colorScheme;
    final items = jobGenItems(t['items']);
    final name = '${(L10n.isEn ? (t['name_en'] ?? t['name']) : t['name']) ?? ''}';
    final desc = '${t['description'] ?? ''}'.trim();
    final cat = '${t['category'] ?? ''}'.trim();
    return _choiceCard(
      theme,
      key: ValueKey('act-template-${t['id']}'),
      icon: NxI.listChecks,
      title: name,
      subtitle: [if (cat.isNotEmpty) cat, if (desc.isNotEmpty) desc].join(' · '),
      badge: tr('${items.length} กิจกรรม'),
      onTap: () => _choose('${t['id']}'),
      extra: Padding(
        padding: const EdgeInsets.only(top: 10, left: 52),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final it in items.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(children: [
                Icon(genTypeIcon(it.type), size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(interpolateJobVars(it.subject, _job), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                ),
                if (it.offsetDays != 0) Text(tr('+${it.offsetDays} วัน'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          if (items.length > 3) Text(tr('อีก ${items.length - 3} รายการ'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- step 2

  Widget _chips(List<(Key, String, bool, VoidCallback)> chips) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in chips) ChoiceChip(key: c.$1, label: Text(c.$2), selected: c.$3, onSelected: (_) => c.$4()),
        ],
      );

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _o.start,
      firstDate: thaiNow().subtract(const Duration(days: 365)),
      lastDate: thaiNow().add(const Duration(days: 730)),
    );
    if (d != null) setState(() => _o.start = DateTime(d.year, d.month, d.day, _o.start.hour, _o.start.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: _o.start.hour, minute: _o.start.minute));
    if (t != null) setState(() => _o.start = DateTime(_o.start.year, _o.start.month, _o.start.day, t.hour, t.minute));
  }

  Future<void> _pickOwner({String? forKey}) async {
    final id = await pickUser(context, title: tr(forKey == null ? 'ผู้รับผิดชอบทุกกิจกรรม' : 'ผู้รับผิดชอบกิจกรรมนี้'));
    if (id == null || !mounted) return;
    setState(() {
      if (forKey == null) {
        _o.ownerAll = id;
        _ownerOf.clear();
      } else {
        _ownerOf[forKey] = id;
      }
    });
  }

  Widget _optionsStep(ThemeData theme) {
    final cs = theme.colorScheme;
    final single = _pick == _single;
    final t = _template;
    final now = thaiNow();
    final planned = parseThaiField(_job['plan_start'], 'plan_start', module: 'job');
    bool sameDay(DateTime? a, DateTime b) => a != null && a.year == b.year && a.month == b.month && a.day == b.day;
    void setDay(DateTime d) => setState(() => _o.start = DateTime(d.year, d.month, d.day, _o.start.hour, _o.start.minute));
    void setTime(int h, int m) => setState(() => _o.start = DateTime(_o.start.year, _o.start.month, _o.start.day, h, m));
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final hm = genHm(_o.start);
    final ownerName = _o.ownerAll == null ? null : _userName(_o.ownerAll!);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 18),
          decoration: _cardDeco(cs, selected: true),
          child: Row(children: [
            Icon(single ? NxI.mapPin : NxI.listChecks, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(single ? tr('กิจกรรมเดียว (เข้าหน้างาน)') : '${t?['name'] ?? ''}',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ),
            TextButton(key: const ValueKey('gen-change-pick'), onPressed: () => setState(() => _step = 0), child: Text(tr('เปลี่ยน'))),
          ]),
        ),
        if (single) ...[
          _section(
            theme,
            'หัวข้อ',
            child: TextField(
              key: const ValueKey('gen-subject'),
              controller: _subject,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: tr('เช่น เข้าหน้างาน ตรวจเช็คแอร์')),
            ),
          ),
          _section(
            theme,
            'ประเภท',
            child: _chips([
              for (final ty in const ['Visit', 'Call', 'Meeting', 'Task']) (ValueKey('gen-type-$ty'), tr(activityTypeLabel(ty)), _type == ty, () => setState(() => _type = ty)),
            ]),
          ),
        ],
        _section(
          theme,
          'เริ่ม',
          hint: single ? null : 'วันของกิจกรรมแรก — กิจกรรมถัดไปเลื่อนตามระยะห่างที่เลือก',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _chips([
              if (planned != null) (const ValueKey('gen-day-plan'), tr('วันนัดงาน'), sameDay(planned, _o.start), () => setDay(planned)),
              (const ValueKey('gen-day-today'), tr('วันนี้'), sameDay(now, _o.start), () => setDay(now)),
              (const ValueKey('gen-day-tomorrow'), tr('พรุ่งนี้'), sameDay(tomorrow, _o.start), () => setDay(tomorrow)),
            ]),
            const SizedBox(height: 8),
            _chips([
              for (final (h, m) in const [(8, 0), (9, 0), (13, 0)]) (ValueKey('gen-time-$h'), '${_two(h)}:${_two(m)}', hm == '${_two(h)}:${_two(m)}', () => setTime(h, m)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('gen-pick-date'),
                  onPressed: _pickDate,
                  icon: const Icon(NxI.calendarBlank, size: 18),
                  label: Text(genDay(_o.start), key: const ValueKey('gen-start-day')),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const ValueKey('gen-pick-time'),
                onPressed: _pickTime,
                icon: const Icon(NxI.clock, size: 18),
                label: Text(hm, key: const ValueKey('gen-start-time')),
              ),
            ]),
          ]),
        ),
        if (!single)
          _section(
            theme,
            'ระยะห่างระหว่างกิจกรรม',
            child: _chips([
              (const ValueKey('gen-spacing-template'), tr('ตามเทมเพลต'), _o.spacing == 'template', () => setState(() => _o.spacing = 'template')),
              (const ValueKey('gen-spacing-chain'), tr('ต่อกันวันเดียว'), _o.spacing == 'chain', () => setState(() => _o.spacing = 'chain')),
              for (final d in const [1, 2, 7])
                (ValueKey('gen-spacing-$d'), tr(d == 7 ? 'ห่าง 1 สัปดาห์' : 'ห่าง $d วัน'), _o.spacing == 'days' && _o.gapDays == d, () => setState(() {
                      _o.spacing = 'days';
                      _o.gapDays = d;
                    })),
            ]),
          ),
        _section(
          theme,
          'ระยะเวลาต่อกิจกรรม',
          child: _chips([
            if (!single) (const ValueKey('gen-duration-0'), tr('ตามเทมเพลต'), _o.durationMin == null, () => setState(() => _o.durationMin = null)),
            for (final m in const [30, 60, 120, 240]) (ValueKey('gen-duration-$m'), _durLabel(m), _o.durationMin == m, () => setState(() => _o.durationMin = m)),
          ]),
        ),
        _section(
          theme,
          'ผู้รับผิดชอบ',
          hint: 'เปลี่ยนรายกิจกรรมได้ในขั้นยืนยัน',
          child: _chips([
            if (!single) (const ValueKey('gen-owner-rule'), tr('ตามเทมเพลต'), _o.ownerAll == null, () => setState(() => _o.ownerAll = null)),
            if (_jobOwnerId.isNotEmpty)
              (const ValueKey('gen-owner-job'), '${tr('เจ้าของงาน')} · ${_userName(_jobOwnerId)}', _o.ownerAll == _jobOwnerId || (single && _o.ownerAll == null), () => setState(() {
                    _o.ownerAll = _jobOwnerId;
                    _ownerOf.clear();
                  })),
            if (_meId.isNotEmpty && _meId != _jobOwnerId)
              (const ValueKey('gen-owner-me'), tr('ฉัน'), _o.ownerAll == _meId, () => setState(() {
                    _o.ownerAll = _meId;
                    _ownerOf.clear();
                  })),
            (
              const ValueKey('gen-owner-pick'),
              ownerName != null && _o.ownerAll != _jobOwnerId && _o.ownerAll != _meId ? ownerName : tr('เลือกคน…'),
              ownerName != null && _o.ownerAll != _jobOwnerId && _o.ownerAll != _meId,
              () => _pickOwner(),
            ),
          ]),
        ),
        if (!single)
          _section(
            theme,
            'คำนำหน้าหัวข้อ',
            hint: 'ใส่หน้าหัวข้อทุกกิจกรรม (ไม่บังคับ)',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                key: const ValueKey('gen-prefix'),
                controller: _prefix,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(hintText: tr('เช่น [JOB-001]')),
              ),
              if ('${_job['job_no'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    key: const ValueKey('gen-prefix-jobno'),
                    avatar: const Icon(NxI.hash, size: 16),
                    label: Text(tr('ใส่เลขงาน')),
                    onPressed: () => setState(() => _prefix.text = '[${_job['job_no']}] '),
                  ),
                ),
              ],
            ]),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(NxI.info, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(tr('ทุกกิจกรรมผูกกับใบสั่งงานนี้ · สถานที่ การแจ้งเตือน และรายละเอียดอื่นแก้ต่อได้ในแต่ละกิจกรรม'),
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ]),
      ],
    );
  }

  // ---------------------------------------------------------------- step 3

  Widget _confirmStep(ThemeData theme) {
    final cs = theme.colorScheme;
    final rows = _rows;
    final n = rows.where((r) => !r.skip).length;
    final counts = <String, int>{};
    for (final r in rows.where((r) => !r.skip)) {
      counts[r.ownerId] = (counts[r.ownerId] ?? 0) + 1;
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Container(
          key: const ValueKey('gen-confirm-summary'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('จะสร้าง $n กิจกรรม'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
            const SizedBox(height: 4),
            Text(
              [
                _template == null ? tr('กิจกรรมเดียว (เข้าหน้างาน)') : '${_template!['name']}',
                if ('${_job['job_no'] ?? ''}'.isNotEmpty) '${tr('ผูกกับ')} ${_job['job_no']}',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (counts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in counts.entries)
                  Container(
                    padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
                    decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(99)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      NxAvatar(label: _userName(e.key), size: 22),
                      const SizedBox(width: 6),
                      Text('${_userName(e.key)} · ${e.value}', style: theme.textTheme.labelMedium),
                    ]),
                  ),
              ]),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        for (final r in rows) ...[
          _previewRow(theme, r),
          const SizedBox(height: 8),
        ],
        if (rows.length > 1)
          Text(tr('ปิดสวิตช์เพื่อข้ามกิจกรรมที่ไม่ต้องการ · แตะชื่อเพื่อเปลี่ยนผู้รับผิดชอบ'),
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }

  Widget _previewRow(ThemeData theme, JobGenRow r) {
    final cs = theme.colorScheme;
    final name = _userName(r.ownerId);
    final multi = _items.length > 1;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: r.skip ? 0.45 : 1,
      child: Container(
        key: ValueKey('gen-row-${r.item.key}'),
        padding: const EdgeInsets.fromLTRB(12, 12, 6, 10),
        decoration: _cardDeco(cs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary.withValues(alpha: 0.14)),
            child: Text('${r.order}', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.subject.isEmpty ? '—' : r.subject,
                  key: ValueKey('gen-row-subject-${r.item.key}'),
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700, decoration: r.skip ? TextDecoration.lineThrough : null)),
              const SizedBox(height: 4),
              Row(children: [
                Icon(genTypeIcon(r.item.type), size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(tr(activityTypeLabel(r.item.type)), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Icon(NxI.calendarClock, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Flexible(child: Text(genWhen(r), key: ValueKey('gen-row-when-${r.item.key}'), style: theme.textTheme.labelMedium)),
              ]),
              const SizedBox(height: 6),
              InkWell(
                key: ValueKey('gen-row-owner-${r.item.key}'),
                borderRadius: BorderRadius.circular(99),
                onTap: r.skip ? null : () => _pickOwner(forKey: r.item.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    NxAvatar(label: name, size: 22),
                    const SizedBox(width: 6),
                    Flexible(child: Text(name, key: ValueKey('gen-row-owner-name-${r.item.key}'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700))),
                    const SizedBox(width: 2),
                    Icon(NxI.caretDown, size: 14, color: cs.onSurfaceVariant),
                  ]),
                ),
              ),
            ]),
          ),
          if (multi)
            Switch(
              key: ValueKey('gen-row-skip-${r.item.key}'),
              value: !r.skip,
              onChanged: (on) => setState(() => on ? _skipped.remove(r.item.key) : _skipped.add(r.item.key)),
            ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- done

  Widget _doneStep(ThemeData theme) {
    final cs = theme.colorScheme;
    const ok = Color(0xFF16A34A);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(shape: BoxShape.circle, color: ok.withValues(alpha: 0.14)),
            child: const Icon(NxI.checkCircleFill, size: 48, color: ok),
          ),
          const SizedBox(height: 18),
          Text(tr('สร้าง ${_created ?? 0} กิจกรรมแล้ว'), key: const ValueKey('gen-done-title'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(tr('แจ้งผู้รับผิดชอบแล้ว — ดูได้ในรายการกิจกรรมของงาน'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }

  Widget _bottomBar(ThemeData theme) {
    final rows = _step == 2 ? _rows : const <JobGenRow>[];
    final n = rows.where((r) => !r.skip).length;
    final canNext = _step != 1 || _pick != _single || _subject.text.trim().isNotEmpty;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: _step == 3
            ? SizedBox(
                height: 52,
                child: FilledButton(key: const ValueKey('gen-done'), style: FilledButton.styleFrom(shape: shape), onPressed: () => Navigator.of(context).pop(true), child: Text(tr('เสร็จ'))),
              )
            : Row(children: [
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    key: const ValueKey('gen-back'),
                    style: OutlinedButton.styleFrom(shape: shape),
                    onPressed: _busy ? null : () => setState(() => _step -= 1),
                    child: Text(tr('ย้อนกลับ')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: _step == 1
                        ? FilledButton.icon(
                            key: const ValueKey('gen-next'),
                            style: FilledButton.styleFrom(shape: shape),
                            onPressed: canNext ? () => setState(() => _step = 2) : null,
                            icon: const Icon(NxI.eye, size: 18),
                            label: Text(tr('ดูตัวอย่างก่อนสร้าง')),
                          )
                        : FilledButton.icon(
                            key: const ValueKey('gen-confirm'),
                            style: FilledButton.styleFrom(shape: shape),
                            onPressed: n == 0 || _busy ? null : _submit,
                            icon: _busy
                                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(NxI.calendarPlus, size: 18),
                            label: Text(tr('สร้าง $n กิจกรรม')),
                          ),
                  ),
                ),
              ]),
      ),
    );
  }
}

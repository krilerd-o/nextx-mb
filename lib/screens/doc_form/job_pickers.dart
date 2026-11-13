import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/doc_form/doc_form_rules.dart' show siteAddressOf, ymd;
import '../../core/doc_form/doc_pick_rules.dart' show DocRecentPicks;
import '../../core/doc_form/job_form_rules.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../services/geo_address.dart';
import '../../widgets/fields/nx_thai_address_set.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_map_pin_picker.dart';
import 'barcode_scan_sheet.dart' show DocFormHooks;
import 'doc_pickers.dart';

/// Search pages of the job form: case / service contract / asset (paged
/// server search with status / customer / owner filters), technicians
/// (skill match + who is free at the planned time) and the work site
/// (customer addresses, service locations, map pin, Thai address set).
/// Full-screen on a phone, a dialog on a tablet ([showDocPicker]).

String _s(Object? v) {
  if (v == null) return '';
  final t = '$v'.trim();
  return t == 'null' ? '' : t;
}

const _caseTint = Color(0xFFF97316);
const _contractTint = Color(0xFF0EA5E9);
const _assetTint = Color(0xFF8B5CF6);
const _locTint = Color(0xFF10B981);
const _ok = Color(0xFF16A34A);
const _warn = Color(0xFFD97706);
const _bad = Color(0xFFDC2626);

// ──────────────────────────────────────────────────────── shared row

/// One row of a job picker: tinted icon, title (+ badges), subtitle lines.
class JobPickRow extends StatelessWidget {
  const JobPickRow({
    super.key,
    required this.icon,
    required this.tint,
    required this.title,
    this.subtitle,
    this.extra,
    this.badges = const [],
    this.selected = false,
    this.onTap,
    this.leading,
    this.trailing,
  });
  final IconData icon;
  final Color tint;
  final String title;
  final String? subtitle;
  final String? extra;
  final List<Widget> badges;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: selected ? cs.primary.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            leading ??
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: tint.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, size: 20, color: tint),
                ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                if (badges.isNotEmpty || (extra != null && extra!.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      ...badges,
                      if (extra != null && extra!.isNotEmpty) Text(extra!, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                  ),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), Padding(padding: const EdgeInsets.only(top: 8), child: trailing!)],
          ]),
        ),
      ),
    );
  }
}

Widget _check(BuildContext context) => Icon(NxI.check, color: Theme.of(context).colorScheme.primary, size: 20);

Widget _spinner() => const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
    );

// ─────────────────────────────────────────── paged entity search (generic)

/// A filter chip of [JobEntityPickerPage]. Chips of one [group] are
/// exclusive (always one on); a chip without a group toggles.
class JobPickChip {
  const JobPickChip(this.key, this.label, {this.icon, this.group, this.filters = const {}});
  final String key;
  final String label;
  final IconData? icon;
  final String? group;

  /// Query params while the chip is on (`filter[col]` …).
  final Map<String, String> filters;
}

/// How a record shows in [JobEntityPickerPage].
class JobPickView {
  const JobPickView({required this.title, this.subtitle, this.extra, this.badges = const []});
  final String title;
  final String? subtitle;
  final String? extra;
  final List<(String, Color)> badges;
}

/// Server search of one module (`GET /api/entity/:module`, 300 ms debounce,
/// 30 per page, endless scroll) with filter chips and "ไม่ระบุ".
class JobEntityPickerPage extends StatefulWidget {
  const JobEntityPickerPage({
    super.key,
    required this.api,
    required this.module,
    required this.title,
    required this.keyPrefix,
    required this.searchHint,
    required this.icon,
    required this.tint,
    required this.view,
    this.chips = const [],
    this.initialOn = const {},
    this.selectedId,
    this.noneTitle,
    this.noneSubtitle,
    this.emptyText,
  });
  final ApiClient api;
  final String module;
  final String title;
  final String keyPrefix;
  final String searchHint;
  final IconData icon;
  final Color tint;
  final JobPickView Function(Map<String, dynamic> row) view;
  final List<JobPickChip> chips;
  final Set<String> initialOn;
  final String? selectedId;

  /// A first row that clears the pick (null = none offered).
  final String? noneTitle;
  final String? noneSubtitle;
  final String? emptyText;

  @override
  State<JobEntityPickerPage> createState() => _JobEntityPickerPageState();
}

class _JobEntityPickerPageState extends State<JobEntityPickerPage> {
  final _q = TextEditingController();
  final _scroll = ScrollController();
  late final Set<String> _on = {...widget.initialOn};
  Timer? _debounce;
  String _lastQ = '';
  List<Map<String, dynamic>> _rows = const [];
  int _page = 1;
  bool _more = false;
  bool _loading = true;
  Object? _error;
  int _token = 0;
  int? _total;

  static const _limit = 30;

  @override
  void initState() {
    super.initState();
    _q.addListener(() {
      if (_q.text.trim() == _lastQ) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        _lastQ = _q.text.trim();
        _load();
      });
    });
    _scroll.addListener(() {
      if (_more && !_loading && _scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _load(more: true);
    });
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Map<String, String> get _params => {
        'with_total': '1',
        for (final c in widget.chips)
          if (_on.contains(c.key)) ...c.filters,
      };

  Future<void> _load({bool more = false}) async {
    final token = ++_token;
    final page = more ? _page + 1 : 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await widget.api.getEntityList(widget.module, q: _q.text.trim(), page: page, limit: _limit, extra: _params);
      if (!mounted || token != _token) return;
      setState(() {
        _rows = more ? [..._rows, ...p.items] : p.items;
        _page = page;
        _total = p.total;
        _more = p.items.length >= _limit && (p.total == null || _rows.length < p.total!);
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _toggle(JobPickChip c) {
    setState(() {
      if (c.group != null) {
        for (final o in widget.chips) {
          if (o.group == c.group) _on.remove(o.key);
        }
        _on.add(c.key);
      } else if (!_on.remove(c.key)) {
        _on.add(c.key);
      }
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim();
    final children = <Widget>[
      if (widget.noneTitle != null && widget.selectedId != null)
        JobPickRow(
          key: ValueKey('${widget.keyPrefix}-none'),
          icon: NxI.x,
          tint: Theme.of(context).colorScheme.onSurfaceVariant,
          title: tr(widget.noneTitle!),
          subtitle: widget.noneSubtitle == null ? null : tr(widget.noneSubtitle!),
          onTap: () => Navigator.of(context).pop(const PickedRecord('none', {})),
        ),
    ];
    if (_error != null && _rows.isEmpty) {
      children.add(DocPickerState(
        key: const ValueKey('picker-error'),
        icon: NxI.warningCircle,
        title: 'โหลดรายการไม่สำเร็จ',
        text: formatApiError(_error!),
        action: OutlinedButton.icon(key: const ValueKey('picker-retry'), onPressed: _load, icon: const Icon(NxI.arrowCounterClockwise, size: 18), label: Text(tr('ลองอีกครั้ง'))),
      ));
    } else {
      if (_rows.isNotEmpty) {
        children.add(DocPickerSection(q.isEmpty ? (_total == null ? 'รายการ' : 'รายการ ($_total)') : 'ผลการค้นหา'));
      }
      for (final r in _rows) {
        final v = widget.view(r);
        final id = _s(r['id']);
        children.add(JobPickRow(
          key: ValueKey('${widget.keyPrefix}-hit-$id'),
          icon: widget.icon,
          tint: widget.tint,
          title: v.title,
          subtitle: v.subtitle,
          extra: v.extra,
          badges: [for (final (t, c) in v.badges) DocPickerBadge(text: t, color: c)],
          selected: id == widget.selectedId,
          trailing: id == widget.selectedId ? _check(context) : null,
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).pop(PickedRecord(widget.module, r));
          },
        ));
      }
      if (_more) children.add(_spinner());
      if (!_loading && _rows.isEmpty) {
        children.add(DocPickerState(
          key: const ValueKey('picker-empty'),
          icon: NxI.magnifyingGlass,
          title: q.isEmpty ? 'ไม่มีรายการตามตัวกรองนี้' : 'ไม่พบ "$q"',
          text: widget.emptyText ?? 'ลองปิดตัวกรอง หรือค้นด้วยคำอื่น',
        ));
      }
    }
    return DocPickerFrame(
      pageKey: ValueKey('${widget.keyPrefix}-picker'),
      title: widget.title,
      search: DocPickerSearchBox(controller: _q, fieldKey: ValueKey('${widget.keyPrefix}-search'), hint: widget.searchHint, loading: _loading, autofocus: false),
      filters: widget.chips.isEmpty
          ? null
          : DocPickerChips(children: [
              for (final c in widget.chips)
                docPickerFilterChip(context, key: ValueKey('${widget.keyPrefix}-chip-${c.key}'), label: c.label, icon: c.icon, selected: _on.contains(c.key), onTap: () => _toggle(c)),
            ]),
      body: ListView(key: ValueKey('${widget.keyPrefix}-results'), controller: _scroll, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: children),
    );
  }
}

// ─────────────────────────────────────────────────── case / contract

(String, Color) _statusBadge(JobLinkView v) => (v.status, v.closed ? const Color(0xFF64748B) : _ok);

/// Cases: open ones of this customer first; all statuses / all customers /
/// mine on the chips. `none` = unlink.
Future<PickedRecord?> showJobCasePicker(BuildContext context, {required ApiClient api, String? userId, String? accountId, String? accountName, String? selectedId}) =>
    showDocPicker<PickedRecord>(
      context,
      (_) => JobEntityPickerPage(
        api: api,
        module: 'case',
        title: 'เลือกเคส',
        keyPrefix: 'case',
        searchHint: 'เลขที่เคส ชื่อเคส หรือชื่อลูกค้า',
        icon: NxI.lifeBuoy,
        tint: _caseTint,
        selectedId: selectedId,
        noneTitle: 'ไม่เชื่อมกับเคส',
        chips: [
          JobPickChip('open', 'เปิดอยู่', group: 'status', filters: {'filter[case_status]': kOpenCaseStatuses.join(',')}),
          const JobPickChip('all', 'ทุกสถานะ', group: 'status'),
          if (accountId != null) JobPickChip('account', accountName == null ? 'ของลูกค้านี้' : 'ของ $accountName', icon: NxI.buildings, filters: {'filter[related_account_id]': accountId}),
          if (userId != null) JobPickChip('mine', 'ของฉัน', icon: NxI.userCircle, filters: {'filter[smownerid]': userId}),
        ],
        initialOn: {'open', if (accountId != null) 'account'},
        view: (r) {
          final v = jobLinkView('case', r);
          return JobPickView(title: v.heading, subtitle: v.customer, extra: v.extra, badges: [if (v.status.isNotEmpty) _statusBadge(v)]);
        },
      ),
    );

/// Service contracts: active ones of this customer first; ใกล้หมดอายุ /
/// all statuses / mine on the chips. `none` = unlink.
Future<PickedRecord?> showJobContractPicker(BuildContext context, {required ApiClient api, String? userId, String? accountId, String? accountName, String? selectedId}) =>
    showDocPicker<PickedRecord>(
      context,
      (_) => JobEntityPickerPage(
        api: api,
        module: 'service_contract',
        title: 'เลือกสัญญาบริการ',
        keyPrefix: 'contract',
        searchHint: 'เลขที่สัญญา ชื่อสัญญา หรือชื่อลูกค้า',
        icon: NxI.fileText,
        tint: _contractTint,
        selectedId: selectedId,
        noneTitle: 'ไม่เชื่อมกับสัญญา',
        chips: [
          const JobPickChip('active', 'ใช้งานอยู่', group: 'status', filters: {'filter[contract_status]': 'Active'}),
          const JobPickChip('expiring', 'ใกล้หมดอายุ', group: 'status', filters: {'filter[contract_due]': 'expiring'}),
          const JobPickChip('all', 'ทุกสถานะ', group: 'status'),
          if (accountId != null) JobPickChip('account', accountName == null ? 'ของลูกค้านี้' : 'ของ $accountName', icon: NxI.buildings, filters: {'filter[related_account_id]': accountId}),
          if (userId != null) JobPickChip('mine', 'ของฉัน', icon: NxI.userCircle, filters: {'filter[smownerid]': userId}),
        ],
        initialOn: {'active', if (accountId != null) 'account'},
        view: (r) {
          final v = jobLinkView('service_contract', r);
          return JobPickView(title: v.heading, subtitle: v.customer, extra: v.extra, badges: [if (v.status.isNotEmpty) _statusBadge(v)]);
        },
      ),
    );

/// Assets (machines) of the customer, or all.
Future<PickedRecord?> showJobAssetPicker(BuildContext context, {required ApiClient api, String? accountId, String? accountName, String? selectedId}) =>
    showDocPicker<PickedRecord>(
      context,
      (_) => JobEntityPickerPage(
        api: api,
        module: 'asset',
        title: 'เลือกสินทรัพย์ / เครื่อง',
        keyPrefix: 'asset',
        searchHint: 'ชื่อเครื่อง เลขซีเรียล หรือเลขที่สินทรัพย์',
        icon: NxI.hardDrives,
        tint: _assetTint,
        selectedId: selectedId,
        noneTitle: 'ไม่ระบุสินทรัพย์',
        chips: [
          if (accountId != null) JobPickChip('account', accountName == null ? 'ของลูกค้านี้' : 'ของ $accountName', icon: NxI.buildings, filters: {'filter[related_account_id]': accountId}),
        ],
        initialOn: {if (accountId != null) 'account'},
        view: (r) => JobPickView(
          title: _s(r['asset_name']).isNotEmpty ? _s(r['asset_name']) : (_s(r['asset_no']).isNotEmpty ? _s(r['asset_no']) : '#${r['id']}'),
          subtitle: [
            if (_s(r['serial_no']).isNotEmpty) 'S/N ${_s(r['serial_no'])}',
            _s(r['asset_no']),
            _s(r['customer_name']),
          ].where((x) => x.isNotEmpty).join(' · '),
          badges: [if (_s(r['asset_status']).isNotEmpty) (_s(r['asset_status']), _assetTint)],
        ),
      ),
    );

// ───────────────────────────────────────────────────────── technicians

/// Business users with what helps to choose: skill match of the job (saved
/// jobs: `match-users`) and who is free at the planned time (their calendar
/// appointments that day). Recent picks first. `none` = clear.
Future<PickedRecord?> showTechnicianPicker(
  BuildContext context, {
  required ApiClient api,
  String title = 'เลือกช่าง / ผู้รับผิดชอบ',
  String keyPrefix = 'tech',
  String? jobId,
  DateTime? start,
  DateTime? end,
  String? selectedId,
  String? meId,
  String? businessId,
  bool allowNone = false,
}) =>
    showDocPicker<PickedRecord>(
      context,
      (_) => TechnicianPickerPage(
        api: api,
        title: title,
        keyPrefix: keyPrefix,
        jobId: jobId,
        start: start,
        end: end,
        selectedId: selectedId,
        meId: meId,
        businessId: businessId,
        allowNone: allowNone,
      ),
    );

class TechnicianPickerPage extends StatefulWidget {
  const TechnicianPickerPage({
    super.key,
    required this.api,
    this.title = 'เลือกช่าง / ผู้รับผิดชอบ',
    this.keyPrefix = 'tech',
    this.jobId,
    this.start,
    this.end,
    this.selectedId,
    this.meId,
    this.businessId,
    this.allowNone = false,
  });
  final ApiClient api;
  final String title;
  final String keyPrefix;
  final String? jobId;
  final DateTime? start;
  final DateTime? end;
  final String? selectedId;
  final String? meId;
  final String? businessId;
  final bool allowNone;

  @override
  State<TechnicianPickerPage> createState() => _TechnicianPickerPageState();
}

class _TechnicianPickerPageState extends State<TechnicianPickerPage> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _users = const [];
  Map<String, ({int matched, int required})> _skills = const {};
  Map<String, TechAvailability> _avail = const {};
  List<String> _recent = const [];
  bool _loading = true;
  bool _availLoaded = false;
  Object? _error;
  String _filter = 'all';

  DateTime? get _start => widget.start;
  DateTime get _end => widget.end != null && _start != null && widget.end!.isAfter(_start!) ? widget.end! : (_start ?? DateTime(2000)).add(kJobDefaultLength);

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = widget.api;
    try {
      final usersF = api.getUsersCached();
      final recentF = DocRecentPicks.read(widget.keyPrefix == 'tech' ? 'technician' : widget.keyPrefix, widget.businessId);
      Future<Map<String, ({int matched, int required})>> skillsF = Future.value(const {});
      if (widget.jobId != null) {
        skillsF = api.matchJobUsers(widget.jobId!).then(technicianSkillMatch).catchError((Object _) => <String, ({int matched, int required})>{});
      }
      Future<Map<String, TechAvailability>?> availF = Future.value(null);
      if (_start != null) {
        availF = api
            .getEntityList('activity', limit: 200, extra: {'calendar_from': ymd(_start!), 'calendar_to': ymd(_end)})
            .then<Map<String, TechAvailability>?>((p) => technicianAvailability(p.items, _start!, _end))
            .catchError((Object _) => null);
      }
      final users = await usersF;
      final skills = await skillsF;
      final avail = await availF;
      final recent = await recentF;
      if (!mounted) return;
      setState(() {
        _users = users;
        _skills = skills;
        _avail = avail ?? const {};
        _availLoaded = avail != null;
        _recent = [for (final r in recent) _s(r['id'])];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  String _id(Map<String, dynamic> u) => _s(u['id'] ?? u['user_id']);

  List<Map<String, dynamic>> get _visible {
    final q = _q.text.trim().toLowerCase();
    final list = [
      for (final u in _users)
        if ((q.isEmpty || '${jobUserName(u)} ${u['email1'] ?? u['email'] ?? ''} ${userPhoneOf(u)} ${u['user_name'] ?? ''}'.toLowerCase().contains(q)) &&
            (_filter != 'skill' || (_skills[_id(u)]?.matched ?? 0) > 0) &&
            (_filter != 'free' || (_avail[_id(u)]?.free ?? true)))
          u,
    ];
    double score(Map<String, dynamic> u) {
      final s = _skills[_id(u)];
      return s == null || s.required == 0 ? 0 : s.matched / s.required;
    }

    list.sort((a, b) {
      final sa = score(a), sb = score(b);
      if (sa != sb) return sb.compareTo(sa);
      final ca = _avail[_id(a)]?.clashes ?? 0, cb = _avail[_id(b)]?.clashes ?? 0;
      if (ca != cb) return ca.compareTo(cb);
      return jobUserName(a).compareTo(jobUserName(b));
    });
    return list;
  }

  void _pick(Map<String, dynamic> u) {
    HapticFeedback.selectionClick();
    DocRecentPicks.add(widget.keyPrefix == 'tech' ? 'technician' : widget.keyPrefix, widget.businessId, {
      'module': 'user',
      'id': _id(u),
      'title': jobUserName(u),
      'subtitle': userPhoneOf(u),
    });
    Navigator.of(context).pop(PickedRecord('user', u));
  }

  List<Widget> _badges(Map<String, dynamic> u) {
    final id = _id(u);
    final out = <Widget>[];
    if (id == widget.meId) out.add(DocPickerBadge(text: 'ฉัน', color: Theme.of(context).colorScheme.primary));
    final sk = _skills[id];
    if (sk != null && sk.required > 0) {
      out.add(KeyedSubtree(
        key: ValueKey('${widget.keyPrefix}-skill-$id'),
        child: DocPickerBadge(text: 'ตรงทักษะ ${sk.matched}/${sk.required}', color: sk.matched >= sk.required ? _ok : _warn),
      ));
    }
    if (_availLoaded) {
      final a = _avail[id] ?? const TechAvailability();
      out.add(KeyedSubtree(
        key: ValueKey('${widget.keyPrefix}-avail-$id'),
        child: DocPickerBadge(text: a.free ? 'ว่างช่วงนี้' : 'ชนเวลา ${a.clashes} นัด', color: a.free ? _ok : _bad),
      ));
      if (a.free && a.sameDay > 0) out.add(DocPickerBadge(text: 'วันนั้นมี ${a.sameDay} นัด', color: _warn));
    }
    return out;
  }

  Widget _row(Map<String, dynamic> u, {String prefix = 'hit'}) {
    final id = _id(u);
    final name = jobUserName(u);
    final cs = Theme.of(context).colorScheme;
    final palette = [const Color(0xFF2563EB), const Color(0xFF10B981), const Color(0xFFF59E0B), const Color(0xFFDB2777), const Color(0xFF8B5CF6), const Color(0xFF0EA5E9)];
    final tint = palette[(int.tryParse(id) ?? id.hashCode).abs() % palette.length];
    final first = _s(u['first_name']).isNotEmpty ? _s(u['first_name']) : name.trim();
    final initials = first.isEmpty ? '?' : first.characters.first.toUpperCase();
    return JobPickRow(
      key: ValueKey('${widget.keyPrefix}-$prefix-$id'),
      icon: NxI.user,
      tint: tint,
      leading: CircleAvatar(radius: 20, backgroundColor: tint.withValues(alpha: 0.18), child: Text(initials, style: TextStyle(color: tint, fontWeight: FontWeight.w800))),
      title: name.isEmpty ? '#$id' : name,
      subtitle: [userPhoneOf(u), _s(u['email1'] ?? u['email'])].where((x) => x.isNotEmpty).join(' · '),
      badges: _badges(u),
      selected: id == widget.selectedId,
      trailing: id == widget.selectedId ? Icon(NxI.check, color: cs.primary, size: 20) : null,
      onTap: () => _pick(u),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final q = _q.text.trim();
    final rows = _visible;
    final hasSkills = _skills.isNotEmpty;
    final when = jobWhenSummary(_start, _start == null ? null : _end, en: L10n.isEn);
    final children = <Widget>[
      Container(
        key: ValueKey('${widget.keyPrefix}-context'),
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(_start == null ? NxI.info : NxI.calendarClock, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_start == null ? tr('ยังไม่กำหนดเวลา — ใส่เวลาในขั้นนี้ก่อน เพื่อดูว่าใครว่าง') : '${tr('ช่วงงาน')} $when',
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              if (widget.jobId == null)
                Text(tr('ทักษะของงานตั้งได้หลังสร้างใบสั่งงาน แล้วระบบจะแนะนำช่างที่ตรงทักษะ'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))
              else if (!hasSkills && !_loading)
                Text(tr('งานนี้ยังไม่ได้ระบุทักษะ — ตั้งได้ในแท็บปฏิบัติงาน'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        ]),
      ),
      if (widget.allowNone && widget.selectedId != null)
        JobPickRow(
          key: ValueKey('${widget.keyPrefix}-none'),
          icon: NxI.x,
          tint: cs.onSurfaceVariant,
          title: tr('ไม่ระบุ'),
          onTap: () => Navigator.of(context).pop(const PickedRecord('none', {})),
        ),
    ];
    if (_error != null) {
      children.add(DocPickerState(
        key: const ValueKey('picker-error'),
        icon: NxI.warningCircle,
        title: 'โหลดรายชื่อไม่สำเร็จ',
        text: formatApiError(_error!),
        action: OutlinedButton.icon(onPressed: _load, icon: const Icon(NxI.arrowCounterClockwise, size: 18), label: Text(tr('ลองอีกครั้ง'))),
      ));
    } else if (_loading) {
      children.add(_spinner());
    } else {
      final recent = q.isEmpty && _filter == 'all'
          ? [
              for (final id in _recent)
                ..._users.where((u) => _id(u) == id),
            ].take(4).toList()
          : const <Map<String, dynamic>>[];
      if (recent.isNotEmpty) {
        children.add(const DocPickerSection('ใช้ล่าสุด'));
        for (final u in recent) {
          children.add(_row(u, prefix: 'recent'));
        }
      }
      if (rows.isNotEmpty) children.add(DocPickerSection(q.isEmpty ? 'ทุกคน (${rows.length})' : 'ผลการค้นหา'));
      for (final u in rows) {
        children.add(_row(u));
      }
      if (rows.isEmpty) {
        children.add(DocPickerState(
          key: const ValueKey('picker-empty'),
          icon: NxI.users,
          title: q.isEmpty ? 'ไม่มีใครตามตัวกรองนี้' : 'ไม่พบ "$q"',
          text: _filter == 'free' ? 'ทุกคนมีนัดชนช่วงนี้ — ลองเลื่อนเวลา หรือดูทุกคน' : null,
        ));
      }
    }
    return DocPickerFrame(
      pageKey: ValueKey('${widget.keyPrefix}-picker'),
      title: widget.title,
      search: DocPickerSearchBox(controller: _q, fieldKey: ValueKey('${widget.keyPrefix}-search'), hint: 'ชื่อ เบอร์ หรืออีเมล', loading: _loading, autofocus: false),
      filters: DocPickerChips(children: [
        docPickerFilterChip(context, key: ValueKey('${widget.keyPrefix}-chip-all'), label: 'ทุกคน', selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
        if (hasSkills)
          docPickerFilterChip(context, key: ValueKey('${widget.keyPrefix}-chip-skill'), label: 'ตรงทักษะ', icon: NxI.userCheck, selected: _filter == 'skill', onTap: () => setState(() => _filter = 'skill')),
        if (_availLoaded)
          docPickerFilterChip(context, key: ValueKey('${widget.keyPrefix}-chip-free'), label: 'ว่างช่วงนี้', icon: NxI.calendarCheck, selected: _filter == 'free', onTap: () => setState(() => _filter = 'free')),
      ]),
      body: ListView(key: ValueKey('${widget.keyPrefix}-results'), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: children),
    );
  }
}

// ────────────────────────────────────────────────────────────── site

/// The work site picked: a customer address, a service location, a pin or
/// a typed Thai address.
class JobSitePick {
  const JobSitePick({required this.kind, required this.name, required this.address, this.location});

  /// `account` · `location` · `pin` · `manual`.
  final String kind;
  final String name;
  final String address;

  /// The service location row (kind `location`).
  final Map<String, dynamic>? location;
}

/// Address sets of an account row (main / billing / shipping …) as
/// `(label, one-line address)`.
List<(String, String)> accountSiteAddresses(Map<String, dynamic> account) {
  final out = <(String, String)>[];
  for (final set in detectThaiAddressSets(account.keys)) {
    String v(String? k) => k == null ? '' : _s(account[k]);
    final addr = composeThaiAddress(line: v(set.line), subdistrict: v(set.subdistrict), district: v(set.district), province: v(set.province), postal: v(set.postal));
    if (addr.isEmpty || out.any((e) => e.$2 == addr)) continue;
    final p = set.province.toLowerCase();
    final label = p.contains('bill')
        ? 'ที่อยู่ออกบิล'
        : p.contains('ship') || p.contains('deliver')
            ? 'ที่อยู่จัดส่ง'
            : out.isEmpty
                ? 'ที่อยู่หลักของลูกค้า'
                : 'ที่อยู่อื่นของลูกค้า';
    out.add((label, addr));
  }
  return out;
}

Future<JobSitePick?> showJobSitePicker(BuildContext context, {required ApiClient api, String? accountId, String? accountName, Map<String, dynamic>? account, String? selectedLocationId}) =>
    showDocPicker<JobSitePick>(
      context,
      (_) => JobSitePickerPage(api: api, accountId: accountId, accountName: accountName, account: account, selectedLocationId: selectedLocationId),
    );

class JobSitePickerPage extends StatefulWidget {
  const JobSitePickerPage({super.key, required this.api, this.accountId, this.accountName, this.account, this.selectedLocationId});
  final ApiClient api;
  final String? accountId;
  final String? accountName;
  final Map<String, dynamic>? account;
  final String? selectedLocationId;

  @override
  State<JobSitePickerPage> createState() => _JobSitePickerPageState();
}

class _JobSitePickerPageState extends State<JobSitePickerPage> {
  final _q = TextEditingController();
  Timer? _debounce;
  String _lastQ = '';
  late bool _ofAccount = widget.accountId != null;
  List<Map<String, dynamic>> _locations = const [];
  bool _loading = true;
  bool _pinning = false;
  Object? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _q.addListener(() {
      if (_q.text.trim() == _lastQ) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        _lastQ = _q.text.trim();
        _load();
      });
    });
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await widget.api.getEntityList('service_location', q: _q.text.trim(), limit: 30, extra: {
        if (_ofAccount && widget.accountId != null) 'filter[related_account_id]': widget.accountId!,
      });
      if (!mounted || token != _token) return;
      setState(() {
        _locations = p.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _pin() async {
    final hook = DocFormHooks.pickPin;
    final p = hook != null ? await hook(context) : await showNxMapPinPicker(context, title: tr('ปักหมุดสถานที่ทำงาน'));
    if (p == null || !mounted) return;
    setState(() => _pinning = true);
    final lookup = DocFormHooks.reverseGeocode;
    String? addr;
    try {
      addr = lookup != null ? await lookup(p.lat, p.lng) : await GeoAddress.lookup(p.lat, p.lng);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop(JobSitePick(kind: 'pin', name: tr('จุดที่ปักหมุด'), address: siteAddressWithPin(addr ?? '', p.lat, p.lng)));
  }

  Future<void> _manual() async {
    final r = await Navigator.of(context).push<JobSitePick>(MaterialPageRoute(builder: (_) => JobSiteAddressPage(api: widget.api)));
    if (r != null && mounted) Navigator.of(context).pop(r);
  }

  Widget _action({required Key key, required IconData icon, required String title, required String subtitle, required VoidCallback? onTap, bool busy = false}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Material(
        color: cs.primary.withValues(alpha: 0.07),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: cs.primary.withValues(alpha: 0.3))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: key,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.14), shape: BoxShape.circle), child: Icon(icon, color: cs.primary, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
                  Text(tr(subtitle), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
              if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) else Icon(NxI.caretRight, color: cs.primary),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim();
    final accountAddrs = widget.account == null ? const <(String, String)>[] : accountSiteAddresses(widget.account!);
    final accName = _s(widget.account?['account_name']).isNotEmpty ? _s(widget.account?['account_name']) : (widget.accountName ?? '');
    final children = <Widget>[
      _action(key: const ValueKey('site-pin'), icon: NxI.mapPinned, title: 'ปักหมุดบนแผนที่', subtitle: 'ใช้ตำแหน่งจริง ช่างเปิดนำทางได้ทันที', onTap: _pinning ? null : _pin, busy: _pinning),
      _action(key: const ValueKey('site-manual'), icon: NxI.mapTrifold, title: 'ระบุที่อยู่เอง', subtitle: 'เลือกจังหวัด อำเภอ ตำบล หรือพิมพ์รหัสไปรษณีย์', onTap: _manual),
      if (accountAddrs.isNotEmpty && q.isEmpty) ...[
        const DocPickerSection('ที่อยู่ของลูกค้า'),
        for (var i = 0; i < accountAddrs.length; i++)
          JobPickRow(
            key: ValueKey('site-account-$i'),
            icon: NxI.buildings,
            tint: const Color(0xFF2563EB),
            title: tr(accountAddrs[i].$1),
            subtitle: accountAddrs[i].$2,
            onTap: () => Navigator.of(context).pop(JobSitePick(kind: 'account', name: accName, address: accountAddrs[i].$2)),
          ),
      ],
      DocPickerSection(_ofAccount ? 'พื้นที่บริการของลูกค้า' : 'พื้นที่บริการทั้งหมด'),
    ];
    if (_error != null) {
      children.add(DocPickerState(key: const ValueKey('picker-error'), icon: NxI.warningCircle, title: 'โหลดพื้นที่บริการไม่สำเร็จ', text: formatApiError(_error!)));
    } else {
      for (final r in _locations) {
        final id = _s(r['id']);
        final addr = siteAddressOf(r);
        children.add(JobPickRow(
          key: ValueKey('site-loc-$id'),
          icon: NxI.mapPin,
          tint: _locTint,
          title: _s(r['location_name']).isNotEmpty ? _s(r['location_name']) : '#$id',
          subtitle: [addr, if (!_ofAccount) _s(r['customer_name'])].where((x) => x.isNotEmpty).join(' · '),
          extra: _s(r['location_type']),
          selected: id == widget.selectedLocationId,
          trailing: id == widget.selectedLocationId ? _check(context) : null,
          onTap: () => Navigator.of(context).pop(JobSitePick(kind: 'location', name: _s(r['location_name']), address: addr, location: r)),
        ));
      }
      if (_loading) children.add(_spinner());
      if (!_loading && _locations.isEmpty) {
        children.add(DocPickerState(
          key: const ValueKey('picker-empty'),
          icon: NxI.mapTrifold,
          title: q.isEmpty ? (_ofAccount ? 'ลูกค้านี้ยังไม่มีพื้นที่บริการ' : 'ยังไม่มีพื้นที่บริการ') : 'ไม่พบ "$q"',
          text: 'ใช้ที่อยู่ลูกค้า ปักหมุด หรือระบุที่อยู่เองด้านบน',
        ));
      }
    }
    return DocPickerFrame(
      pageKey: const ValueKey('site-picker'),
      title: 'สถานที่ทำงาน',
      search: DocPickerSearchBox(controller: _q, fieldKey: const ValueKey('site-search'), hint: 'ค้นหาพื้นที่บริการ', loading: _loading, autofocus: false),
      filters: widget.accountId == null
          ? null
          : DocPickerChips(children: [
              docPickerFilterChip(context, key: const ValueKey('site-chip-account'), label: accName.isEmpty ? 'ของลูกค้านี้' : 'ของ $accName', icon: NxI.buildings, selected: _ofAccount, onTap: () {
                setState(() => _ofAccount = true);
                _load();
              }),
              docPickerFilterChip(context, key: const ValueKey('site-chip-all'), label: 'ทั้งหมด', selected: !_ofAccount, onTap: () {
                setState(() => _ofAccount = false);
                _load();
              }),
            ]),
      body: ListView(key: const ValueKey('site-results'), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: children),
    );
  }
}

/// Typed site address with the app's Thai address set (จังหวัด → อำเภอ →
/// ตำบล, postcode lookup, map pin) — composed into one line for the job.
class JobSiteAddressPage extends StatefulWidget {
  const JobSiteAddressPage({super.key, required this.api});
  final ApiClient api;

  @override
  State<JobSiteAddressPage> createState() => _JobSiteAddressPageState();
}

class _JobSiteAddressPageState extends State<JobSiteAddressPage> {
  static const _set = ThaiAddressSetFields(
    province: 'site_province',
    district: 'site_district',
    subdistrict: 'site_sub_district',
    postal: 'site_postal_code',
    line: 'site_line',
    latLng: 'site_locationmap',
  );
  final Map<String, dynamic> _v = {};
  final _name = TextEditingController();
  final _line = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _line.dispose();
    super.dispose();
  }

  String _text() {
    String v(String k) => _s(_v[k]);
    final addr = composeThaiAddress(line: _line.text, subdistrict: v('site_sub_district'), district: v('site_district'), province: v('site_province'), postal: v('site_postal_code'));
    final ll = v('site_locationmap').split(',');
    if (ll.length == 2) {
      final lat = double.tryParse(ll[0]), lng = double.tryParse(ll[1]);
      if (lat != null && lng != null) return siteAddressWithPin(addr, lat, lng);
    }
    return addr;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = _text();
    return Scaffold(
      key: const ValueKey('site-address-page'),
      appBar: AppBar(title: Text(tr('ระบุที่อยู่หน้างาน'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        TextField(
          key: const ValueKey('site-address-name'),
          controller: _name,
          decoration: InputDecoration(labelText: tr('ชื่อสถานที่ (ไม่บังคับ)'), hintText: tr('เช่น อาคาร B ชั้น 3 / โกดังบางนา')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('site-address-line'),
          controller: _line,
          decoration: InputDecoration(labelText: tr('บ้านเลขที่ / อาคาร / ถนน')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        NxThaiAddressSet(
          fields: _set,
          values: _v,
          api: widget.api,
          onChanged: (k, v) {
            setState(() => _v[k] = v);
            if (k == 'site_line' && _line.text.trim().isEmpty) _line.text = '${v ?? ''}';
          },
        ),
        const SizedBox(height: 12),
        if (text.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(14)),
            child: Text(text, key: const ValueKey('site-address-preview'), style: theme.textTheme.bodyMedium),
          ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            key: const ValueKey('site-address-use'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
            onPressed: text.isEmpty ? null : () => Navigator.of(context).pop(JobSitePick(kind: 'manual', name: _name.text.trim(), address: text)),
            icon: const Icon(NxI.check, size: 18),
            label: Text(tr('ใช้ที่อยู่นี้')),
          ),
        ),
      ),
    );
  }
}

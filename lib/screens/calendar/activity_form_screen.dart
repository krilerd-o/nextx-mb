import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:provider/provider.dart';

import '../../core/activity_guests.dart';
import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/html_display.dart';
import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../widgets/fields/nx_lift_sheet.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_map_pin_picker.dart';
import '../../widgets/nx_map_view.dart';
import 'cal/cal_model.dart';
import '../../widgets/nx_unsaved_guard.dart';

/// Activity create / edit / duplicate, laid out like the web compose panel
/// (and Google Calendar): title + type, all-day or times (hh:mm), guests with
/// suggestions, location with a map pin, online meeting, reminder, details.
class ActivityFormScreen extends StatefulWidget {
  const ActivityFormScreen({super.key, this.initial = const {}, this.recordId, this.title, this.start});

  /// Existing row (edit / duplicate) or seed values (related record, subject…).
  final Map<String, dynamic> initial;

  /// Set when editing.
  final String? recordId;
  final String? title;

  /// New activity at this time (calendar slot / FAB).
  final DateTime? start;

  /// Copy of [row] for "ทำซ้ำ": same content, new record, no check-in/series.
  static Map<String, dynamic> duplicateSeed(Map<String, dynamic> row) {
    const drop = {
      'id', 'checkindate', 'checkoutdate', 'checkin_lat', 'checkin_lng', 'location_chkout', 'time_tracking', 'imagename', 'photos',
      'calendar_sync', 'series_id', 'reminder_sent_at', 'createdtime', 'modifiedtime', 'smcreatorid', 'modifiedby', 'status', 'deleted',
    };
    return {for (final e in row.entries) if (!drop.contains(e.key)) e.key: e.value};
  }

  bool get isEdit => recordId != null && recordId!.isNotEmpty;

  @override
  State<ActivityFormScreen> createState() => _ActivityFormScreenState();
}

class _ActivityFormScreenState extends State<ActivityFormScreen> {
  late final TextEditingController _subject;
  late final TextEditingController _location;
  late final TextEditingController _meetUrl;
  late final TextEditingController _desc;
  late String _type;
  late bool _allDay;
  late DateTime _start;
  late DateTime _end;
  List<ActivityGuest> _guests = [];
  double? _lat;
  double? _lng;
  late bool _meetOn;
  late int _reminder;
  late final String _descInitial;
  bool _saving = false;
  String? _subjectError;

  int? get _ownerId {
    final v = widget.initial['smownerid'] ?? widget.initial['owner'];
    final id = num.tryParse('${v is Map ? v['id'] : v ?? ''}')?.toInt();
    return id ?? int.tryParse(context.read<AppConfig>().session.userId ?? '');
  }

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _subject = TextEditingController(text: '${r['subject'] ?? ''}');
    _location = TextEditingController(text: '${r['location'] ?? ''}');
    final url = '${r['video_conference_url'] ?? ''}'.trim();
    _meetUrl = TextEditingController(text: url);
    _meetOn = url.isNotEmpty;
    // Description is HTML on the web: edit as text, send only when changed.
    _descInitial = stripHtmlPreview('${r['description'] ?? ''}', maxLen: 100000);
    _desc = TextEditingController(text: _descInitial);
    final t = '${r['activitytype'] ?? ''}';
    // New activities start as a customer visit (เยี่ยมลูกค้า).
    _type = t.isEmpty ? 'Visit' : t;
    _allDay = r['all_day'] == true || r['all_day'] == 1 || '${r['all_day']}' == 'true';
    final s = parseWall(r['date_start']) ?? widget.start ?? _nextSlot(thaiNow());
    var e = parseWall(r['date_end']) ?? (_allDay ? _dayEnd(s) : s.add(const Duration(hours: 1)));
    if (!e.isAfter(s)) e = _allDay ? _dayEnd(s) : s.add(const Duration(hours: 1));
    _start = _allDay ? calDay(s) : s;
    _end = e;
    _lat = double.tryParse('${r['location_lat'] ?? ''}');
    _lng = double.tryParse('${r['location_lng'] ?? ''}');
    if ((_lat == null || _lng == null) && '${r['event_locationmap'] ?? ''}'.contains(',')) {
      final p = '${r['event_locationmap']}'.split(',');
      _lat = double.tryParse(p[0].trim());
      _lng = double.tryParse(p[1].trim());
    }
    _reminder = int.tryParse('${r['reminder_minutes'] ?? ''}') ?? 0;
    _guests = parseActivityGuests(r['attendees']);
    WidgetsBinding.instance.addPostFrameCallback((_) => _seedGuests());
  }

  /// Owner first (organizer); the related customer of a new activity next.
  void _seedGuests() {
    if (!mounted) return;
    final config = context.read<AppConfig>();
    final me = int.tryParse(config.session.userId ?? '');
    var list = ensureOwnerGuest(_guests, _ownerId, ownerName: _ownerId == me ? (config.session.displayName ?? '') : '');
    final mod = '${widget.initial['related_module'] ?? ''}'.toLowerCase();
    final rid = int.tryParse('${widget.initial['related_id'] ?? ''}');
    if (kGuestEntityModules.contains(mod) && rid != null && !list.any((g) => g.kind == 'entity' && g.module == mod && g.entityId == rid)) {
      list = [
        ...list,
        ActivityGuest(
          kind: 'entity',
          module: mod,
          entityId: rid,
          name: '${widget.initial['customer_name'] ?? widget.initial['_related_name'] ?? ''}',
          email: '${widget.initial['customer_email'] ?? ''}',
          phone: '${widget.initial['customer_mobile'] ?? ''}',
          accountName: '${widget.initial['account_name'] ?? ''}',
        ),
      ];
    }
    setState(() => _guests = list);
  }

  @override
  void dispose() {
    _subject.dispose();
    _location.dispose();
    _meetUrl.dispose();
    _desc.dispose();
    super.dispose();
  }

  static DateTime _nextSlot(DateTime now) {
    final m = now.minute < 30 ? 30 : 60;
    return DateTime(now.year, now.month, now.day, now.hour).add(Duration(minutes: m));
  }

  static DateTime _dayEnd(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59);

  // ── dates ────────────────────────────────────────────────────────────────

  Future<DateTime?> _pickDay(DateTime cur) => showDatePicker(
        context: context,
        initialDate: cur,
        firstDate: DateTime(cur.year - 5),
        lastDate: DateTime(cur.year + 5),
      );

  Future<TimeOfDay?> _pickTime(DateTime cur) => showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(cur),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
      );

  Future<void> _editStart({required bool time}) async {
    final dur = _end.difference(_start);
    DateTime? next;
    if (time) {
      final t = await _pickTime(_start);
      if (t != null) next = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute);
    } else {
      final d = await _pickDay(_start);
      if (d != null) next = DateTime(d.year, d.month, d.day, _start.hour, _start.minute);
    }
    if (next == null || !mounted) return;
    setState(() {
      _start = next!;
      // Keep the length, like the web and Google Calendar.
      _end = _allDay ? _dayEnd(next.add(Duration(days: dur.inDays))) : next.add(dur.inMinutes > 0 ? dur : const Duration(hours: 1));
    });
  }

  Future<void> _editEnd({required bool time}) async {
    DateTime? next;
    if (time) {
      final t = await _pickTime(_end);
      if (t != null) next = DateTime(_end.year, _end.month, _end.day, t.hour, t.minute);
    } else {
      final d = await _pickDay(_end);
      if (d != null) next = _allDay ? _dayEnd(d) : DateTime(d.year, d.month, d.day, _end.hour, _end.minute);
    }
    if (next == null || !mounted) return;
    if (!next.isAfter(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('เวลาสิ้นสุดต้องหลังเวลาเริ่ม'))));
      return;
    }
    setState(() => _end = next!);
  }

  void _setAllDay(bool on) => setState(() {
        _allDay = on;
        if (on) {
          _start = calDay(_start);
          _end = _dayEnd(_end.isBefore(_start) ? _start : _end);
        } else {
          final s = DateTime(_start.year, _start.month, _start.day, 9);
          _start = s;
          _end = s.add(const Duration(hours: 1));
        }
      });

  void _setDuration(int minutes) => setState(() {
        _allDay = false;
        _end = _start.add(Duration(minutes: minutes));
      });

  // ── guests ───────────────────────────────────────────────────────────────

  Future<void> _addGuests() async {
    final api = context.read<AppConfig>().apiClient;
    final picked = await showNxLiftSheet<List<ActivityGuest>>(
      context: context,
      builder: (ctx, scroll) => _GuestPicker(
        api: api,
        scroll: scroll,
        firstMode: defaultGuestMode(_type),
        existing: {for (final g in _guests) g.key},
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      final keys = {for (final g in _guests) g.key};
      _guests = [..._guests, ...picked.where((g) => keys.add(g.key))];
    });
  }

  // ── location ─────────────────────────────────────────────────────────────

  Future<void> _pickOnMap() async {
    final res = await showNxMapPinPicker(context, lat: _lat, lng: _lng);
    if (res != null && mounted) {
      setState(() {
        _lat = res.lat;
        _lng = res.lng;
      });
    }
  }

  // ── save ─────────────────────────────────────────────────────────────────

  Map<String, dynamic> buildPayload() {
    final guests = ensureOwnerGuest(_guests, _ownerId);
    final related = projectRelatedFromGuests(guests);
    final initialMod = '${widget.initial['related_module'] ?? ''}'.toLowerCase();
    // Job / asset links are not guests: keep them as they were.
    final keepLink = (initialMod == 'job' || initialMod == 'asset') && widget.initial['related_id'] != null;
    final hasPin = _lat != null && _lng != null;
    final desc = _desc.text.trim();
    return {
      'subject': _subject.text.trim(),
      'activitytype': _type,
      'all_day': _allDay,
      'date_start': ymdhm(_allDay ? calDay(_start) : _start),
      'date_end': ymdhm(_allDay ? _dayEnd(_end) : _end),
      'smownerid': _ownerId,
      'location': _location.text.trim().isEmpty ? null : _location.text.trim(),
      'location_lat': hasPin ? double.parse(_lat!.toStringAsFixed(6)) : null,
      'location_lng': hasPin ? double.parse(_lng!.toStringAsFixed(6)) : null,
      'event_locationmap': hasPin ? '${_lat!.toStringAsFixed(6)},${_lng!.toStringAsFixed(6)}' : null,
      'attendees': [for (final g in guests) g.toJson()],
      if (keepLink) ...{'related_module': initialMod, 'related_id': widget.initial['related_id']} else ...{
        'related_module': related['related_module'],
        'related_id': related['related_id'],
      },
      for (final k in ['customer_name', 'customer_mobile', 'customer_email', 'account_name'])
        if (related.containsKey(k)) k: related[k] else if (!keepLink) k: null,
      'video_conference_url': _meetOn && _meetUrl.text.trim().isNotEmpty ? _meetUrl.text.trim() : null,
      'reminder_minutes': _reminder > 0 ? _reminder : null,
      if (desc != _descInitial || !widget.isEdit) 'description': desc.isEmpty ? null : desc,
      if (!widget.isEdit) 'status': 'Planned',
    };
  }

  Future<void> _save() async {
    if (_subject.text.trim().isEmpty) {
      HapticFeedback.heavyImpact();
      setState(() => _subjectError = 'กรุณาใส่ชื่อกิจกรรม');
      return;
    }
    setState(() {
      _saving = true;
      _subjectError = null;
    });
    final api = context.read<AppConfig>().apiClient;
    try {
      final payload = buildPayload();
      if (widget.isEdit) {
        await api.putEntity('activity', widget.recordId!, payload);
      } else {
        await api.postEntity('activity', payload);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  // Back / swipe asks before throwing away what was typed.
  @override
  Widget build(BuildContext context) => NxUnsavedGuard(
        enabled: true,
        snapshot: () => [_subject.text, _location.text, _meetUrl.text, _desc.text, _start, _end].join('|'),
        child: _buildForm(context),
      );


  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = widget.title ?? (widget.isEdit ? 'แก้ไขกิจกรรม' : 'นัดหมายใหม่');
    return Scaffold(
      appBar: AppBar(title: Text(tr(title))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          TextField(
            key: const ValueKey('act-subject'),
            controller: _subject,
            autofocus: !widget.isEdit && _subject.text.isEmpty,
            textCapitalization: TextCapitalization.sentences,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            onChanged: (_) => _subjectError == null ? null : setState(() => _subjectError = null),
            decoration: InputDecoration(
              hintText: tr('เพิ่มชื่อกิจกรรม'),
              errorText: _subjectError == null ? null : tr(_subjectError!),
              border: InputBorder.none,
              filled: false,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final t in {...kActivityTypes, _type})
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: ValueKey('act-type-$t'),
                    label: Text(tr(activityTypeLabel(t))),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 14),
          _Section(children: [
            _Row(
              icon: NxI.clock,
              child: Row(children: [
                Expanded(child: Text(tr('ทั้งวัน'), style: theme.textTheme.bodyLarge)),
                Switch(key: const ValueKey('act-allday'), value: _allDay, onChanged: _setAllDay),
              ]),
            ),
            _WhenLine(
              keyPrefix: 'act-start',
              day: _start,
              allDay: _allDay,
              onDay: () => _editStart(time: false),
              onTime: () => _editStart(time: true),
            ),
            _WhenLine(
              keyPrefix: 'act-end',
              day: _end,
              allDay: _allDay,
              onDay: () => _editEnd(time: false),
              onTime: () => _editEnd(time: true),
            ),
            if (!_allDay)
              Padding(
                padding: const EdgeInsets.fromLTRB(52, 0, 12, 10),
                child: Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final m in const [30, 60, 90, 120])
                    ChoiceChip(
                      label: Text(tr(m < 60 ? '$m นาที' : (m % 60 == 0 ? '${m ~/ 60} ชม.' : '${m / 60} ชม.'))),
                      selected: _end.difference(_start).inMinutes == m,
                      onSelected: (_) => _setDuration(m),
                    ),
                ]),
              ),
          ]),
          _Section(children: [
            for (final g in _guests)
              _GuestTile(
                guest: g,
                onRemove: g.isOrganizer ? null : () => setState(() => _guests = _guests.where((x) => x.key != g.key).toList()),
              ),
            _Row(
              icon: NxI.userPlus,
              onTap: _addGuests,
              child: Text(tr('เพิ่มผู้เข้าร่วม'), key: const ValueKey('act-add-guest'), style: theme.textTheme.bodyLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
            ),
          ]),
          _Section(children: [
            _Row(
              icon: NxI.mapPin,
              child: TextField(
                key: const ValueKey('act-location'),
                controller: _location,
                decoration: InputDecoration(hintText: tr('เพิ่มสถานที่'), border: InputBorder.none, filled: false, isDense: true),
              ),
            ),
            if (_lat != null && _lng != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: NxMapView(me: LatLng(_lat!, _lng!), dest: LatLng(_lat!, _lng!), height: 150),
              ),
            _Row(
              icon: NxI.crosshair,
              onTap: _pickOnMap,
              child: Row(children: [
                Expanded(
                  child: Text(
                    _lat == null ? tr('ปักหมุดบนแผนที่') : '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                    key: const ValueKey('act-pin'),
                    style: theme.textTheme.bodyLarge?.copyWith(color: _lat == null ? cs.primary : null, fontWeight: _lat == null ? FontWeight.w600 : null),
                  ),
                ),
                if (_lat != null)
                  IconButton(
                    tooltip: tr('ลบหมุด'),
                    icon: const Icon(NxI.x, size: 18),
                    onPressed: () => setState(() => _lat = _lng = null),
                  ),
              ]),
            ),
          ]),
          _Section(children: [
            _Row(
              icon: NxI.videoCamera,
              child: Row(children: [
                Expanded(child: Text(tr('ประชุมออนไลน์'), style: theme.textTheme.bodyLarge)),
                Switch(value: _meetOn, onChanged: (v) => setState(() => _meetOn = v)),
              ]),
            ),
            if (_meetOn)
              Padding(
                padding: const EdgeInsets.fromLTRB(52, 0, 12, 10),
                child: TextField(
                  controller: _meetUrl,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(hintText: tr('ลิงก์ Google Meet / Zoom / Teams'), isDense: true),
                ),
              ),
            _Row(
              icon: NxI.bell,
              child: Wrap(spacing: 8, runSpacing: 6, children: [
                for (final m in {...kReminderPresets, _reminder})
                  ChoiceChip(
                    key: ValueKey('act-remind-$m'),
                    label: Text(tr(reminderLabel(m))),
                    selected: _reminder == m,
                    onSelected: (_) => setState(() => _reminder = m),
                  ),
              ]),
            ),
          ]),
          _Section(children: [
            _Row(
              icon: NxI.note,
              child: TextField(
                controller: _desc,
                minLines: 2,
                maxLines: 8,
                decoration: InputDecoration(hintText: tr('เพิ่มรายละเอียด'), border: InputBorder.none, filled: false, isDense: true),
              ),
            ),
          ]),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: NxHeroCta(key: const ValueKey('act-save'), label: widget.isEdit ? 'บันทึก' : 'สร้างกิจกรรม', busy: _saving, onPressed: _saving ? null : _save),
      ),
    );
  }
}

/// Thai label of a day: `พ. 4 พ.ย. 2569`.
String activityDayLabel(DateTime d) => '${weekdayShort(d)}. ${d.day} ${monthShort(d.month)} ${uiYear(d.year)}';

class _Section extends StatelessWidget {
  const _Section({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

/// Icon on the left, content on the right (Google Calendar style).
class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.child, this.onTap});
  final IconData icon;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            SizedBox(width: 28, child: Icon(icon, size: 20, color: cs.onSurfaceVariant)),
            const SizedBox(width: 12),
            Expanded(child: child),
          ]),
        ),
      ),
    );
  }
}

class _WhenLine extends StatelessWidget {
  const _WhenLine({required this.keyPrefix, required this.day, required this.allDay, required this.onDay, required this.onTime});
  final String keyPrefix;
  final DateTime day;
  final bool allDay;
  final VoidCallback onDay;
  final VoidCallback onTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(52, 0, 4, 2),
      child: Row(children: [
        Expanded(
          child: TextButton(
            key: ValueKey('$keyPrefix-day'),
            style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10)),
            onPressed: onDay,
            child: Text(activityDayLabel(day), style: theme.textTheme.bodyLarge),
          ),
        ),
        // All-day hides the time completely.
        if (!allDay)
          TextButton(
            key: ValueKey('$keyPrefix-time'),
            onPressed: onTime,
            child: Text(hm(day), style: theme.textTheme.bodyLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ),
      ]),
    );
  }
}

class _GuestTile extends StatelessWidget {
  const _GuestTile({required this.guest, this.onRemove});
  final ActivityGuest guest;
  final VoidCallback? onRemove;

  static String _kindLabel(ActivityGuest g) => switch (g.kind) {
        'user' => 'ผู้ใช้',
        'email' => 'อีเมล',
        _ => switch (g.module) {
            'lead' => 'ผู้มุ่งหวัง',
            'contact' => 'ผู้ติดต่อ',
            'account' => 'บัญชี',
            'case' => 'เคส',
            _ => g.module ?? '',
          },
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sub = [
      if (guest.isOrganizer) 'ผู้จัด',
      _kindLabel(guest),
      if (guest.kind != 'email' && guest.email.isNotEmpty) guest.email,
      if (guest.accountName.isNotEmpty) guest.accountName,
    ].map(tr).join(' · ');
    return Padding(
      key: ValueKey('act-guest-${guest.key}'),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(children: [
        SizedBox(width: 28, child: NxAvatar(label: guest.display, size: 28)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(guest.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
        if (onRemove != null) IconButton(tooltip: tr('เอาออก'), icon: const Icon(NxI.x, size: 18), onPressed: onRemove),
      ]),
    );
  }
}

/// Search users / leads / contacts / accounts, or type an email; multi-select.
class _GuestPicker extends StatefulWidget {
  const _GuestPicker({required this.api, required this.scroll, required this.firstMode, required this.existing});
  final ApiClient api;
  final ScrollController scroll;
  final String firstMode;
  final Set<String> existing;

  @override
  State<_GuestPicker> createState() => _GuestPickerState();
}

class _GuestPickerState extends State<_GuestPicker> {
  static const _modes = ['user', 'lead', 'contact', 'account', 'email'];
  late String _mode = widget.firstMode;
  final _q = TextEditingController();
  final _picked = <String, ActivityGuest>{};
  List<ActivityGuest> _results = [];
  bool _loading = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  static String _modeLabel(String m) => switch (m) {
        'user' => 'ผู้ใช้',
        'lead' => 'ผู้มุ่งหวัง',
        'contact' => 'ผู้ติดต่อ',
        'account' => 'บัญชี',
        _ => 'อีเมล',
      };

  Future<void> _search() async {
    if (_mode == 'email') {
      setState(() => _results = []);
      return;
    }
    final seq = ++_seq;
    setState(() => _loading = true);
    try {
      final q = _q.text.trim();
      final List<ActivityGuest> out;
      if (_mode == 'user') {
        final rows = await widget.api.getUsers(q: q.isEmpty ? null : q, limit: 40);
        out = [
          for (final u in rows)
            if (int.tryParse('${u['id']}') != null)
              ActivityGuest(
                kind: 'user',
                userId: int.parse('${u['id']}'),
                name: [u['first_name'], u['last_name']].where((e) => e != null && '$e'.trim().isNotEmpty).join(' ').trim().isNotEmpty
                    ? [u['first_name'], u['last_name']].where((e) => e != null && '$e'.trim().isNotEmpty).join(' ').trim()
                    : '${u['name'] ?? u['user_name'] ?? ''}',
                email: '${u['email1'] ?? u['email'] ?? ''}',
              ),
        ];
      } else {
        final page = await widget.api.getEntityList(_mode, limit: 30, q: q.isEmpty ? null : q);
        out = [
          for (final row in page.items)
            if (int.tryParse('${row['id']}') != null)
              ActivityGuest(
                kind: 'entity',
                module: _mode,
                entityId: int.parse('${row['id']}'),
                name: entityTitle(row, module: _mode),
                email: '${row['email'] ?? row['email1'] ?? row['email_1st'] ?? ''}'.trim(),
                phone: '${row['mobile'] ?? row['mobile_1st'] ?? row['phone'] ?? ''}'.trim(),
                accountName: '${row['account_name'] ?? row['company_name'] ?? ''}'.trim(),
              ),
        ];
      }
      if (mounted && seq == _seq) setState(() => _results = out);
    } catch (_) {
      if (mounted && seq == _seq) setState(() => _results = []);
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  void _toggle(ActivityGuest g) => setState(() => _picked.containsKey(g.key) ? _picked.remove(g.key) : _picked[g.key] = g);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final email = _q.text.trim();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(children: [
          Expanded(child: Text(tr('เพิ่มผู้เข้าร่วม'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          TextButton(
            key: const ValueKey('guest-done'),
            onPressed: () => Navigator.of(context).pop(_picked.values.toList()),
            child: Text(_picked.isEmpty ? tr('ปิด') : tr('เพิ่ม ${_picked.length} คน')),
          ),
        ]),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          for (final m in {widget.firstMode, ..._modes})
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('guest-mode-$m'),
                label: Text(tr(_modeLabel(m))),
                selected: _mode == m,
                onSelected: (_) {
                  setState(() => _mode = m);
                  _search();
                },
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: TextField(
          key: const ValueKey('guest-q'),
          controller: _q,
          autofocus: true,
          keyboardType: _mode == 'email' ? TextInputType.emailAddress : TextInputType.text,
          onChanged: (_) => _mode == 'email' ? setState(() {}) : _search(),
          decoration: InputDecoration(
            prefixIcon: Icon(_mode == 'email' ? NxI.envelope : NxI.magnifyingGlass, size: 20),
            hintText: tr(_mode == 'email' ? 'พิมพ์อีเมลผู้เข้าร่วม' : 'ค้นหาชื่อ'),
            isDense: true,
          ),
        ),
      ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: ListView(
          controller: widget.scroll,
          children: [
            if (_mode == 'email')
              if (emailLooksValid(email))
                ListTile(
                  key: const ValueKey('guest-add-email'),
                  leading: const Icon(NxI.envelope),
                  title: Text(email),
                  trailing: const Icon(NxI.plus),
                  onTap: () {
                    _toggle(ActivityGuest(kind: 'email', email: email.toLowerCase()));
                    _q.clear();
                    setState(() {});
                  },
                )
              else
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(tr('พิมพ์อีเมลให้ครบ เช่น name@company.com'), textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                ),
            for (final g in [..._picked.values.where((p) => p.kind == 'email'), ..._results])
              if (!widget.existing.contains(g.key))
                CheckboxListTile(
                  key: ValueKey('guest-opt-${g.key}'),
                  value: _picked.containsKey(g.key),
                  onChanged: (_) => _toggle(g),
                  secondary: NxAvatar(label: g.display, size: 34),
                  title: Text(g.display, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: [g.email, g.accountName].where((e) => e.isNotEmpty).isEmpty
                      ? null
                      : Text([g.email, g.accountName].where((e) => e.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            if (!_loading && _mode != 'email' && _results.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('ไม่พบรายชื่อ'), textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
              ),
          ],
        ),
      ),
    ]);
  }
}

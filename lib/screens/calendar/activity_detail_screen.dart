import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../services/api_client.dart';
import '../../services/location_service.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/nx_icons.dart';
import '../../core/error_reporting.dart';
import '../../core/nx_page_route.dart';
import '../crm/entity_detail_parts.dart';
import 'activity_form_screen.dart';
import 'cal/cal_model.dart' show hm;
import 'visit_check_sheet.dart';
import '../../core/thai_time.dart';
import '../../core/i18n.dart';
import '../../core/recent_records.dart';
import '../../widgets/nx_refresh.dart';

class ActivityDetailScreen extends StatefulWidget {
  const ActivityDetailScreen({super.key, required this.row});
  final Map<String, dynamic> row;

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  final _location = LocationService();
  Map<String, dynamic>? _visit;
  bool _busy = false;
  Object? _error;
  late Map<String, dynamic> _row = Map<String, dynamic>.from(widget.row);
  int _tab = 0;
  List<Map<String, dynamic>> _comments = [];
  List<Map<String, dynamic>> _timeline = [];
  bool _timelineLoading = false;
  bool _timelineLoaded = false;

  String get _id => strId(widget.row['id']);

  @override
  void initState() {
    super.initState();
    _loadVisit();
    _loadRecord();
  }

  /// Callers often pass only `{id}` (FSM job, related lists) — load the full row.
  Future<void> _loadRecord() async {
    final api = context.read<AppConfig>().apiClient;
    try {
      final rec = await api.getEntity('activity', _id);
      final comments = await api.getEntityComments('activity', _id);
      if (!mounted) return;
      setState(() {
        if (rec.isNotEmpty) _row = {..._row, ...rec};
        _comments = comments;
      });
      RecentRecords.instance.add(
        context.read<AppConfig>().prefsScope,
        module: 'activity',
        id: _id,
        title: '${_row['subject'] ?? entityTitle(_row, module: 'activity')}',
      );
    } catch (e, s) {
      ErrorReporting.report(e, s);
    }
  }

  Future<void> _loadTimeline({bool force = false}) async {
    if ((_timelineLoaded && !force) || _timelineLoading) return;
    setState(() => _timelineLoading = true);
    try {
      final rows = await context.read<AppConfig>().apiClient.getEntityTimeline(
        'activity',
        _id,
      );
      if (mounted) {
        setState(() {
          _timeline = rows;
          _timelineLoaded = true;
        });
      }
    } catch (e, s) {
      ErrorReporting.report(e, s);
    } finally {
      if (mounted) setState(() => _timelineLoading = false);
    }
  }

  Future<void> _edit() async {
    final saved = await nxPush<bool>(
      context,
      ActivityFormScreen(initial: Map<String, dynamic>.from(_row), recordId: _id, title: 'แก้ไขกิจกรรม'),
    );
    if (saved == true && mounted) {
      _timelineLoaded = false;
      await _loadRecord();
    }
  }

  /// Opens the form with a copy (no check-in, new record), like the web.
  Future<void> _duplicate() async {
    final saved = await nxPush<bool>(
      context,
      ActivityFormScreen(initial: ActivityFormScreen.duplicateSeed(_row), title: 'ทำซ้ำกิจกรรม'),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('สร้างกิจกรรมใหม่จากการทำซ้ำแล้ว'))));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ลบกิจกรรมนี้?')),
        content: Text(tr('กด "เลิกทำ" ได้ภายใน 5 วินาที')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('ยกเลิก')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('ลบ')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final api = context.read<AppConfig>().apiClient;
    PendingEntityDeletes.instance.schedule(
      messenger: ScaffoldMessenger.of(context),
      module: 'activity',
      ids: [_id],
      label: entityTitle(_row, module: 'activity'),
      commit: () => api.deleteEntity('activity', _id),
    );
    Navigator.of(context).maybePop();
  }

  Future<void> _quickAttach() async {
    final files = await pickAttachments(context);
    if (files.isEmpty || !mounted) return;
    final api = context.read<AppConfig>().apiClient;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final atts = await api.uploadCommentAttachments(files);
      await api.postEntityComment('activity', _id, '', attachments: atts);
      await _loadRecord();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  Future<void> _loadVisit() async {
    try {
      final visit = await context.read<AppConfig>().apiClient.getActivityVisit(
        _id,
      );
      if (mounted) setState(() => _visit = visit);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _check({required bool inn}) async {
    final checkedAt = parseThai(_visit?['checkindate']);
    final r = await showVisitCheckSheet(
      context,
      activityId: _id,
      checkIn: inn,
      placeName: widget.row['location']?.toString(),
      checkedInAt: checkedAt,
      location: _location,
    );
    if (r == null || !mounted) return;
    await _loadVisit();
  }

  Future<void> _pickPhotos({required bool camera}) async {
    final api = context.read<AppConfig>().apiClient;
    final picker = ImagePicker();
    final files = <XFile>[];
    if (camera) {
      final shot = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (shot != null) files.add(shot);
    } else {
      files.addAll(
        await picker.pickMultiImage(imageQuality: 80, maxWidth: 1600),
      );
    }
    if (!mounted || files.isEmpty) return;
    setState(() => _busy = true);
    try {
      final parts = <MultipartFile>[];
      for (final f in files) {
        final bytes = await f.readAsBytes();
        parts.add(MultipartFile.fromBytes(bytes, filename: f.name));
      }
      await api.uploadActivityPhotos(_id, parts);
      await _loadVisit();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rsvp(String response) async {
    setState(() => _busy = true);
    try {
      await context.read<AppConfig>().apiClient.activityRsvp(_id, response);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr('RSVP: $response'))));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _rsvpLabels = {
    'accepted': 'เข้าร่วม',
    'tentative': 'ไม่แน่ใจ',
    'declined': 'ไม่เข้าร่วม',
  };

  String _when(dynamic raw, [String? field]) {
    final d = parseThaiField(raw, field);
    if (d == null) return raw?.toString() ?? '—';
    return thaiDateTime(d).replaceFirst(RegExp(r':\d\d$'), '');
  }

  /// All-day → dates only; same day → `4 พ.ย. 2569 · 17:54–18:54`.
  String _whenRange(Map<String, dynamic> row) {
    final s = parseWall(row['date_start']);
    final e = parseWall(row['date_end']);
    if (s == null) return _when(row['date_start'], 'date_start');
    final allDay = row['all_day'] == true || row['all_day'] == 1 || '${row['all_day']}' == 'true';
    String day(DateTime d) => activityDayLabel(d);
    final sameDay = e == null || (e.year == s.year && e.month == s.month && e.day == s.day);
    if (allDay) return sameDay ? '${day(s)} · ${tr('ทั้งวัน')}' : '${day(s)} – ${day(e)}';
    if (e == null) return '${day(s)} · ${hm(s)}';
    return sameDay ? '${day(s)} · ${hm(s)}–${hm(e)}' : '${day(s)} ${hm(s)} → ${day(e)} ${hm(e)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final row = _row;
    final checkedIn =
        _visit?['checked_in'] == true ||
        (_visit?['checkindate']?.toString().isNotEmpty ?? false);
    final checkedOut =
        _visit?['checked_out'] == true ||
        (_visit?['checkoutdate']?.toString().isNotEmpty ?? false);
    final photos = extractMapList(_visit?['photos']);
    return NxScrollScaffold(
      insetBody: false,
      header: NxAppHeader(
        title: entityTitle(row, module: 'activity'),
        actions: [
          IconButton(
            tooltip: tr('แก้ไข'),
            icon: const Icon(NxI.pencilSimple),
            onPressed: _edit,
          ),
        ],
        menu: [
          NxHeaderMenuItem(
            label: 'ทำซ้ำ',
            icon: NxI.copySimple,
            onTap: _duplicate,
          ),
          NxHeaderMenuItem(
            label: 'ถ่ายรูป / แนบไฟล์',
            icon: NxI.camera,
            onTap: _quickAttach,
          ),
          NxHeaderMenuItem(label: 'ลบ', icon: NxI.trash, onTap: _delete),
        ],
      ),
      body: Builder(
        builder: (context) => NxRefresh(
          onRefresh: () => Future.wait([_loadRecord(), _loadVisit()]),
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            8 + NxScrollScaffold.topInset(context),
            16,
            32,
          ),
          children: [
            NxSurfaceCard(
              radius: 26,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(entityTitle(row, module: 'activity')),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _line(
                    context,
                    NxI.calendarBlank,
                    _whenRange(row),
                  ),
                  if ((row['location']?.toString() ?? '').isNotEmpty)
                    _line(context, NxI.mapPin, row['location'].toString()),
                  if ((row['status']?.toString() ?? '').isNotEmpty)
                    _line(context, NxI.flag, row['status'].toString()),
                ],
              ),
            ),
            if ((row['description']?.toString() ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              NxSurfaceCard(
                padding: const EdgeInsets.all(16),
                child: NxHtmlView(html: row['description'].toString()),
              ),
            ],
            const SizedBox(height: 14),
            NxSegmented(
              labels: [
                'ภาพรวม',
                _comments.isEmpty
                    ? 'คอมเม้นท์'
                    : 'คอมเม้นท์ ${_comments.length}',
                'ไฟล์',
                'ประวัติ',
              ],
              index: _tab,
              onChanged: (i) {
                setState(() => _tab = i);
                if (i == 3) _loadTimeline();
              },
            ),
            if (_tab == 1) ...[
              const SizedBox(height: 14),
              EntityCommentsPanel(
                module: 'activity',
                id: _id,
                comments: _comments,
                onChanged: _loadRecord,
              ),
            ],
            if (_tab == 2) ...[
              const SizedBox(height: 14),
              EntityFilesPanel(comments: _comments, onAdd: _quickAttach),
            ],
            if (_tab == 3) ...[
              const SizedBox(height: 14),
              EntityHistoryPanel(events: _timeline, loading: _timelineLoading),
            ],
            if (_tab == 0) ...[
              const SizedBox(height: 16),
              Text(
                tr('การเยี่ยม'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              NxSurfaceCard(
                radius: 24,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _stepRow(
                      context,
                      done: checkedIn,
                      title: 'เช็คอิน',
                      value: checkedIn
                          ? _when(_visit?['checkindate'])
                          : 'ยังไม่เช็คอิน',
                    ),
                    _stepRow(
                      context,
                      done: checkedOut,
                      title: 'เช็คเอาท์',
                      value: checkedOut
                          ? _when(_visit?['checkoutdate'])
                          : 'ยังไม่เช็คเอาท์',
                      last: true,
                    ),
                    const SizedBox(height: 12),
                    if (!checkedIn)
                      NxHeroCta(
                        label: 'เช็คอิน',
                        busy: _busy,
                        onPressed: _busy ? null : () => _check(inn: true),
                      )
                    else if (!checkedOut)
                      NxHeroCta(
                        label: 'เช็คเอาท์',
                        busy: _busy,
                        onPressed: _busy ? null : () => _check(inn: false),
                      )
                    else
                      Text(
                        tr('เยี่ยมเสร็จแล้ว'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF16A34A),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('รูปถ่าย (${photos.length})'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('ถ่ายรูป'),
                    icon: const Icon(NxI.camera),
                    onPressed: _busy ? null : () => _pickPhotos(camera: true),
                  ),
                  IconButton(
                    tooltip: tr('แนบรูป'),
                    icon: const Icon(NxI.images),
                    onPressed: _busy ? null : () => _pickPhotos(camera: false),
                  ),
                ],
              ),
              if (photos.isEmpty)
                Text(
                  tr('ยังไม่มีรูป'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                )
              else
                AttachmentStrip(
                  items: [
                    for (final p in photos)
                      {
                        'url': (p['url'] ?? '/uploads/${p['path']}').toString(),
                        'name': p['name'],
                        'mime': p['mime'] ?? 'image/jpeg',
                      },
                  ],
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  tr(formatApiError(_error!)),
                  style: TextStyle(color: cs.error),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                tr('ตอบรับนัด'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in _rsvpLabels.entries)
                    ActionChip(
                      label: Text(tr(e.value)),
                      onPressed: _busy ? null : () => _rsvp(e.key),
                    ),
                ],
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }

  Widget _line(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(tr(text), style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Widget _stepRow(
    BuildContext context, {
    required bool done,
    required String title,
    required String value,
    bool last = false,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const green = Color(0xFF16A34A);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: done ? green : cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  done ? NxI.check : NxI.circle,
                  size: 14,
                  color: done ? Colors.white : cs.onSurfaceVariant,
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    color: done ? green : cs.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(title), style: theme.textTheme.titleSmall),
                  Text(
                    tr(value),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: done ? null : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

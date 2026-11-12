import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_tabs.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../docs/document_preview.dart';
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
import '../../services/photo_pipeline.dart' show PhotoTarget;
import 'visit_photo_flow.dart';
import '../../widgets/nx_place_panel.dart';
import 'package:flutter/services.dart';
import '../../core/thai_time.dart';
import '../../core/i18n.dart';
import '../../core/recent_records.dart';
import '../../widgets/nx_refresh.dart';
import 'package:share_plus/share_plus.dart';

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
        context.read<AppConfig>().businessScope,
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

  /// "ส่งออก / แชร์": the activity as text (when, where, who, details) plus
  /// its web link, to the phone's share sheet (LINE, mail, Notes…) — like the
  /// record pages' "แชร์ลิงก์".
  Future<void> _export() async {
    final base = Uri.tryParse(context.read<AppConfig>().apiBaseUrl);
    final link = base?.replace(path: '/modules/activity/view/$_id', query: null).toString();
    final subject = '${_row['subject'] ?? entityTitle(_row, module: 'activity')}';
    await Share.share(activityExportText(_row, when: _whenRange(_row), link: link), subject: subject);
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
    final checkedAt = parseWall(_visit?['checkindate']);
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
    // Checked in = attending: answer the invite for the user when not done yet.
    if (inn && _myRsvp != 'accepted') _rsvp('accepted', auto: true);
  }

  PhotoRunProgress? _photoProgress;
  VisitPhotoFlow? _photoFlow;

  VisitPhotoFlow _flow() => _photoFlow ??= VisitPhotoFlow(
        upload: (files) => context.read<AppConfig>().apiClient.uploadActivityPhotos(_id, files),
        location: _location,
        target: PhotoTarget('activity', _id),
        onProgress: (p) {
          if (mounted) setState(() => _photoProgress = p);
        },
      );

  /// Camera / gallery / Fast Take → (location watermark?) → batched upload.
  Future<void> _pickPhotos(PhotoSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final n = await _flow().run(context, source);
      if (n > 0) {
        HapticFeedback.mediumImpact();
        messenger.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(tr('อัปโหลด $n รูปแล้ว'))));
      }
    } on PhotoUploadIncomplete catch (e) {
      messenger.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(tr(e.toString()))));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      await _loadVisit();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryPhotos() async {
    setState(() => _busy = true);
    try {
      final n = await _flow().retryPending();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('อัปโหลด $n รูปแล้ว'))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(e.toString()))));
    } finally {
      await _loadVisit();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// My answer to the invite, from `attendees` (kind user = me).
  String? _rsvpLocal;
  String? get _myRsvp {
    if (_rsvpLocal != null) return _rsvpLocal;
    final me = context.read<AppConfig>().session.userId;
    final raw = _row['attendees'];
    final list = raw is List ? raw : const [];
    for (final g in list) {
      if (g is Map && '${g['user_id'] ?? ''}' == me && me != null) {
        final r = '${g['response'] ?? ''}';
        return r.isEmpty || r == 'needsAction' ? null : r;
      }
    }
    return null;
  }

  /// Answer the invite: selected at once (optimistic), Thai snackbar, rolls back on error.
  Future<void> _rsvp(String response, {bool auto = false}) async {
    final before = _myRsvp;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _rsvpLocal = response);
    if (!auto) HapticFeedback.selectionClick();
    try {
      await context.read<AppConfig>().apiClient.activityRsvp(_id, response);
      final label = tr(_rsvpLabels[response] ?? response);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(auto ? tr('เช็คอินแล้ว — ตอบรับนัด "$label" ให้อัตโนมัติ') : tr('ตอบรับนัด: $label')),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _rsvpLocal = before);
      if (!auto) messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  static const _rsvpLabels = {
    'accepted': 'เข้าร่วม',
    'tentative': 'ไม่แน่ใจ',
    'declined': 'ไม่เข้าร่วม',
  };
  static const _rsvpColors = {
    'accepted': Color(0xFF16A34A),
    'tentative': Color(0xFFF59E0B),
    'declined': Color(0xFFDC2626),
  };
  static const _rsvpIcons = {
    'accepted': NxI.checkCircle,
    'tentative': NxI.question,
    'declined': NxI.xCircle,
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

  bool _deciding = false;

  /// Waiting for approval: who decides; the approver approves / rejects here
  /// (like the web's Service Journey panel).
  Widget _approvalCard(BuildContext context, Map<String, dynamic> row) {
    final theme = Theme.of(context);
    final me = context.read<AppConfig>().session.userId;
    final mine = '${row['approver_user_id'] ?? ''}' == '$me';
    Future<void> decide(bool approve) async {
      String? note;
      if (!approve) {
        final ctrl = TextEditingController();
        note = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('ไม่อนุมัติกิจกรรม')),
            content: TextField(key: const ValueKey('act-reject-note'), controller: ctrl, autofocus: true, maxLines: 3, decoration: InputDecoration(labelText: tr('เหตุผล'))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('ยกเลิก'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('ไม่อนุมัติ'))),
            ],
          ),
        );
        if (note == null) return;
      }
      if (!mounted) return;
      final api = context.read<AppConfig>().apiClient;
      final messenger = ScaffoldMessenger.of(context);
      setState(() => _deciding = true);
      try {
        approve ? await api.approveActivity(_id) : await api.rejectActivity(_id, note: note);
        messenger.showSnackBar(SnackBar(content: Text(tr(approve ? 'อนุมัติกิจกรรมแล้ว' : 'ไม่อนุมัติกิจกรรมแล้ว'))));
        await _loadRecord();
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      } finally {
        if (mounted) setState(() => _deciding = false);
      }
    }

    return NxSurfaceCard(
      key: const ValueKey('act-approval'),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(NxI.shieldCheck, size: 18, color: Color(0xFFD97706)),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('กิจกรรมนี้รออนุมัติ'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
        ]),
        if ('${row['approver_name'] ?? row['approver_user_name'] ?? ''}'.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('${tr('ผู้อนุมัติ')}: ${row['approver_name'] ?? row['approver_user_name']}', style: theme.textTheme.bodySmall)),
        if (mine) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: FilledButton.icon(key: const ValueKey('act-approve'), onPressed: _deciding ? null : () => decide(true), icon: const Icon(NxI.check, size: 18), label: Text(tr('อนุมัติ')))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(key: const ValueKey('act-reject'), onPressed: _deciding ? null : () => decide(false), icon: Icon(NxI.x, size: 18, color: theme.colorScheme.error), label: Text(tr('ไม่อนุมัติ'), style: TextStyle(color: theme.colorScheme.error)))),
          ]),
        ],
      ]),
    );
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
            label: 'ส่งออก PDF',
            icon: NxI.filePdf,
            onTap: () => openDocumentPreview(context, activityDocumentSource(_id, subject: '${_row['subject'] ?? ''}')),
          ),
          NxHeaderMenuItem(
            label: 'ส่งออก / แชร์',
            icon: NxI.shareNetwork,
            onTap: _export,
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
        builder: (context) => Stack(children: [
          NxRefresh(
          onRefresh: () => Future.wait([_loadRecord(), _loadVisit()]),
          child: NxSwipeTabs(
            index: _tab,
            count: 4,
            onChanged: _setTab,
            child: ListView(
          controller: _scroll,
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
            if ('${row['approval_state'] ?? ''}' == 'pending') ...[
              const SizedBox(height: 12),
              _approvalCard(context, row),
            ],
            if ((row['description']?.toString() ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              NxSurfaceCard(
                padding: const EdgeInsets.all(16),
                child: NxHtmlView(html: row['description'].toString()),
              ),
            ],
            const SizedBox(height: 14),
            KeyedSubtree(key: _tabsAnchor, child: _tabBar()),
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
                      key: const ValueKey('visit-step-in'),
                      done: checkedIn,
                      title: 'เช็คอิน',
                      value: checkedIn
                          ? _when(_visit?['checkindate'], 'checkindate')
                          : 'ยังไม่เช็คอิน',
                      onTap: checkedIn
                          ? () => showNxPlacePanel(
                                context,
                                title: 'เช็คอิน',
                                at: parseWall(_visit?['checkindate']),
                                lat: _visit?['checkin_lat'],
                                lng: _visit?['checkin_lng'],
                              )
                          : null,
                    ),
                    _stepRow(
                      context,
                      key: const ValueKey('visit-step-out'),
                      done: checkedOut,
                      title: 'เช็คเอาท์',
                      value: checkedOut
                          ? _when(_visit?['checkoutdate'], 'checkoutdate')
                          : 'ยังไม่เช็คเอาท์',
                      last: true,
                      onTap: checkedOut
                          ? () {
                              final p = parseLatLngText(_visit?['location_chkout']);
                              showNxPlacePanel(
                                context,
                                title: 'เช็คเอาท์',
                                at: parseWall(_visit?['checkoutdate']),
                                lat: p?.$1,
                                lng: p?.$2,
                              );
                            }
                          : null,
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
                    key: const ValueKey('visit-photo-camera'),
                    tooltip: tr('ถ่ายรูป'),
                    icon: const Icon(NxI.camera),
                    onPressed: _busy ? null : () => _pickPhotos(PhotoSource.camera),
                  ),
                  IconButton(
                    key: const ValueKey('visit-photo-fast'),
                    tooltip: tr('ถ่ายต่อเนื่อง (Fast Take)'),
                    icon: const Icon(NxI.aperture),
                    onPressed: _busy ? null : () => _pickPhotos(PhotoSource.fastTake),
                  ),
                  IconButton(
                    key: const ValueKey('visit-photo-gallery'),
                    tooltip: tr('อัปโหลดรูป'),
                    icon: const Icon(NxI.images),
                    onPressed: _busy ? null : () => _pickPhotos(PhotoSource.gallery),
                  ),
                ],
              ),
              if (_photoProgress != null)
                Padding(
                  key: const ValueKey('visit-photo-progress'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(_photoProgress!.total > 0
                            ? '${_photoProgress!.label} ${_photoProgress!.done}/${_photoProgress!.total}'
                            : _photoProgress!.label),
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value: _photoProgress!.total == 0 ? null : _photoProgress!.done / _photoProgress!.total,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_photoFlow != null && _photoFlow!.pending.isNotEmpty && !_busy)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    key: const ValueKey('visit-photo-retry'),
                    icon: const Icon(NxI.arrowClockwise, size: 18),
                    label: Text(tr('ลองอัปโหลดใหม่ (${_photoFlow!.pending.length} รูปที่ค้าง)')),
                    onPressed: _retryPhotos,
                  ),
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
                runSpacing: 8,
                children: [
                  for (final e in _rsvpLabels.entries)
                    () {
                      final sel = _myRsvp == e.key;
                      final color = _rsvpColors[e.key]!;
                      return ChoiceChip(
                        key: ValueKey('rsvp-${e.key}'),
                        selected: sel,
                        showCheckmark: false,
                        avatar: Icon(_rsvpIcons[e.key], size: 18, color: sel ? Colors.white : color),
                        label: Text(tr(e.value)),
                        labelStyle: TextStyle(color: sel ? Colors.white : cs.onSurface, fontWeight: sel ? FontWeight.w700 : FontWeight.w500),
                        selectedColor: color,
                        side: BorderSide(color: sel ? color : cs.outlineVariant),
                        onSelected: (_) => sel ? null : _rsvp(e.key),
                      );
                    }(),
                ],
              ),
              if (_myRsvp != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    tr('คุณตอบรับแล้ว: ${_rsvpLabels[_myRsvp] ?? _myRsvp}'),
                    key: const ValueKey('rsvp-current'),
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
            ],
          ],
        ),
        ),
        ),
          NxStickyTabs(
            controller: _scroll,
            anchorKey: _tabsAnchor,
            top: NxScrollScaffold.topInset(context),
            child: _tabBar(),
          ),
        ]),
      ),
    );
  }

  final _scroll = ScrollController();
  final _tabsAnchor = GlobalKey();

  void _setTab(int i) {
    setState(() => _tab = i);
    if (i == 3) _loadTimeline();
  }

  Widget _tabBar() => NxScrollTabs(
        keyPrefix: 'detail-tab-',
        labels: const ['ภาพรวม', 'คอมเม้นท์', 'ไฟล์', 'ประวัติ'],
        icons: const [NxI.sparkle, NxI.chatCircle, NxI.paperclip, NxI.clockCounterClockwise],
        badges: [null, _comments.length, null, null],
        index: _tab,
        onChanged: _setTab,
      );

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
    Key? key,
    required bool done,
    required String title,
    required String value,
    bool last = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: _stepRowBody(context, done: done, title: title, value: value, last: last, tappable: onTap != null),
    );
  }

  Widget _stepRowBody(
    BuildContext context, {
    required bool done,
    required String title,
    required String value,
    required bool last,
    required bool tappable,
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
          if (tappable)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(NxI.mapPin, size: 16, color: cs.primary),
                  const SizedBox(width: 2),
                  Text(tr('ดูพิกัด'), style: theme.textTheme.labelMedium?.copyWith(color: cs.primary)),
                  Icon(NxI.caretRight, size: 16, color: cs.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Plain-text export of an activity (see the detail page's "ส่งออก / แชร์").
String activityExportText(Map<String, dynamic> row, {required String when, String? link}) {
  String v(String k) {
    final s = '${row[k] ?? ''}'.trim();
    return s == 'null' ? '' : s;
  }

  final desc = stripTags(v('description').replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), '\n'));
  final who = [v('account_name'), v('customer_name')].where((e) => e.isNotEmpty).toSet().join(' · ');
  return [
    v('subject').isEmpty ? entityTitle(row, module: 'activity') : v('subject'),
    '${tr('เวลา')}: $when',
    if (v('activitytype').isNotEmpty) '${tr('ประเภท')}: ${v('activitytype')}',
    if (v('status').isNotEmpty) '${tr('สถานะ')}: ${v('status')}',
    if (v('location').isNotEmpty) '${tr('สถานที่')}: ${v('location')}',
    if (who.isNotEmpty) '${tr('ลูกค้า')}: $who',
    if (v('video_conference_url').isNotEmpty) '${tr('ลิงก์')}: ${v('video_conference_url')}',
    if (desc.isNotEmpty) '\n$desc',
    if (link != null && link.isNotEmpty) '\n$link',
  ].join('\n');
}

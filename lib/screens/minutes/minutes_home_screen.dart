import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/minutes/minutes.dart';
import '../../core/navigation/app_routes.dart';
import '../../services/api_client.dart';
import '../../services/minutes/minute_recorder.dart';
import '../../services/minutes/minute_uploader.dart';
import '../../services/realtime_service.dart';
import '../../core/nx_breakpoint.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_back_handler.dart';
import '../../widgets/nx_create_fab.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'minute_record_flow.dart';
import 'minute_join_sheet.dart';
import 'minute_room_create_screen.dart';
import 'minute_upload_sheet.dart';
import 'minutes_widgets.dart';

/// ไอแซคบันทึกประชุม — start a recording, upload a file, open a meeting room, or join one; below, every
/// meeting with search and filters (processing progress live from the socket).
class MinutesHomeScreen extends StatefulWidget {
  const MinutesHomeScreen({super.key, this.initialAction});

  /// `record` | `video` | `upload` | `room` | `join` (deep link / Home shortcut / `/ประชุม`).
  final String? initialAction;

  @override
  State<MinutesHomeScreen> createState() => _MinutesHomeScreenState();
}

class _MinutesHomeScreenState extends State<MinutesHomeScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  StreamSubscription<RealtimeEvent>? _sub;
  StreamSubscription<FinishedMinute>? _finSub;
  StreamSubscription<MinuteUploadJob>? _upSub;
  List<MinuteMeeting> _items = const [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';
  bool _roomsAvailable = false;

  ApiClient get _api => context.read<AppConfig>().apiClient;

  @override
  void initState() {
    super.initState();
    _load();
    _loadConfig();
    _sub = RealtimeService.instance.events.listen(_onEvent);
    _finSub = MinuteRecorder.instance.finished.listen((_) => _load(quiet: true));
    _upSub = MinuteUploader.instance.done.listen((_) => _load(quiet: true));
    final a = widget.initialAction;
    if (a != null) WidgetsBinding.instance.addPostFrameCallback((_) => _runAction(a));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    _finSub?.cancel();
    _upSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final c = await _api.getMinutesConfig();
      if (mounted) setState(() => _roomsAvailable = c['rooms'] == true);
    } catch (_) {}
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final rows = await _api.getMinuteMeetings(q: _search.text, source: _filter == 'all' ? null : _filter);
      if (!mounted) return;
      setState(() {
        _items = [for (final r in rows) MinuteMeeting.fromJson(r)];
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiEnvelopeException ? e.message : 'โหลดรายการไม่สำเร็จ';
        _loading = false;
      });
    }
  }

  void _onEvent(RealtimeEvent e) {
    if (e.type == 'ai:minute_status') {
      final id = '${e.data['meeting_id']}';
      final i = _items.indexWhere((m) => m.id == id);
      if (i < 0) return;
      setState(() {
        _items = [..._items]..[i] = _items[i].copyWith(status: '${e.data['status'] ?? _items[i].status}', progress: (e.data['progress'] as num?)?.toInt(), stage: e.data['stage']?.toString());
      });
    } else if (e.type == 'ai:minute_ready') {
      _load(quiet: true);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(quiet: true));
  }

  Future<void> _runAction(String a) async {
    switch (a) {
      case 'record':
      case 'video':
        await startMinuteRecording(context, video: a == 'video');
      case 'upload':
        await showMinuteUploadSheet(context);
      case 'room':
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MinuteRoomCreateScreen()));
      case 'join':
        await showMinuteJoinSheet(context);
      default:
        // `/m/<code>` link: straight to the lobby.
        if (a.startsWith('join:')) await openMinuteLobby(context, a.substring(5));
    }
    if (mounted) _load(quiet: true);
  }

  bool _searching = false;

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching && _search.text.isNotEmpty) {
        _search.clear();
        _load(quiet: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final groups = _groups();
    return NxBackHandler(
      active: _searching,
      onBack: _toggleSearch,
      child: NxScrollScaffold(
        key: const ValueKey('minutes-home'),
        header: NxAppHeader(
          title: 'ไอแซคบันทึกประชุม',
          subtitle: 'บันทึก · ถอดข้อความ · สรุป · แปล',
          actions: [
            IconButton(
              key: const ValueKey('minutes-search-toggle'),
              tooltip: tr(_searching ? 'ปิดค้นหา' : 'ค้นหา'),
              icon: Icon(_searching ? NxI.x : NxI.magnifyingGlass),
              onPressed: _toggleSearch,
            ),
            IconButton(
              key: const ValueKey('minutes-header-join'),
              tooltip: tr('เข้าร่วมด้วยรหัส'),
              icon: const Icon(NxI.signIn),
              onPressed: () => _runAction('join'),
            ),
            if (NxBreakpoint.of(context).twoPane) NxAddButton(tooltip: tr('เริ่มใหม่'), onPressed: _openCommands),
          ],
        ),
        floatingActionButton: NxCreateFab(key: const ValueKey('minutes-fab'), label: 'เริ่มใหม่', onPressed: _openCommands),
        body: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              if (_searching)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: TextField(
                      key: const ValueKey('minutes-search'),
                      controller: _search,
                      autofocus: true,
                      onChanged: _onSearch,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(NxI.magnifyingGlass, size: 20),
                        hintText: tr('ค้นหาชื่อหรือคำที่พูดในการประชุม'),
                        filled: true,
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(child: _activeBanner()),
              SliverToBoxAdapter(child: _uploads()),
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      for (final f in const [('all', 'ทั้งหมด', NxI.squaresFour), ('record', 'บันทึกสด', NxI.microphone), ('upload', 'ไฟล์', NxI.uploadSimple), ('room', 'ห้องประชุม', NxI.users)])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            key: ValueKey('minutes-filter-${f.$1}'),
                            avatar: Icon(f.$3, size: 16),
                            label: Text(tr(f.$2)),
                            selected: _filter == f.$1,
                            showCheckmark: false,
                            onSelected: (_) {
                              setState(() => _filter = f.$1);
                              _load(quiet: true);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(tr(_error!)), TextButton(onPressed: _load, child: Text(tr('ลองอีกครั้ง')))])),
                )
              else if (_items.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: _empty(theme, cs))
              else
                for (final g in groups) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                      child: Text(tr(g.$1), style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  SliverList.builder(itemCount: g.$2.length, itemBuilder: (_, i) => _MeetingCard(meeting: g.$2[i], onTap: () => _open(g.$2[i]))),
                ],
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
    );
  }

  /// Meetings by day: วันนี้ / เมื่อวาน / 7 วันที่ผ่านมา / ก่อนหน้า.
  List<(String, List<MinuteMeeting>)> _groups() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <String, List<MinuteMeeting>>{};
    for (final m in _items) {
      final t = m.startedAt;
      final d = t == null ? null : DateTime(t.year, t.month, t.day);
      final key = d == null
          ? 'ก่อนหน้า'
          : d == today
          ? 'วันนี้'
          : d == today.subtract(const Duration(days: 1))
          ? 'เมื่อวาน'
          : today.difference(d).inDays < 7
          ? '7 วันที่ผ่านมา'
          : 'ก่อนหน้า';
      (out[key] ??= []).add(m);
    }
    return [for (final k in const ['วันนี้', 'เมื่อวาน', '7 วันที่ผ่านมา', 'ก่อนหน้า']) if (out[k] != null) (k, out[k]!)];
  }

  Widget _empty(ThemeData theme, ColorScheme cs) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: const BoxDecoration(gradient: kMinuteGradient, shape: BoxShape.circle),
          child: const Icon(NxI.microphone, color: Colors.white, size: 38),
        ),
        const SizedBox(height: 16),
        Text(tr(_search.text.isEmpty ? 'ยังไม่มีการประชุม' : 'ไม่พบการประชุมที่ค้นหา'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(tr('เริ่มบันทึก อัปโหลดไฟล์ หรือเปิดห้องประชุม แล้วไอแซคจะถอดข้อความ สรุป และแปลให้'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        if (_search.text.isEmpty) ...[
          const SizedBox(height: 18),
          FilledButton.icon(key: const ValueKey('minutes-empty-start'), onPressed: _openCommands, icon: const Icon(NxI.plus), label: Text(tr('เริ่มประชุมแรก'))),
        ],
      ],
    ),
  );

  /// "+" → what to start: record / video / upload / room / join.
  Future<void> _openCommands() async {
    final a = await showMinuteCommandSheet(context, roomsAvailable: _roomsAvailable);
    if (a != null && mounted) await _runAction(a);
  }

  Future<void> _open(MinuteMeeting m) async {
    await context.push(AppRoutes.aiMinute(m.id));
    if (mounted) _load(quiet: true);
  }

  Widget _activeBanner() {
    return ListenableBuilder(
      listenable: MinuteRecorder.instance,
      builder: (context, _) {
        final r = MinuteRecorder.instance;
        if (!r.active) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Material(
            color: kMinuteRecord.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            child: ListTile(
              key: const ValueKey('minutes-active'),
              leading: const Icon(NxI.microphone, color: kMinuteRecord),
              title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(tr(r.paused ? 'หยุดชั่วคราว — แตะเพื่อกลับไปที่การบันทึก' : 'กำลังบันทึก — แตะเพื่อกลับไปที่การบันทึก')),
              trailing: const Icon(NxI.caretRight),
              onTap: () => openMinuteRecorder(context, r),
            ),
          ),
        );
      },
    );
  }

  Widget _uploads() {
    return ListenableBuilder(
      listenable: MinuteUploader.instance,
      builder: (context, _) {
        final jobs = MinuteUploader.instance.jobs.where((j) => j.state != 'done').toList();
        if (jobs.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            children: [
              for (final j in jobs)
                Card(
                  key: ValueKey('minutes-upload-${j.uploadId}'),
                  margin: const EdgeInsets.only(bottom: 6),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                    child: Row(
                      children: [
                        const Icon(NxI.uploadSimple, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(j.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(value: j.progress, minHeight: 5, borderRadius: BorderRadius.circular(9)),
                              const SizedBox(height: 4),
                              Text(
                                j.state == 'failed'
                                    ? (j.error ?? tr('อัปโหลดไม่สำเร็จ'))
                                    : j.state == 'paused'
                                    ? (j.error ?? tr('รอเครือข่าย — จะอัปโหลดต่อให้อัตโนมัติ'))
                                    : '${tr('กำลังอัปโหลด')} ${(j.progress * 100).round()}% · ${_mb(j.sentBytes)} / ${_mb(j.size)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (j.state == 'paused') IconButton(tooltip: tr('ลองอีกครั้ง'), icon: const Icon(NxI.arrowClockwise), onPressed: MinuteUploader.instance.retryNow),
                        IconButton(tooltip: tr('ยกเลิก'), icon: const Icon(NxI.x), onPressed: () => MinuteUploader.instance.cancel(j)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _mb(int bytes) => bytes >= 1 << 30 ? '${(bytes / (1 << 30)).toStringAsFixed(2)} GB' : '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
}

class _MeetingCard extends StatelessWidget {
  const _MeetingCard({required this.meeting, required this.onTap});
  final MinuteMeeting meeting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final m = meeting;
    final color = minuteSourceColor(m.source);
    final t = m.startedAt;
    final time = t == null ? '' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final text = m.snippet ?? m.headline;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: dark ? cs.surfaceContainer : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: ValueKey('minute-card-${m.id}'),
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: cs.outlineVariant.withValues(alpha: dark ? 0.25 : 0.5))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: color.withValues(alpha: dark ? 0.22 : 0.12), borderRadius: BorderRadius.circular(14)),
                  child: Icon(minuteSourceIcon(m), color: minuteTint(context, color), size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(NxI.clock, size: 13, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(time, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          if (m.durationMs > 0) ...[
                            const SizedBox(width: 10),
                            Icon(NxI.timer, size: 13, color: cs.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(minuteClock(m.durationMs), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                          const SizedBox(width: 10),
                          Flexible(child: Text(tr(minuteSourceLabel(m.source)), overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: minuteTint(context, color), fontWeight: FontWeight.w600))),
                        ],
                      ),
                      if (text != null) ...[
                        const SizedBox(height: 8),
                        Text(text, key: m.snippet != null ? ValueKey('minute-snippet-${m.id}') : null, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.78), height: 1.4)),
                      ],
                      if (!m.ready) ...[const SizedBox(height: 8), MinuteStatusChip(meeting: m)],
                    ],
                  ),
                ),
                Icon(NxI.caretRight, size: 18, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

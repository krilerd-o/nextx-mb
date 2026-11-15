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
import '../../widgets/nx_icons.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      key: const ValueKey('minutes-home'),
      appBar: AppBar(title: Text(tr('ไอแซคบันทึกประชุม')), centerTitle: false),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _hero(theme)),
            SliverToBoxAdapter(child: _activeBanner()),
            SliverToBoxAdapter(child: _uploads()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  key: const ValueKey('minutes-search'),
                  controller: _search,
                  onChanged: _onSearch,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(NxI.magnifyingGlass, size: 20),
                    hintText: tr('ค้นหาชื่อหรือคำในการประชุม'),
                    filled: true,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    for (final f in const [('all', 'ทั้งหมด'), ('record', 'บันทึกสด'), ('upload', 'ไฟล์'), ('room', 'ห้องประชุม')])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          key: ValueKey('minutes-filter-${f.$1}'),
                          label: Text(tr(f.$2)),
                          selected: _filter == f.$1,
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
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [Text(tr(_error!)), TextButton(onPressed: _load, child: Text(tr('ลองอีกครั้ง')))]),
                ),
              )
            else if (_items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(NxI.microphone, size: 40, color: cs.outline),
                      const SizedBox(height: 10),
                      Text(tr(_search.text.isEmpty ? 'ยังไม่มีการประชุม' : 'ไม่พบการประชุมที่ค้นหา'), style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(tr('เริ่มบันทึก อัปโหลดไฟล์ หรือเปิดห้องประชุม แล้วไอแซคจะถอดข้อความ สรุป และแปลให้'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              )
            else
              SliverList.builder(itemCount: _items.length, itemBuilder: (_, i) => _MeetingCard(meeting: _items[i], onTap: () => _open(_items[i]))),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Future<void> _open(MinuteMeeting m) async {
    await context.push(AppRoutes.aiMinute(m.id));
    if (mounted) _load(quiet: true);
  }

  Widget _hero(ThemeData theme) {
    Widget tile(String key, IconData icon, String label, String hint, {Color? color, bool enabled = true}) {
      return Expanded(
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Material(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              key: ValueKey('minutes-action-$key'),
              borderRadius: BorderRadius.circular(18),
              onTap: enabled ? () => _runAction(key) : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ผู้ดูแลยังไม่ได้เปิดใช้ห้องประชุม')))),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: color ?? Colors.white, shape: BoxShape.circle),
                      child: Icon(icon, size: 20, color: color == null ? const Color(0xFF4F46E5) : Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    Text(tr(hint), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 10.5)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(gradient: kMinuteGradient, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('บันทึก ถอดข้อความ สรุป และแปลการประชุม'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(tr('ไอแซคจดให้ครบ ทั้งสด และย้อนหลัง'), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          const SizedBox(height: 14),
          Row(
            children: [
              tile('record', NxI.microphone, 'บันทึกเสียง', 'ถอดสด', color: kMinuteRecord),
              const SizedBox(width: 8),
              tile('video', NxI.videoCamera, 'บันทึกวิดีโอ', 'กล้อง + ถอดสด'),
              const SizedBox(width: 8),
              tile('upload', NxI.uploadSimple, 'อัปโหลดไฟล์', 'เสียง / วิดีโอ'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              tile('room', NxI.users, 'สร้างห้องประชุม', 'ลิงก์เชิญ', enabled: _roomsAvailable),
              const SizedBox(width: 8),
              tile('join', NxI.signIn, 'เข้าร่วมด้วยรหัส', 'รหัสห้อง / ลิงก์', enabled: _roomsAvailable),
            ],
          ),
        ],
      ),
    );
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
    final m = meeting;
    final color = minuteSourceColor(m.source);
    final sub = [minuteWhen(m.startedAt), if (m.durationMs > 0) minuteClock(m.durationMs), tr(minuteSourceLabel(m.source))].where((s) => s.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: ValueKey('minute-card-${m.id}'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                  child: Icon(minuteSourceIcon(m), color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(sub, style: theme.textTheme.bodySmall),
                      if ((m.snippet ?? m.headline) != null) ...[
                        const SizedBox(height: 6),
                        Text(m.snippet ?? m.headline!, key: m.snippet != null ? ValueKey('minute-snippet-${m.id}') : null, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                      const SizedBox(height: 8),
                      MinuteStatusChip(meeting: m),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

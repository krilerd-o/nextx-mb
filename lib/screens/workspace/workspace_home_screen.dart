import '../../core/nx_number.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../core/workspace_models.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_overlay_panel.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_refresh_bar.dart';
import '../../core/nx_swr_cache.dart';
import 'task_detail_screen.dart';
import 'workspace_board_screen.dart';
import 'workspace_trash_screen.dart';
import '../../widgets/nx_refresh.dart';
import '../../widgets/nx_list_toolbar.dart';

/// Which of my open items to show at the top.
enum WsMyScope { today, overdue, week, all }

/// Filters my open items by due date (Thai calendar days).
List<Map<String, dynamic>> wsMyWork(List<Map<String, dynamic>> items, WsMyScope scope) {
  final out = [
    for (final it in items)
      if (switch (scope) {
        WsMyScope.overdue => (wsDueIn(it['due_date']) ?? 1) < 0,
        WsMyScope.today => wsDueIn(it['due_date']) == 0,
        WsMyScope.week => (wsDueIn(it['due_date']) ?? 99) <= 7,
        WsMyScope.all => true,
      })
        it,
  ];
  out.sort((a, b) => (wsDueIn(a['due_date']) ?? 9999).compareTo(wsDueIn(b['due_date']) ?? 9999));
  return out;
}

/// Workspace home: my open work across every board (overdue / today / this
/// week), then the boards with progress; trash and board duplicate in reach.
class WorkspaceHomeScreen extends StatefulWidget {
  const WorkspaceHomeScreen({super.key});

  @override
  State<WorkspaceHomeScreen> createState() => _WorkspaceHomeScreenState();
}

/// Last load ([NxSwrCache], per server + user + Space), so coming back shows
/// it at once and refreshes underneath (never another Space's boards).
final _boardsKey = NxSwrCache.key('/api/boards');
final _mineKey = NxSwrCache.key('/api/workspace/items', query: const {'mine': 1});

class _WorkspaceHomeScreenState extends State<WorkspaceHomeScreen> {
  List<Map<String, dynamic>>? _boards = NxSwrCache.instance.peek<List<Map<String, dynamic>>>(_boardsKey);
  List<Map<String, dynamic>>? _mine = NxSwrCache.instance.peek<List<Map<String, dynamic>>>(_mineKey);

  /// Showing the last copy while it reloads.
  bool _refreshing = false;
  String? _error;
  WsMyScope _scope = WsMyScope.today;
  bool _expanded = false;
  NxListQuery _query = const NxListQuery();

  /// My-work box starts folded (remembered per device).
  bool _myOpen = false;
  static const _kMyOpen = 'ws_home_mywork_open';

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getBool(_kMyOpen);
      if (v != null && mounted) setState(() => _myOpen = v);
    } catch (_) {}
  }

  void _toggleMy() {
    HapticFeedback.selectionClick();
    setState(() => _myOpen = !_myOpen);
    SharedPreferences.getInstance().then((p) => p.setBool(_kMyOpen, _myOpen)).catchError((_) => false);
  }


  ApiClient get _api => context.read<AppConfig>().apiClient;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _load();
  }

  Future<void> _load() async {
    final me = context.read<AppConfig>().session.userId;
    if (_boards != null) setState(() => _refreshing = true);
    try {
      final r = await Future.wait([
        _api.getBoards(),
        if (me != null)
          _api.getWorkspaceItems(assigneeId: me, excludeDone: true, limit: 200).catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _boards = r[0];
        for (final b in r[0]) {
          wsRememberBoard(b);
        }
        _mine = r.length > 1 ? r[1] : const [];
        _error = null;
        _refreshing = false;
      });
      NxSwrCache.instance.put(_boardsKey, _boards);
      NxSwrCache.instance.put(_mineKey, _mine);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = formatApiError(e);
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _openBoard(Map<String, dynamic> b) async {
    await nxPush<void>(context, WorkspaceBoardScreen(board: b));
    if (mounted) _load();
  }

  Future<void> _openItem(Map<String, dynamic> it) async {
    await nxOpenDetail<void>(
      context,
      TaskDetailScreen(task: {...it, if (it['item_type'] == 'epic') '_kind': 'epic'}),
    );
    if (mounted) _load();
  }

  Future<void> _duplicateBoard(Map<String, dynamic> b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ทำซ้ำบอร์ด?')),
        content: Text(tr('สร้างบอร์ดใหม่จาก "${b['name']}" พร้อมสถานะและงานทั้งหมด')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ทำซ้ำ'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final nb = await _api.duplicateBoard('${b['id']}');
      HapticFeedback.mediumImpact();
      messenger.showSnackBar(SnackBar(content: Text(tr('ทำซ้ำบอร์ดแล้ว'))));
      await _load();
      final id = '${nb['id'] ?? nb['board_id'] ?? ''}';
      final row = _boards?.where((x) => '${x['id']}' == id).firstOrNull;
      if (row != null && mounted) _openBoard(row);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  void _boardMenu(Map<String, dynamic> b) {
    HapticFeedback.selectionClick();
    showNxBlurPanel<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(NxI.kanban),
              title: Text(tr('เปิดบอร์ด')),
              onTap: () {
                Navigator.pop(ctx);
                _openBoard(b);
              },
            ),
            ListTile(
              leading: const Icon(NxI.copySimple),
              title: Text(tr('ทำซ้ำบอร์ด')),
              onTap: () {
                Navigator.pop(ctx);
                _duplicateBoard(b);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _buildPage(context);


  Widget _buildPage(BuildContext context) {
    final theme = Theme.of(context);
    final boards = _boards;
    // Search board name, code and description (case-insensitive, any word order).
    final words = _query.q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final shownBoards = [
      for (final b in boards ?? const <Map<String, dynamic>>[])
        if (words.isEmpty || words.every('${b['name'] ?? ''} ${b['code'] ?? ''} ${b['description'] ?? ''}'.toLowerCase().contains)) b,
    ];
    return NxScrollScaffold(
      header: NxAppHeader(
        title: 'Workspace',
        actions: [
          IconButton(
            tooltip: tr('ถังขยะ'),
            icon: const Icon(NxI.trash),
            onPressed: () async {
              await nxPush<void>(context, const WorkspaceTrashScreen());
              if (mounted) _load();
            },
          ),
        ],
      ),
      // Same search bar as the other lists (header search icon, live filter) — the old in-list
      // field could lose the keyboard on Android when the page re-laid out.
      body: Column(children: [
        NxListToolbar(
          key: const ValueKey('ws-board-toolbar'),
          query: _query,
          liveSearch: true,
          allowSavedViews: false,
          searchHint: 'ค้นหาบอร์ด',
          onChanged: (q) => setState(() => _query = q),
        ),
        NxRefreshBar(visible: _refreshing),
        Expanded(
          child: NxRefresh(
        onRefresh: _load,
        child: boards == null && _error == null
            ? const _WsHomeSkeleton()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  if (_error != null && boards == null)
                    Padding(padding: const EdgeInsets.all(24), child: Text(tr(_error!), textAlign: TextAlign.center)),
                  if (_mine != null) _myWork(context),
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(child: Text(tr('บอร์ด'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                    Text(
                      words.isEmpty ? '${boards?.length ?? 0}' : '${shownBoards.length}/${boards?.length ?? 0}',
                      style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  if (boards != null && boards.isEmpty)
                    Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tr('ยังไม่มีบอร์ด')))),
                  if (boards != null && boards.isNotEmpty && shownBoards.isEmpty)
                    Padding(
                      key: const ValueKey('ws-board-none'),
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text('${tr('ไม่พบบอร์ดที่ตรงกับ')} "${_query.q}"', textAlign: TextAlign.center)),
                    ),
                  for (final b in shownBoards) _boardCard(context, b),
                ],
              ),
          ),
        ),
      ]),
    );
  }

  Widget _myWork(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final all = _mine!;
    final counts = {for (final s in WsMyScope.values) s: wsMyWork(all, s).length};
    final list = wsMyWork(all, _scope);
    final shown = _expanded ? list : list.take(6).toList();
    const labels = {WsMyScope.overdue: 'เลยกำหนด', WsMyScope.today: 'วันนี้', WsMyScope.week: 'สัปดาห์นี้', WsMyScope.all: 'ทั้งหมด'};
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary.withValues(alpha: 0.12), cs.tertiary.withValues(alpha: 0.06)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('ws-my-toggle'),
            borderRadius: BorderRadius.circular(12),
            onTap: _toggleMy,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(NxI.user, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(tr('งานของฉัน'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                Text('${tr('วันนี้')} ${nxInt(counts[WsMyScope.today])} · ${tr('ค้าง')} ${nxInt(all.length)}', style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _myOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(NxI.caretDown, size: 18, color: cs.onSurfaceVariant),
                ),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_myOpen
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final s in WsMyScope.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('${tr(labels[s]!)} ${counts[s]}'),
                    selected: _scope == s,
                    selectedColor: s == WsMyScope.overdue && counts[s]! > 0 ? cs.errorContainer : null,
                    onSelected: (_) => setState(() {
                      _scope = s;
                      _expanded = false;
                    }),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 6),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(child: Text(tr('ไม่มีงานในช่วงนี้ 🎉'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
            ),
          for (final it in shown) _myRow(context, it),
          if (list.length > shown.length)
            TextButton(onPressed: () => setState(() => _expanded = true), child: Text('${tr('ดูทั้งหมด')} ${nxInt(list.length)} ${tr('งาน')}')),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _myRow(BuildContext context, Map<String, dynamic> it) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final type = wsTypeStyle(it['item_type'] == 'epic' ? 'epic' : '${it['type'] ?? 'task'}');
    final due = wsDueIn(it['due_date']);
    final p = wsPriorityStyle('${it['priority'] ?? 'medium'}');
    final status = '${(L10n.isEn ? it['status_label_en'] : it['status_label_th']) ?? it['status_name'] ?? ''}';
    return InkWell(
      onTap: () => _openItem(it),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(type.icon, size: 18, color: type.color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(wsTitle(it), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                    [wsKey(it), if (it['board_name'] != null) '${it['board_name']}', if (status.isNotEmpty) status].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(p.icon, size: 16, color: p.color),
            if (due != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (due < 0 ? cs.error : due == 0 ? const Color(0xFFF59E0B) : cs.primary).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  due < 0 ? tr('เลย ${-due} วัน') : due == 0 ? tr('วันนี้') : wsShortDate(it['due_date']),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: due < 0 ? cs.error : due == 0 ? const Color(0xFFB45309) : cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _boardCard(BuildContext context, Map<String, dynamic> b) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final total = wsInt(b['task_count']) ?? 0;
    final done = wsInt(b['done_count']) ?? 0;
    final hex = '${b['color'] ?? ''}'.replaceAll('#', '');
    final color = hex.length == 6 && int.tryParse(hex, radix: 16) != null ? Color(0xFF000000 | int.parse(hex, radix: 16)) : cs.primary;
    final members = wsInt(b['member_count']) ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: ValueKey('ws-board-${b['id']}'),
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openBoard(b),
          onLongPress: () => _boardMenu(b), // long-press: anchored at the finger
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                    child: (b['icon'] ?? '').toString().isNotEmpty && '${b['icon']}'.runes.length <= 2
                        ? Text('${b['icon']}', style: const TextStyle(fontSize: 20))
                        : Icon(NxI.kanban, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${b['name'] ?? tr('บอร์ด')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        Text(
                          [
                            // Automatic deal codes (D26…) say nothing to people — hide them.
                            if ('${b['code'] ?? ''}'.isNotEmpty && !RegExp(r'^D\d{8,}$').hasMatch('${b['code']}') && '${b['code']}'.toUpperCase() != '${b['name'] ?? ''}'.toUpperCase())
                              '${b['code']}',
                            '${nxInt(total)} ${tr('งาน')}',
                            if (members > 0) '${nxInt(members)} ${tr('สมาชิก')}',
                          ].join(' · '),
                          style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Builder(builder: (bc) => IconButton(tooltip: tr('เพิ่มเติม'), icon: const Icon(NxI.dotsThree), onPressed: NxTapTracker.from(bc, () => _boardMenu(b)))),
                ]),
                if (total > 0) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: done / total, minHeight: 6, color: color, backgroundColor: color.withValues(alpha: 0.12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${tr('เสร็จ')} ${nxInt(done)}/${nxInt(total)}', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Workspace home while loading: the folded "งานของฉัน" gradient card, the
/// boards heading, and board cards (icon tile, name, counts, progress bar).
class _WsHomeSkeleton extends StatelessWidget {
  const _WsHomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return NxSkeleton(
      key: const ValueKey('ws-home-skeleton'),
      child: NxSkeletonListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary.withValues(alpha: 0.12), cs.tertiary.withValues(alpha: 0.06)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Row(children: [NxBone(width: 18, height: 18, radius: 5), SizedBox(width: 8), NxBone(width: 90, height: 15), Spacer(), NxBone(width: 96, height: 11)]),
          ),
          const SizedBox(height: 18),
          const Row(children: [NxBone(width: 56, height: 16), Spacer(), NxBone(width: 20, height: 12)]),
          const SizedBox(height: 12),
          for (var i = 0; i < 5; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const NxBone(width: 40, height: 40, radius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      NxBoneLine(i.isEven ? 0.6 : 0.42, height: 14),
                      const SizedBox(height: 7),
                      const NxBoneLine(0.36, height: 10),
                    ]),
                  ),
                  const NxBone(width: 20, height: 6, radius: 3),
                ]),
                if (i % 3 != 2) ...[
                  const SizedBox(height: 12),
                  const Row(children: [Expanded(child: NxBone(height: 6, radius: 3)), SizedBox(width: 8), NxBone(width: 56, height: 10)]),
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

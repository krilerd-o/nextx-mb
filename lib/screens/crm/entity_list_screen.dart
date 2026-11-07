import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_create_fab.dart';
import '../../widgets/nx_entity_row.dart';
import '../../widgets/nx_filter_chips.dart';
import '../../widgets/nx_search_field.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_split_view.dart';
import 'entity_create_screen.dart';
import 'entity_detail_parts.dart';
import 'entity_detail_screen.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/entity_display.dart';
import '../../widgets/nx_icons.dart';

class EntityListScreen extends StatefulWidget {
  const EntityListScreen({
    super.key,
    required this.module,
    required this.title,
  });

  final String module;
  final String title;

  @override
  State<EntityListScreen> createState() => _EntityListScreenState();
}

class _EntityListScreenState extends State<EntityListScreen> {
  final _searchController = TextEditingController();
  final _scroll = ScrollController();
  final _items = <Map<String, dynamic>>[];

  /// Ids picked in multi-select mode (long-press a row).
  final Set<String> _picked = {};

  List<Map<String, dynamic>> get _visible => [
        for (final r in _items)
          if (!PendingEntityDeletes.instance.isPending(widget.module, r['id']?.toString() ?? '')) r,
      ];

  void _onPendingChanged() {
    if (mounted) setState(() {});
  }

  void _deleteIds(List<String> ids, String label) {
    final api = context.read<AppConfig>().apiClient;
    PendingEntityDeletes.instance.schedule(
      messenger: ScaffoldMessenger.of(context),
      module: widget.module,
      ids: ids,
      label: label,
      commit: () async {
        if (ids.length == 1) {
          await api.deleteEntity(widget.module, ids.first);
        } else {
          await api.bulkDeleteEntities(widget.module, ids);
        }
        if (mounted) _load(reset: true);
      },
    );
  }

  void _togglePick(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    if (id == null) return;
    HapticFeedback.selectionClick();
    setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id));
  }
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  Object? _error;
  int _page = 1;
  bool _hasMore = true;
  String _q = '';
  NxEntityFilter _filter = NxEntityFilter.all;
  bool _showMine = true;
  Map<String, dynamic>? _selected;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    PendingEntityDeletes.instance.addListener(_onPendingChanged);
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    PendingEntityDeletes.instance.removeListener(_onPendingChanged);
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 240) {
      _load();
    }
  }

  Map<String, String>? _extra() {
    switch (_filter) {
      case NxEntityFilter.all:
        return null;
      case NxEntityFilter.mine:
        if (widget.module == 'activity') {
          return const {'involved': '1'};
        }
        final uid = context.read<AppConfig>().session.userId;
        if (uid == null || uid.isEmpty) return null;
        return {'filter[smownerid]': uid};
      case NxEntityFilter.recent:
        return const {'sort': 'modifiedtime', 'order': 'desc'};
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = _items.isEmpty;
        _refreshing = _items.isNotEmpty;
        _error = null;
        _page = 1;
        _hasMore = true;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    if (!context.read<AppConfig>().isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
        _hasMore = false;
      });
      return;
    }
    try {
      final page = await context.read<AppConfig>().apiClient.getEntityList(
            widget.module,
            limit: 30,
            page: _page,
            q: _q.isEmpty ? null : _q,
            extra: _extra(),
          );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(page.items);
        } else {
          _items.addAll(page.items);
        }
        _hasMore = page.hasMore && page.items.isNotEmpty;
        _page += 1;
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (_filter == NxEntityFilter.mine) {
        setState(() {
          _showMine = false;
          _filter = NxEntityFilter.all;
          _loading = false;
          _refreshing = false;
          _loadingMore = false;
        });
        await _load(reset: true);
        return;
      }
      setState(() {
        _error = e;
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _openCreate() async {
    final twoPane = NxBreakpoint.of(context).twoPane;
    if (twoPane) {
      setState(() {
        _creating = true;
        _selected = null;
      });
      return;
    }
    final created = await nxPush<bool>(
      context,
      EntityCreateScreen(module: widget.module, title: 'สร้าง${widget.title}'),
      root: true,
    );
    if (created == true) _load(reset: true);
  }

  Widget _detail() {
    if (_creating) {
      return EntityCreateScreen(
        module: widget.module,
        title: 'สร้าง${widget.title}',
        embedded: true,
        onFinished: (ok) {
          setState(() => _creating = false);
          if (ok) _load(reset: true);
        },
      );
    }
    if (_selected == null) return const SizedBox.shrink();
    return EntityDetailScreen(
      key: ValueKey(_selected!['id']),
      module: widget.module,
      row: _selected!,
      embedded: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final twoPane = NxBreakpoint.of(context).twoPane;
    final bp = NxBreakpoint.of(context);
    final list = Column(
      children: [
        if (_refreshing) const LinearProgressIndicator(minHeight: 2),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: NxSearchField(
            controller: _searchController,
            hint: 'ค้นหา${widget.title}',
            onSubmitted: (v) {
              _q = v.trim();
              _load(reset: true);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: NxFilterChips(
            value: _filter,
            showMine: _showMine && context.select((AppConfig c) => c.session).userId != null,
            onChanged: (f) {
              setState(() => _filter = f);
              _load(reset: true);
            },
          ),
        ),
        Expanded(child: _body(Theme.of(context), twoPane: twoPane, bp: bp)),
      ],
    );

    return Scaffold(
      appBar: _picked.isNotEmpty
          ? AppBar(
              leading: IconButton(tooltip: 'ยกเลิก', icon: const Icon(NxI.x), onPressed: () => setState(_picked.clear)),
              title: Text('เลือก ${_picked.length} รายการ'),
              actions: [
                IconButton(
                  tooltip: 'เลือกทั้งหมด',
                  icon: const Icon(NxI.checkCircle),
                  onPressed: () => setState(() => _picked.addAll([for (final r in _visible) if (r['id'] != null) r['id'].toString()])),
                ),
                IconButton(
                  tooltip: 'ลบที่เลือก',
                  icon: const Icon(NxI.trash),
                  onPressed: () {
                    final ids = _picked.toList();
                    setState(_picked.clear);
                    _deleteIds(ids, '${ids.length} รายการ');
                  },
                ),
              ],
            )
          : NxAppHeader(
        title: widget.title,
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            icon: const Icon(NxI.arrowCounterClockwise),
            onPressed: () => _load(reset: true),
          ),
          if (twoPane) NxAddButton(onPressed: _openCreate),
        ],
      ),
      floatingActionButton: NxCreateFab(onPressed: _openCreate),
      body: NxSplitView(
        list: list,
        detail: _creating || _selected != null ? _detail() : null,
      ),
    );
  }

  Widget _body(ThemeData theme, {required bool twoPane, required NxBreakpoint bp}) {
    if (_loading && _items.isEmpty) return const NxSkeletonList();
    if (_error != null && _items.isEmpty) {
      return NxErrorRetry(error: _error!, onRetry: () => _load(reset: true));
    }
    final items = _visible;
    if (items.isEmpty) {
      return RefreshIndicator(
        color: theme.colorScheme.primary,
        onRefresh: () => _load(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 320,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        NxI.tray,
                        size: 56,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text('ยังไม่มี${widget.title}', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Text(
                        twoPane ? 'กดปุ่มสร้างด้านบนขวาเพื่อเพิ่มรายการแรก' : 'กดปุ่มสร้างมุมล่างเพื่อเพิ่มรายการแรก',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: theme.colorScheme.primary,
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: bp.scrollPadding(context, hasFab: !twoPane),
      itemCount: items.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: NxBone(height: 52, radius: 14),
          );
        }
        final row = items[i];
        final id = row['id']?.toString() ?? '';
        final picked = _picked.contains(id);
        final phone = ['mobile_1st', 'mobile', 'phone', 'contact_mobile']
            .map((k) => row[k]?.toString().trim() ?? '')
            .firstWhere((v) => v.isNotEmpty && v != 'null', orElse: () => '');
        final tile = NxEntityRow.fromRow(
          row,
          module: widget.module,
          onLongPress: () => _togglePick(row),
          onTap: () {
            if (_picked.isNotEmpty) {
              _togglePick(row);
              return;
            }
            if (twoPane) {
              setState(() {
                _creating = false;
                _selected = row;
              });
              return;
            }
            nxPush<void>(
              context,
              EntityDetailScreen(module: widget.module, row: row),
              root: true,
            ).then((_) => _load(reset: true));
          },
        );
        final decorated = picked
            ? DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.colorScheme.primary, width: 2),
                ),
                child: tile,
              )
            : tile;
        if (_picked.isNotEmpty || id.isEmpty) return decorated;
        // Swipe left = delete (undo 5 s), swipe right = call.
        return Dismissible(
          key: ValueKey('row-${widget.module}-$id'),
          direction: phone.isEmpty ? DismissDirection.endToStart : DismissDirection.horizontal,
          background: _swipeBg(theme.colorScheme.primary, NxI.phoneCall, 'โทร', Alignment.centerLeft),
          secondaryBackground: _swipeBg(theme.colorScheme.error, NxI.trash, 'ลบ', Alignment.centerRight),
          confirmDismiss: (dir) async {
            if (dir == DismissDirection.startToEnd) {
              launchUrl(Uri(scheme: 'tel', path: phone));
              return false;
            }
            HapticFeedback.mediumImpact();
            return true;
          },
          onDismissed: (_) => _deleteIds([id], entityTitle(row, module: widget.module)),
          child: decorated,
        );
      },
    ),
    );
  }

  Widget _swipeBg(Color color, IconData icon, String label, Alignment align) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      alignment: align,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

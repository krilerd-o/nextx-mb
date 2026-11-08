import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/error_reporting.dart';
import '../core/i18n.dart';
import 'app_bottom_sheet.dart';
import 'nx_chrome.dart';
import 'nx_icons.dart';

/// One choice inside a filter group.
class NxFilterOption {
  const NxFilterOption(this.value, this.label);
  final String value;
  final String label;
}

/// A filter section (สถานะ, ประเภท, …). [multi] = several values may be on.
class NxFilterGroup {
  const NxFilterGroup({
    required this.key,
    required this.label,
    required this.options,
    this.multi = true,
  });
  final String key;
  final String label;
  final List<NxFilterOption> options;
  final bool multi;
}

/// A sort choice. [key] is opaque to the toolbar (e.g. `createdtime:desc`).
class NxSortOption {
  const NxSortOption(this.key, this.label);
  final String key;
  final String label;
}

/// Search text + active filters + sort — what a list screen queries with.
@immutable
class NxListQuery {
  const NxListQuery({this.q = '', this.filters = const {}, this.sort});

  final String q;
  final Map<String, Set<String>> filters;
  final String? sort;

  bool has(String group, String value) =>
      filters[group]?.contains(value) ?? false;
  Set<String> values(String group) => filters[group] ?? const {};
  String? single(String group) {
    final v = filters[group];
    return v == null || v.isEmpty ? null : v.first;
  }

  int get activeFilterCount => filters.values.fold(0, (n, s) => n + s.length);
  bool get isEmpty => q.isEmpty && activeFilterCount == 0;

  NxListQuery copyWith({
    String? q,
    Map<String, Set<String>>? filters,
    String? sort,
    bool clearSort = false,
  }) => NxListQuery(
    q: q ?? this.q,
    filters: filters ?? this.filters,
    sort: clearSort ? null : (sort ?? this.sort),
  );

  NxListQuery toggle(NxFilterGroup g, String value) {
    final next = {
      for (final e in filters.entries) e.key: {...e.value},
    };
    final set = next.putIfAbsent(g.key, () => <String>{});
    if (set.contains(value)) {
      set.remove(value);
    } else {
      if (!g.multi) set.clear();
      set.add(value);
    }
    if (set.isEmpty) next.remove(g.key);
    return copyWith(filters: next);
  }

  Map<String, dynamic> toJson() => {
    'filters': {for (final e in filters.entries) e.key: e.value.toList()},
    if (sort != null) 'sort': sort,
  };

  factory NxListQuery.fromJson(Map<String, dynamic> j) {
    final f = <String, Set<String>>{};
    final raw = j['filters'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is List && v.isNotEmpty)
          f[k.toString()] = {for (final x in v) x.toString()};
      });
    }
    return NxListQuery(filters: f, sort: j['sort']?.toString());
  }

  @override
  bool operator ==(Object other) =>
      other is NxListQuery &&
      other.q == q &&
      other.sort == sort &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => Object.hash(q, sort, jsonEncode(toJson()));
}

/// A named filter set the user saved ("มุมมองโปรด").
class NxSavedView {
  const NxSavedView(this.name, this.query);
  final String name;
  final NxListQuery query;
}

/// Per-menu memory: last filters/sort, recent searches and saved views.
class NxListPrefs {
  NxListPrefs(this.key);

  /// e.g. `crm_lead_<scope>` — include the user scope so accounts don't mix.
  final String key;

  String get _q => 'nx_list_q_$key';
  String get _r => 'nx_list_recent_$key';
  String get _v => 'nx_list_views_$key';

  Future<NxListQuery?> loadQuery() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_q);
      if (raw == null) return null;
      return NxListQuery.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e, s) {
      ErrorReporting.report(e, s);
      return null;
    }
  }

  Future<void> saveQuery(NxListQuery q) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _q,
        jsonEncode(q.toJson()),
      );
    } catch (e, s) {
      ErrorReporting.report(e, s);
    }
  }

  Future<List<String>> recents() async {
    try {
      return (await SharedPreferences.getInstance()).getStringList(_r) ??
          const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> addRecent(String q) async {
    final t = q.trim();
    if (t.isEmpty) return;
    final list = [
      t,
      ...(await recents()).where((e) => e != t),
    ].take(8).toList();
    try {
      await (await SharedPreferences.getInstance()).setStringList(_r, list);
    } catch (_) {}
  }

  Future<void> clearRecents() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_r);
    } catch (_) {}
  }

  Future<List<NxSavedView>> views() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_v);
      if (raw == null) return const [];
      return [
        for (final e in (jsonDecode(raw) as List))
          if (e is Map)
            NxSavedView(
              e['name'].toString(),
              NxListQuery.fromJson(Map<String, dynamic>.from(e)),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveViews(List<NxSavedView> views) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _v,
        jsonEncode([
          for (final v in views) {'name': v.name, ...v.query.toJson()},
        ]),
      );
    } catch (_) {}
  }
}

/// Search box + filter / sort chips + result count, shared by every list.
///
/// The screen owns the [NxListQuery] and reloads (server or local) in
/// [onChanged]. Quick filters from the first [quickGroups] show as chips;
/// the rest live in the filter sheet.
class NxListToolbar extends StatefulWidget {
  const NxListToolbar({
    super.key,
    required this.query,
    required this.onChanged,
    this.prefs,
    this.groups = const [],
    this.sorts = const [],
    this.searchHint = 'ค้นหา',
    this.showSearch = true,
    this.liveSearch = false,
    this.resultCount,
    this.quickGroup,
    this.leading = const [],
    this.allowSavedViews = true,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 8),
    this.collapsible = true,
    this.extraActions = const [],
  });

  /// Fold away while the page reads down (inside [NxScrollScaffold]); search /
  /// filter then live as header icons.
  final bool collapsible;

  /// More header icons while folded (e.g. the board's view switcher), shown
  /// before search / filter.
  final List<NxChromeAction> extraActions;

  /// Chips placed first in the chip row (e.g. the Custom View picker).
  final List<Widget> leading;

  /// Local "saved views" in the filter sheet — off where the server has
  /// real Custom Views instead.
  final bool allowSavedViews;

  final NxListQuery query;
  final ValueChanged<NxListQuery> onChanged;
  final NxListPrefs? prefs;
  final List<NxFilterGroup> groups;
  final List<NxSortOption> sorts;
  final String searchHint;
  final bool showSearch;

  /// Filter as you type (local lists) instead of on submit (server search).
  final bool liveSearch;
  final int? resultCount;

  /// Key of a group whose options are shown inline as chips.
  final String? quickGroup;
  final EdgeInsets padding;

  @override
  State<NxListToolbar> createState() => _NxListToolbarState();
}

class _NxListToolbarState extends State<NxListToolbar> {
  late final TextEditingController _c = TextEditingController(
    text: widget.query.q,
  );
  final _focus = FocusNode();
  List<String> _recents = const [];
  bool _showRecents = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() async {
      if (_focus.hasFocus && widget.prefs != null) {
        final r = await widget.prefs!.recents();
        if (mounted) setState(() => _recents = r);
      }
      if (mounted)
        setState(() => _showRecents = _focus.hasFocus && _c.text.isEmpty);
    });
  }

  @override
  void didUpdateWidget(covariant NxListToolbar old) {
    super.didUpdateWidget(old);
    if (widget.query.q != _c.text && !_focus.hasFocus) _c.text = widget.query.q;
  }

  NxChrome? _chrome;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = NxChrome.maybeRead(context);
    if (c != _chrome) {
      _chrome?.removeActions(this);
      _chrome = c;
    }
  }

  @override
  void dispose() {
    _chrome?.removeActions(this);
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Header icons left behind while folded: search, filter (with badge).
  void _registerChrome({required int filterBadge, required bool hasFilters}) {
    final chrome = _chrome;
    if (chrome == null) return;
    if (!widget.collapsible) {
      chrome.removeActions(this);
      return;
    }
    chrome.setActions(this, [
      ...widget.extraActions,
      if (widget.showSearch)
        NxChromeAction(
          id: 'search',
          icon: NxI.magnifyingGlass,
          tooltip: 'ค้นหา',
          badge: widget.query.q.isEmpty ? 0 : 1,
          onTap: () {
            chrome.expand();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _focus.requestFocus();
            });
          },
        ),
      if (hasFilters)
        NxChromeAction(
          id: 'filter',
          icon: NxI.funnel,
          tooltip: 'ตัวกรอง',
          badge: filterBadge,
          onTap: () {
            HapticFeedback.selectionClick();
            _openFilters();
          },
        ),
    ]);
  }

  void _submit(String v) {
    final t = v.trim();
    widget.prefs?.addRecent(t);
    _focus.unfocus();
    setState(() => _showRecents = false);
    widget.onChanged(widget.query.copyWith(q: t));
  }

  NxFilterGroup? get _quick => widget.quickGroup == null
      ? null
      : widget.groups.where((g) => g.key == widget.quickGroup).firstOrNull;

  String? get _sortLabel {
    final s = widget.query.sort;
    if (s == null || widget.sorts.isEmpty) return null;
    return widget.sorts.where((o) => o.key == s).firstOrNull?.label;
  }

  Future<void> _openFilters() async {
    final next = await showNxSnapSheet<NxListQuery>(
      context: context,
      title: 'ตัวกรอง',
      snaps: const [0.6, 0.92],
      builder: (ctx, controller) => _FilterSheet(
        query: widget.query,
        groups: widget.groups,
        sorts: widget.sorts,
        prefs: widget.allowSavedViews ? widget.prefs : null,
        controller: controller,
      ),
    );
    if (next != null) widget.onChanged(next);
  }

  Future<void> _openSort() async {
    final cs = Theme.of(context).colorScheme;
    final picked = await showAppBottomSheet<String>(
      context: context,
      title: 'เรียงตาม',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in widget.sorts)
            ListTile(
              title: Text(tr(o.label)),
              trailing: (widget.query.sort ?? widget.sorts.first.key) == o.key
                  ? Icon(NxI.check, color: cs.primary)
                  : null,
              onTap: () => Navigator.pop(context, o.key),
            ),
        ],
      ),
    );
    if (picked != null) widget.onChanged(widget.query.copyWith(sort: picked));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final q = widget.query;
    final quick = _quick;
    final sheetGroups = widget.groups
        .where((g) => g.key != widget.quickGroup)
        .toList();
    final sheetCount = [
      for (final g in sheetGroups) q.values(g.key).length,
    ].fold(0, (a, b) => a + b);

    Widget chip({
      required String label,
      required bool on,
      required VoidCallback onTap,
      IconData? icon,
      int badge = 0,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          avatar: icon == null
              ? null
              : Icon(
                  icon,
                  size: 16,
                  color: on ? cs.onPrimary : cs.onSurfaceVariant,
                ),
          label: Text(badge > 0 ? '${tr(label)} · $badge' : tr(label)),
          selected: on,
          showCheckmark: false,
          onSelected: (_) {
            HapticFeedback.selectionClick();
            onTap();
          },
          labelStyle: TextStyle(
            color: on ? cs.onPrimary : cs.onSurface,
            fontWeight: FontWeight.w500,
          ),
          selectedColor: cs.primary,
          side: BorderSide(
            color: on ? cs.primary : cs.outlineVariant.withValues(alpha: 0.7),
          ),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    final hasChips =
        quick != null || sheetGroups.isNotEmpty || widget.sorts.isNotEmpty || widget.leading.isNotEmpty;
    final sortOn = q.sort != null && widget.sorts.isNotEmpty && q.sort != widget.sorts.first.key;
    _registerChrome(
      hasFilters: widget.groups.isNotEmpty || widget.sorts.isNotEmpty,
      filterBadge: q.activeFilterCount + (sortOn ? 1 : 0),
    );
    return NxChromeCollapse(
      // Keep it open while the user is typing in it.
      enabled: widget.collapsible && !_focus.hasFocus,
      child: _body(context, q, quick, sheetGroups, sheetCount, chip, hasChips),
    );
  }

  Widget _body(
    BuildContext context,
    NxListQuery q,
    NxFilterGroup? quick,
    List<NxFilterGroup> sheetGroups,
    int sheetCount,
    Widget Function({required String label, required bool on, required VoidCallback onTap, IconData? icon, int badge}) chip,
    bool hasChips,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: widget.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showSearch)
            TextField(
              controller: _c,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onSubmitted: _submit,
              onChanged: (v) {
                setState(() => _showRecents = _focus.hasFocus && v.isEmpty);
                if (widget.liveSearch)
                  widget.onChanged(q.copyWith(q: v.trim()));
              },
              decoration: InputDecoration(
                hintText: tr(widget.searchHint),
                prefixIcon: const Icon(NxI.magnifyingGlass, size: 20),
                isDense: true,
                suffixIcon: _c.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: tr('ล้าง'),
                        icon: const Icon(NxI.x, size: 18),
                        onPressed: () {
                          _c.clear();
                          setState(() {});
                          widget.onChanged(q.copyWith(q: ''));
                        },
                      ),
              ),
            ),
          if (hasChips || _recents.isNotEmpty) ...[
            const SizedBox(height: 8),
            // While the empty search box is focused the chip row shows recent
            // searches instead (same height, so floating headers don't jump).
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _showRecents && _recents.isNotEmpty
                  ? Row(
                      children: [
                        Icon(
                          NxI.clockCounterClockwise,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        for (final r in _recents)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text(r),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                _c.text = r;
                                _submit(r);
                              },
                            ),
                          ),
                        TextButton(
                          onPressed: () async {
                            await widget.prefs?.clearRecents();
                            if (mounted) setState(() => _recents = const []);
                          },
                          child: Text(tr('ล้างประวัติ')),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        ...widget.leading,
                        if (sheetGroups.isNotEmpty)
                          chip(
                            label: 'ตัวกรอง',
                            icon: NxI.funnel,
                            on: sheetCount > 0,
                            badge: sheetCount,
                            onTap: _openFilters,
                          ),
                        if (widget.sorts.isNotEmpty)
                          chip(
                            label: _sortLabel ?? 'เรียง',
                            icon: NxI.sortAscending,
                            on:
                                q.sort != null &&
                                q.sort != widget.sorts.first.key,
                            onTap: _openSort,
                          ),
                        if (quick != null)
                          for (final o in quick.options)
                            chip(
                              label: o.label,
                              on: q.has(quick.key, o.value),
                              onTap: () =>
                                  widget.onChanged(q.toggle(quick, o.value)),
                            ),
                      ],
                    ),
            ),
          ],
          if (!q.isEmpty || widget.resultCount != null)
            SizedBox(
              height: 32,
              child: Row(
                children: [
                  if (widget.resultCount != null)
                    Text(
                      tr('${widget.resultCount} รายการ'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  const Spacer(),
                  if (!q.isEmpty)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () {
                        _c.clear();
                        widget.onChanged(NxListQuery(sort: q.sort));
                      },
                      icon: const Icon(NxI.x, size: 16),
                      label: Text(tr('ล้างตัวกรอง')),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.query, required this.groups, this.prefs, this.controller, this.sorts = const []});
  final NxListQuery query;
  final List<NxFilterGroup> groups;

  /// Sort choices on top (the folded header has one funnel for both).
  final List<NxSortOption> sorts;
  final NxListPrefs? prefs;
  final ScrollController? controller;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late NxListQuery _q = widget.query;
  List<NxSavedView> _views = const [];
  String _find = '';

  /// Groups with many options start folded to their first few choices.
  final Set<String> _expanded = {};
  static const _foldAt = 8;

  @override
  void initState() {
    super.initState();
    widget.prefs?.views().then((v) {
      if (mounted) setState(() => _views = v);
    });
  }

  Future<void> _saveView() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('บันทึกมุมมอง')),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: InputDecoration(labelText: tr('ชื่อมุมมอง')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('บันทึก'))),
        ],
      ),
    );
    final n = name.text.trim();
    name.dispose();
    if (ok != true || n.isEmpty || widget.prefs == null) return;
    final next = [..._views.where((v) => v.name != n), NxSavedView(n, _q.copyWith(q: ''))];
    await widget.prefs!.saveViews(next);
    if (mounted) setState(() => _views = next);
  }

  Future<void> _deleteView(NxSavedView v) async {
    final next = _views.where((e) => e.name != v.name).toList();
    await widget.prefs?.saveViews(next);
    if (mounted) setState(() => _views = next);
  }

  bool _groupMatches(NxFilterGroup g) {
    if (_find.isEmpty) return true;
    final f = _find.toLowerCase();
    return tr(g.label).toLowerCase().contains(f) ||
        g.label.toLowerCase().contains(f) ||
        g.options.any((o) => tr(o.label).toLowerCase().contains(f));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final groups = widget.groups.where(_groupMatches).toList();
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: widget.controller,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            children: [
              if (widget.groups.length > 3)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    onChanged: (v) => setState(() => _find = v.trim()),
                    decoration: InputDecoration(
                      hintText: tr('ค้นหาฟิลด์…'),
                      prefixIcon: const Icon(NxI.magnifyingGlass, size: 18),
                      isDense: true,
                    ),
                  ),
                ),
              if (_views.isNotEmpty) ...[
                Text(tr('มุมมองที่บันทึกไว้'), style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final v in _views)
                      InputChip(
        deleteIcon: const Icon(NxI.x, size: 16),
                        avatar: const Icon(NxI.star, size: 16),
                        label: Text(v.name),
                        onPressed: () => Navigator.pop(context, v.query.copyWith(q: widget.query.q)),
                        onDeleted: () => _deleteView(v),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (widget.sorts.isNotEmpty && _find.isEmpty) ...[
                Text(tr('เรียงตาม'), style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in widget.sorts)
                      ChoiceChip(
                        label: Text(tr(o.label)),
                        selected: (_q.sort ?? widget.sorts.first.key) == o.key,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setState(() => _q = _q.copyWith(sort: o.key));
                        },
                        selectedColor: cs.primaryContainer,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              for (final g in groups) ...[
                Row(
                  children: [
                    Expanded(child: Text(tr(g.label), style: theme.textTheme.titleSmall)),
                    if (_q.values(g.key).isNotEmpty)
                      Text(
                        '${_q.values(g.key).length}',
                        style: theme.textTheme.labelMedium?.copyWith(color: cs.primary),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                () {
                  final f = _find.toLowerCase();
                  var opts = g.options;
                  if (f.isNotEmpty && !tr(g.label).toLowerCase().contains(f)) {
                    opts = opts.where((o) => tr(o.label).toLowerCase().contains(f)).toList();
                  }
                  final fold = opts.length > _foldAt && !_expanded.contains(g.key) && _find.isEmpty;
                  // Keep selected choices visible even when folded.
                  final shown = fold
                      ? [...opts.take(_foldAt), ...opts.skip(_foldAt).where((o) => _q.has(g.key, o.value))]
                      : opts;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final o in shown)
                        FilterChip(
                          label: Text(tr(o.label)),
                          selected: _q.has(g.key, o.value),
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            setState(() => _q = _q.toggle(g, o.value));
                          },
                          selectedColor: cs.primaryContainer,
                        ),
                      if (fold)
                        ActionChip(
                          label: Text(tr('ดูทั้งหมด (${opts.length})')),
                          onPressed: () => setState(() => _expanded.add(g.key)),
                        ),
                    ],
                  );
                }(),
                const SizedBox(height: 18),
              ],
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.paddingOf(context).bottom),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5), width: 0.5)),
          ),
          child: Row(
            children: [
              if (widget.prefs != null && _q.activeFilterCount > 0)
                IconButton(
                  tooltip: tr('บันทึกมุมมอง'),
                  onPressed: _saveView,
                  icon: const Icon(NxI.star),
                ),
              TextButton(
                onPressed: () => setState(() => _q = NxListQuery(q: _q.q, sort: _q.sort)),
                child: Text(tr('ล้าง')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _q),
                  child: Text(_q.activeFilterCount > 0 ? tr('ใช้ตัวกรอง (${_q.activeFilterCount})') : tr('ใช้ตัวกรอง')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Applies a [NxListQuery] to an in-memory list (menus whose API has no
/// server-side filters): free-text search, per-group predicates, sort.
List<T> nxApplyLocalQuery<T>(
  List<T> items,
  NxListQuery q, {
  required String Function(T item) text,
  Map<String, bool Function(T item, Set<String> values)> filters = const {},
  Map<String, int Function(T a, T b)> sorts = const {},
}) {
  final needle = q.q.trim().toLowerCase();
  final out = items.where((it) {
    if (needle.isNotEmpty && !text(it).toLowerCase().contains(needle)) return false;
    for (final e in q.filters.entries) {
      final f = filters[e.key];
      if (f != null && e.value.isNotEmpty && !f(it, e.value)) return false;
    }
    return true;
  }).toList();
  final s = q.sort == null ? null : sorts[q.sort];
  if (s != null) out.sort(s);
  return out;
}

/// The toolbar's filter + sort sheet on its own (screens whose filters live
/// behind a header icon, e.g. the calendar). Returns the new query or null.
Future<NxListQuery?> showNxFilterSheet(
  BuildContext context, {
  required NxListQuery query,
  required List<NxFilterGroup> groups,
  List<NxSortOption> sorts = const [],
}) =>
    showNxSnapSheet<NxListQuery>(
      context: context,
      title: 'ตัวกรอง',
      snaps: const [0.6, 0.92],
      builder: (ctx, controller) => _FilterSheet(query: query, groups: groups, sorts: sorts, controller: controller),
    );

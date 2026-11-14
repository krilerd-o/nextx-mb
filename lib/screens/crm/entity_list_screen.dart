import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/nx_swr_cache.dart';
import '../../services/api_client.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_create_fab.dart';
import '../../widgets/nx_entity_row.dart';
import '../../widgets/nx_list_toolbar.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../core/error_reporting.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_split_view.dart';
import '../../widgets/nx_confirm_sheet.dart';
import 'custom_views.dart';
import 'card_layout_editor.dart';
import '../../core/card_layout.dart';
import '../../widgets/nx_entity_card.dart';
import 'entity_create_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'entity_detail_parts.dart';
import 'entity_detail_screen.dart';
import 'entity_record_actions.dart';
import 'entity_row_action_sheet.dart';
import 'lead_convert_sheet.dart';
import 'card_scan/card_scan_models.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/entity_display.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_measure_size.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_refresh.dart';
import '../../widgets/nx_tip_banner.dart';

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

/// Last first page per module + query (this app session): reopening a list
/// shows it instantly, then refreshes in the background.
/// First page of a list (app-wide [NxSwrCache]; dropped on Space switch / writes).
typedef _FirstPage = ({List<Map<String, dynamic>> items, int? total});

class _EntityListScreenState extends State<EntityListScreen> {
  final _searchController = TextEditingController();
  final _scroll = ScrollController();
  final _items = <Map<String, dynamic>>[];

  /// Ids picked in multi-select mode (long-press a row).
  final Set<String> _picked = {};

  List<Map<String, dynamic>> get _visible => [
    for (final r in _items)
      if (!PendingEntityDeletes.instance.isPending(
        widget.module,
        r['id']?.toString() ?? '',
      ))
        r,
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

  /// Long-press a row: haptic + icon sheet (status, comment, edit, duplicate,
  /// delete, multi-select); each command opens its own window.
  Future<void> _rowActions(Map<String, dynamic> row) async {
    if (_picked.isNotEmpty) {
      _togglePick(row);
      return;
    }
    _hintSeen();
    final picklists = _cardCtx?.picklists ?? const <String, List<Map<String, dynamic>>>{};
    final key = _statusKey ?? EntityRecordActions.statusKey(widget.module, picklists, row);
    final raw = key == null ? null : row[key]?.toString();
    final cur = statusCurrent(widget.module, raw);
    final opt = EntityRecordActions.statusOptions(widget.module, key, picklists, current: raw)
        .where((o) => o.value == cur || o.label == raw)
        .firstOrNull;
    final act = await showEntityRowActionSheet(
      context,
      module: widget.module,
      moduleLabel: _title,
      row: row,
      statusKey: key != null && (picklists[key] ?? const []).isNotEmpty ? key : null,
      statusLabel: opt?.label ?? raw,
      statusColor: opt?.color,
    );
    if (act == null || !mounted) return;
    final id = row['id']?.toString() ?? '';
    switch (act) {
      case EntityRowAction.convert:
        final r = await showLeadConvertSheet(context, leadId: id);
        if (r != null && mounted) _load(reset: true);
      case EntityRowAction.status:
        await EntityRecordActions.changeStatus(
          context,
          module: widget.module,
          row: row,
          picklists: picklists.isEmpty ? null : picklists,
          onChanged: (k, v) {
            if (!mounted) return;
            setState(() {
              final i = _items.indexWhere((r) => r['id']?.toString() == id);
              if (i >= 0) _items[i] = {..._items[i], k: v};
              if (_selected?['id']?.toString() == id) _selected = {..._selected!, k: v};
            });
          },
        );
      case EntityRowAction.comment:
        await EntityRecordActions.openComments(context, module: widget.module, row: row);
      case EntityRowAction.edit:
        if (await EntityRecordActions.edit(context, module: widget.module, row: row, root: true) && mounted) {
          _load(reset: true);
        }
      case EntityRowAction.duplicate:
        if (await EntityRecordActions.duplicate(context, module: widget.module, row: row, root: true) && mounted) {
          _load(reset: true);
        }
      case EntityRowAction.delete:
        final ok = await EntityRecordActions.delete(
          context,
          module: widget.module,
          row: row,
          onCommitted: () {
            if (mounted) _load(reset: true);
          },
        );
        if (ok && mounted && _selected?['id']?.toString() == id) setState(() => _selected = null);
      case EntityRowAction.select:
        _togglePick(row);
    }
  }

  /// One-time tip under the toolbar: "long-press a row for commands".
  bool _showHint = false;
  static const _hintKey = 'nx_crm_row_actions_hint_v1';

  Future<void> _loadHint() async {
    try {
      final seen = (await SharedPreferences.getInstance()).getBool(_hintKey) ?? false;
      if (!seen && mounted) setState(() => _showHint = true);
    } catch (_) {}
  }

  void _hintSeen() {
    if (_showHint) setState(() => _showHint = false);
    SharedPreferences.getInstance().then((p) => p.setBool(_hintKey, true)).catchError((_) => false);
  }

  Widget _hintBanner(ThemeData theme) => NxTipBanner(
        key: const ValueKey('crm-row-hint'),
        icon: NxI.handPointing,
        text: tr('กดค้างที่รายการเพื่อดูคำสั่ง (ปรับสถานะ, คอมเมนต์, แก้ไข, ทำซ้ำ, ลบ)'),
        onClose: _hintSeen,
      );

  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  Object? _error;
  int _page = 1;
  bool _hasMore = true;
  NxListQuery _query = const NxListQuery();
  late final NxListPrefs _prefs = NxListPrefs('crm_${widget.module}_${context.read<AppConfig>().businessScope}');
  bool _showMine = true;
  int? _total;

  /// Quick filters built like the web panel: every picklist field, owner
  /// fields (users), a period (date field × preset) and case tags.
  String? _statusKey;
  List<NxFilterGroup> _pickGroups = const [];
  List<NxFilterGroup> _ownerGroups = const [];
  List<NxFilterOption> _dateFields = const [];
  List<NxFilterOption> _periodPresets = const [];
  List<NxFilterOption> _tagOptions = const [];
  String? _nameCol;
  String? _amountCol;

  /// The user's card layout for this menu (shared default until customised).
  CardLayout? _layout;
  CardLayout? _defaultLayout;
  CardFieldContext? _cardCtx;

  Future<void> _openCardEditor() async {
    final ctx = _cardCtx;
    final def = _defaultLayout;
    if (ctx == null || def == null) return;
    final scope = context.read<AppConfig>().businessScope;
    final result = await nxPush<CardLayout>(
      context,
      CardLayoutEditorScreen(
        module: widget.module,
        initial: _layout ?? def,
        defaults: def,
        fields: ctx,
        sample: _visible.isNotEmpty ? _visible.first : null,
      ),
      root: true,
    );
    if (result == null || !mounted) return;
    setState(() => _layout = result);
    await CardLayoutStore.save(widget.module, scope, result);
  }

  /// Custom Views (มุมมอง CV) from the server, and the one applied.
  CustomViewList? _cvs;
  String? _cvId;
  /// Filters, chosen view and card layout belong to the current business.
  String get _cvPrefKey => 'nx_cv_${widget.module}_${context.read<AppConfig>().businessScope}';

  static const _statusCandidates = [
    'status', 'leadstatus', 'lead_status', 'deal_stage', 'sales_stage', 'case_status', 'quotation_status',
    'job_status', 'inspection_status', 'account_status', 'contact_status', 'activity_status', 'contract_status',
  ];
  static const _nameCandidates = [
    'lead_name', 'deal_name', 'account_name', 'contact_firstname', 'customer_name', 'case_name', 'subject',
    'product_name', 'service_name', 'activity_name', 'title', 'name',
  ];
  static const _amountCandidates = ['amount', 'grand_total', 'total_amount', 'expected_revenue', 'price'];

  List<NxFilterGroup> get _groups => [
        if (_showMine && context.read<AppConfig>().session.userId != null)
          const NxFilterGroup(key: 'scope', label: 'ขอบเขต', multi: false, options: [NxFilterOption('mine', 'ของฉัน')]),
        ..._pickGroups,
        ..._ownerGroups,
        if (_dateFields.isNotEmpty && _periodPresets.isNotEmpty) ...[
          NxFilterGroup(key: 'pp', label: 'ช่วงเวลา', multi: false, options: _periodPresets),
          NxFilterGroup(key: 'pf', label: 'ใช้ช่วงเวลากับฟิลด์', multi: false, options: _dateFields),
        ],
        if (_tagOptions.isNotEmpty) NxFilterGroup(key: 'tag', label: 'แท็ก', options: _tagOptions),
      ];

  List<NxSortOption> get _sorts => [
        const NxSortOption('modifiedtime:desc', 'แก้ไขล่าสุด'),
        const NxSortOption('createdtime:desc', 'สร้างล่าสุด'),
        const NxSortOption('createdtime:asc', 'เก่าสุด'),
        if (_nameCol != null) NxSortOption('$_nameCol:asc', 'ชื่อ ก–ฮ'),
        if (_amountCol != null) NxSortOption('$_amountCol:desc', 'มูลค่าสูงสุด'),
      ];

  static bool _isPicklist(Map f, Map<String, List<Map<String, dynamic>>> picklists) {
    final t = '${f['type'] ?? f['uitype'] ?? ''}';
    final name = f['name']?.toString() ?? '';
    return (picklists[name] ?? const []).isNotEmpty && (t == 'Enum' || t == 'Picklist' || t == '15' || t == '16' || t == 'MultiPicklist' || t == '33');
  }

  static bool _isOwner(Map f) {
    final t = '${f['type'] ?? f['uitype'] ?? ''}';
    return f['name'] == 'smownerid' || f['name'] == 'assign_to' || t == 'PicklistUser' || t == '53';
  }

  Future<void> _loadSchema({bool beforeList = false}) async {
    final api = context.read<AppConfig>().apiClient;
    try {
      final schema = await api.getFieldSchema(widget.module);
      final names = {for (final f in schema.fields) f['name']?.toString() ?? ''};
      String? status;
      for (final k in ['${widget.module}_status', '${widget.module}_stage', ..._statusCandidates]) {
        if ((schema.picklists[k] ?? const []).isNotEmpty) {
          status = k;
          break;
        }
      }
      final picks = <NxFilterGroup>[];
      for (final f in schema.fields) {
        if (f['access'] == 'hidden' || '${f['presence'] ?? 1}' == '0' || !_isPicklist(f, schema.picklists)) continue;
        final name = f['name'].toString();
        picks.add(NxFilterGroup(
          key: 'pl:$name',
          label: nxLabel(f, fallback: name),
          options: [
            for (final o in schema.picklists[name]!)
              NxFilterOption((o['value'] ?? o['value_th'] ?? '').toString(), nxLabel(o)),
          ],
        ));
      }
      // Status first: it is also the inline quick-chip row.
      picks.sort((a, b) => (a.key == 'pl:$status' ? 0 : 1).compareTo(b.key == 'pl:$status' ? 0 : 1));
      final c0 = context.read<AppConfig>();
      final saved = await CardLayoutStore.load(widget.module, c0.businessScope, fallbackScope: c0.prefsScope);
      if (!mounted) return;
      final ctx0 = CardFieldContext(fields: schema.fields, picklists: schema.picklists, module: widget.module);
      final def = CardLayout.defaults(widget.module, schema.fields, statusKey: status).sanitized(ctx0);
      setState(() {
        _defaultLayout = def;
        _layout = (saved ?? def).sanitized(ctx0);
        _cardCtx = ctx0;
        _statusKey = status;
        _pickGroups = picks;
        _nameCol = _nameCandidates.where(names.contains).firstOrNull;
        _amountCol = _amountCandidates.where(names.contains).firstOrNull;
      });
      _saveCols();
      // Owners / periods need the CV meta (users, date fields, presets) — not
      // needed for the first page, so it loads behind the list.
      _loadMeta(schema);
    } catch (e, s) {
      ErrorReporting.report(e, s);
    }
    if (widget.module == 'case') _loadCaseTags();
  }

  Future<void> _loadCaseTags() async {
    final api = context.read<AppConfig>().apiClient;
      try {
        final tags = await api.getTags(module: 'case');
        if (mounted) {
          setState(() => _tagOptions = [
                for (final t in tags)
                  if (t['id'] != null) NxFilterOption(t['id'].toString(), t['name']?.toString() ?? '#${t['id']}'),
              ]);
        }
      } catch (e, s) {
        ErrorReporting.report(e, s);
      }
  }

  Future<void> _loadMeta(ModuleFieldSchema schema) async {
    final api = context.read<AppConfig>().apiClient;
    try {
      final meta = await api.getCustomViewMeta(widget.module);
      final users = [
        for (final u in (meta['users'] as List? ?? const []))
          if (u is Map) NxFilterOption(u['id'].toString(), u['name']?.toString() ?? '${u['id']}'),
      ];
      final ownerFields = <Map>[
        {'name': 'smownerid', 'label_th': 'เจ้าของ', 'label_en': 'Owner'},
        for (final f in schema.fields)
          if (_isOwner(f) && f['name'] != 'smownerid') f,
      ];
      if (!mounted) return;
      setState(() {
        _cardCtx = CardFieldContext(
          fields: schema.fields,
          picklists: schema.picklists,
          module: widget.module,
          users: {for (final u in users) u.value: u.label},
        );
        _ownerGroups = users.isEmpty
            ? const []
            : [
                for (final f in ownerFields)
                  NxFilterGroup(key: 'ow:${f['name']}', label: nxLabel(f, fallback: '${f['name']}'), options: users),
              ];
        _dateFields = [
          for (final f in (meta['date_fields'] as List? ?? const []))
            if (f is Map) NxFilterOption(f['name'].toString(), nxLabel(f)),
        ];
        _periodPresets = [
          for (final p in (meta['period_presets'] as List? ?? const []))
            if (p is Map && p['value'] != 'custom') NxFilterOption(p['value'].toString(), nxLabel(p)),
        ];
      });
    } catch (e, s) {
      ErrorReporting.report(e, s);
    }
  }

  /// [reloadList] false: the first load waits for this instead (so the list is not
  /// fetched once without the default view and again with it).
  Future<void> _loadViews({bool reloadList = true}) async {
    try {
      final data = await context.read<AppConfig>().apiClient.getCustomViews(widget.module);
      if (!mounted) return;
      final before = _cvId;
      setState(() {
        _cvs = CustomViewList.from(data);
        if (_cvId == null || !_cvs!.views.any((v) => v.id == _cvId)) _cvId = _cvs!.defaultId;
      });
      // A default view with its own conditions changes what the list shows.
      if (before != _cvId && reloadList) _load(reset: true);
    } catch (e, s) {
      ErrorReporting.report(e, s);
    }
  }

  Future<void> _pickView() async {
    final cvs = _cvs;
    if (cvs == null) return;
    final id = await showCustomViewPicker(
      context,
      module: widget.module,
      views: cvs,
      currentId: _cvId,
      onChanged: _loadViews,
    );
    if (id == null || !mounted) return;
    setState(() => _cvId = id.isEmpty ? _cvs?.defaultId : id);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_cvId == null) {
        await prefs.remove(_cvPrefKey);
      } else {
        await prefs.setString(_cvPrefKey, _cvId!);
      }
    } catch (_) {}
    _load(reset: true);
  }

  /// `ทั้งหมด ▾` under the menu name: the current Custom View, tap to switch.
  Widget _cvTitleRow() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cv = _cvs?.views.where((v) => v.id == _cvId).firstOrNull;
    final custom = cv != null && !cv.isSystem;
    return InkWell(
      key: const ValueKey('crm-cv-row'),
      onTap: _pickView,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                cv?.displayName ?? tr('ทั้งหมด'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: custom ? cs.primary : cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(NxI.caretDown, size: 16, color: custom ? cs.primary : cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _cvChip() {
    final cs = Theme.of(context).colorScheme;
    final cv = _cvs?.views.where((v) => v.id == _cvId).firstOrNull;
    final custom = cv != null && !cv.isSystem;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(NxI.squaresFour, size: 16, color: custom ? cs.onPrimary : cs.onSurfaceVariant),
        label: Text(cv?.displayName ?? tr('มุมมอง')),
        onPressed: _cvs == null ? null : _pickView,
        backgroundColor: custom ? cs.primary : null,
        labelStyle: TextStyle(color: custom ? cs.onPrimary : cs.onSurface, fontWeight: FontWeight.w500),
        side: BorderSide(color: custom ? cs.primary : cs.outlineVariant.withValues(alpha: 0.7)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  /// Bulk status choices in the real order; a lead can't be set to
  /// "Converted" in bulk (only through the convert window).
  List<NxFilterOption> _bulkStatusOptions(NxFilterGroup group) {
    final ordered = orderStatusOptions(widget.module, [for (final o in group.options) (value: o.value, label: o.label)]);
    return [
      for (final o in ordered)
        if (!(widget.module == 'lead' && isLeadConvertedStatus(o.value)))
          if (group.options.any((g) => g.value == o.value)) NxFilterOption(o.value, o.label),
    ];
  }

  bool get _workflowStatus => const {'job', 'quotation', 'case', 'service_contract'}.contains(widget.module);

  /// Multi-select → one status for all picked records (`bulk-update`).
  Future<void> _bulkStatus() async {
    final group = _pickGroups.firstWhere((g) => g.key == 'pl:$_statusKey');
    final ids = _picked.toList();
    final cs = Theme.of(context).colorScheme;
    final value = await showAppBottomSheet<String>(
      context: context,
      title: tr('เปลี่ยนสถานะ ${ids.length} รายการ'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in _bulkStatusOptions(group))
            ListTile(
              leading: Icon(NxI.flag, color: cs.primary),
              title: Text(tr(o.label)),
              onTap: () => Navigator.pop(context, o.value),
            ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    // Confirm: the shared status (when all picked rows agree) → the new one.
    final current = {
      for (final r in _items)
        if (ids.contains(r['id']?.toString())) statusCurrent(widget.module, r[_statusKey!]?.toString()) ?? '',
    };
    final from = current.length == 1 ? current.first : null;
    String label(String? v) => group.options.where((o) => o.value == v).firstOrNull?.label ?? (v ?? '');
    final ok = await showStatusChangeConfirm(
      context,
      recordTitle: tr('${ids.length} รายการ'),
      from: from == null ? 'หลายสถานะ' : (from.isEmpty ? null : label(from)),
      fromColor: from == null || from.isEmpty ? null : EntityRecordActions.statusColor(cs, from),
      to: label(value),
      toColor: EntityRecordActions.statusColor(cs, value),
      impact: EntityRecordActions.statusImpact(widget.module, value),
      destructive: nxIsDestructiveStatus('$value ${label(value)}'),
    );
    if (ok == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await context.read<AppConfig>().apiClient.bulkUpdateEntities(widget.module, ids, {_statusKey!: value});
      HapticFeedback.lightImpact();
      if (!mounted) return;
      setState(_picked.clear);
      messenger.showSnackBar(SnackBar(
        content: Text(n >= ids.length
            ? tr('เปลี่ยนสถานะ ${ids.length} รายการแล้ว')
            : '${tr('เปลี่ยนสถานะได้ $n จาก ${ids.length} รายการ')} — ${tr('ที่เหลือไม่มีสิทธิ์หรือต้องเปลี่ยนผ่านขั้นตอนของรายการ')}'),
      ));
      _load(reset: true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  void _onQuery(NxListQuery q) {
    setState(() => _query = q);
    _prefs.saveQuery(q.copyWith(q: ''));
    _load(reset: true);
  }
  Map<String, dynamic>? _selected;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    PendingEntityDeletes.instance.addListener(_onPendingChanged);
    _scroll.addListener(_onScroll);
    _init();
    _loadHint();
  }

  /// Menu name as configured on NEXTX (aicrm_tab), e.g. "ลีด" instead of the
  /// built-in "ผู้มุ่งหวัง"; falls back to [EntityListScreen.title].
  (String, String?)? _menuName;

  String get _title {
    final m = _menuName;
    if (m == null) return widget.title;
    return L10n.isEn && m.$2 != null ? m.$2! : m.$1;
  }

  Future<void> _loadMenuName() async {
    try {
      final labels = await context.read<AppConfig>().apiClient.getModuleLabels();
      final m = labels[widget.module.toLowerCase()];
      if (m != null && mounted) setState(() => _menuName = m);
    } catch (_) {}
  }

  Future<void> _init() async {
    final saved = await _prefs.loadQuery();
    String? cv;
    try {
      cv = (await SharedPreferences.getInstance()).getString(_cvPrefKey);
    } catch (_) {}
    if (!mounted) return;
    if (saved != null) _query = saved;
    _cvId = cv;
    // Opened before (this view / search): show that first page now; views,
    // schema and page 1 refresh it underneath.
    final hit = NxSwrCache.instance.peek<_FirstPage>(_cacheKey);
    if (hit != null && _items.isEmpty) {
      setState(() {
        _items.addAll(hit.items);
        _total = hit.total;
        _loading = false;
        _refreshing = true;
      });
    }
    if (!context.read<AppConfig>().isLoggedIn) {
      _load(reset: true);
      return;
    }
    _loadMenuName();
    // Views and schema side by side. Page 1 waits for the default view (else it is fetched
    // twice) and, when this list was opened before, goes out with the columns saved then —
    // in parallel with the schema instead of after it.
    final views = _loadViews(reloadList: false);
    final schema = _loadSchema(beforeList: true);
    final hint = await _savedCols();
    if (hint != null) {
      _colsHint = hint;
      await views;
      if (mounted) _load(reset: true);
      await schema;
      // The layout changed elsewhere and needs a column the first page did not ask for.
      final now = _currentCols();
      if (mounted && now != null && !hint.split(',').toSet().containsAll(now.split(','))) _load(reset: true);
    } else {
      await Future.wait([views, schema]);
      if (mounted) _load(reset: true);
    }
  }

  /// Columns of page 1 before the schema has loaded (saved from the last visit).
  String? _colsHint;
  String get _colsPrefKey => 'nx_list_cols_${widget.module}_${context.read<AppConfig>().businessScope}';

  Future<String?> _savedCols() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_colsPrefKey);
      return v == null || v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  void _saveCols() {
    final cols = _currentCols();
    if (cols == null) return;
    final key = _colsPrefKey;
    () async {
      try {
        await (await SharedPreferences.getInstance()).setString(key, cols);
      } catch (_) {}
    }();
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
    final q = _query;
    final out = <String, String>{};
    final sort = q.sort?.split(':');
    if (sort != null && sort.length == 2) {
      out['sort'] = sort[0];
      out['order'] = sort[1];
    }
    if (q.has('scope', 'mine')) {
      if (widget.module == 'activity') {
        out['involved'] = '1';
      } else {
        final uid = context.read<AppConfig>().session.userId;
        if (uid != null && uid.isNotEmpty) out['filter[smownerid]'] = uid;
      }
    }
    for (final e in q.filters.entries) {
      if (e.value.isEmpty) continue;
      if (e.key.startsWith('pl:') || e.key.startsWith('ow:')) out['filter[${e.key.substring(3)}]'] = e.value.join(',');
    }
    final preset = q.single('pp');
    if (preset != null) {
      out['period_field'] = q.single('pf') ??
          (_dateFields.any((f) => f.value == 'createdtime') || _dateFields.isEmpty ? 'createdtime' : _dateFields.first.value);
      out['period_preset'] = preset;
    }
    final tags = q.values('tag');
    if (tags.isNotEmpty) out['filter[tag_ids]'] = tags.join(',');
    if (_cvId != null && _cvId!.isNotEmpty) out['cv_id'] = _cvId!;
    return out;
  }

  String get _cacheKey {
    final c = context.read<AppConfig>();
    return NxSwrCache.key('/api/entity/${widget.module}', query: {
      'p': c.session.packageCode,
      'cv': _cvId,
      'q': _query.q,
      'f': _query.toJson(),
    });
  }

  /// Bumped on every reset load; older responses are ignored.
  int _loadGen = 0;

  /// Columns this list actually draws (card slots, title, status, phone,
  /// owner). Sent as `cols=` so big tables return slim rows; servers without
  /// the option just return everything.
  Map<String, String> _liteParams({required bool firstPage}) {
    final out = <String, String>{
      // Only the first page needs a total (COUNT is the slow part on big tables).
      if (!firstPage) 'with_total': '0',
    };
    final cols = _currentCols() ?? _colsHint;
    if (cols != null) out['cols'] = cols;
    return out;
  }

  /// The `cols=` this list draws with its current layout; null before the schema.
  String? _currentCols() {
    final ctx = _cardCtx;
    if (ctx == null) return null;
    final cols = <String>{
      'id', 'smownerid', 'createdtime', 'modifiedtime',
      ?_statusKey,
      for (final slot in CardLayout.slots) ?_layout?.slot(slot),
      ..._nameCandidates, '${widget.module}_no', 'customer_name', 'account_name', 'contact_name',
      'firstname', 'lastname', 'lead_firstname', 'lead_lastname', 'contact_firstname', 'contact_lastname',
      'mobile_1st', 'mobile', 'phone', 'contact_mobile', 'email_1st', 'email', 'image_url',
      if (widget.module == 'activity') ...['date_start', 'date_end', 'status', 'activitytype', 'location', 'checkindate'],
    }..removeWhere((c) => c.isEmpty || (!ctx.fields.containsKey(c) && !CardFieldContext.metaLabels.containsKey(c) && c != 'id'));
    return cols.join(',');
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) _loadGen++;
    final gen = _loadGen;
    if (reset && _items.isEmpty) {
      final hit = NxSwrCache.instance.peek<_FirstPage>(_cacheKey);
      if (hit != null) {
        _items.addAll(hit.items);
        _total = hit.total;
      }
    }
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
        q: _query.q.isEmpty ? null : _query.q,
        extra: {
          ...?_extra(),
          ..._liteParams(firstPage: reset),
        },
      );
      // A newer search/filter started while this page was loading: drop it.
      if (!mounted || gen != _loadGen) return;
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(page.items);
        } else {
          _items.addAll(page.items);
        }
        _hasMore = page.hasMore && page.items.isNotEmpty;
        _total = page.total;
        if (reset) NxSwrCache.instance.put<_FirstPage>(_cacheKey, (items: List.of(page.items), total: page.total));
        _page += 1;
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (_query.has('scope', 'mine')) {
        setState(() {
          _showMine = false;
          _query = _query.toggle(_groups.first, 'mine');
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

  /// Lead / Contact / Account: "สร้างเอง" or "สแกนนามบัตร" first (like Zoho).
  Future<void> _openCreate() async {
    if (!kCardScanModules.contains(widget.module)) return _create();
    final scan = await showAppBottomSheet<bool>(
      context: context,
      title: tr('ตัวเลือก$_title ใหม่'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _createOption(
            key: const ValueKey('create-manual'),
            icon: NxI.plus,
            title: '$_title ใหม่',
            subtitle: 'สร้างด้วยตนเอง',
            onTap: () => Navigator.pop(context, false),
          ),
          const Divider(height: 1),
          _createOption(
            key: const ValueKey('create-scan'),
            icon: NxI.idCard,
            title: 'สแกนนามบัตร',
            subtitle: 'ถ่ายหรือเลือกรูปนามบัตร แล้วกรอกให้อัตโนมัติ — ตรวจสอบก่อนกดบันทึก',
            onTap: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (scan == null || !mounted) return;
    return _create(scan: scan);
  }

  Widget _createOption({required Key key, required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      key: key,
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      leading: CircleAvatar(radius: 22, backgroundColor: const Color(0xFF16A34A).withValues(alpha: 0.12), child: Icon(icon, color: const Color(0xFF16A34A))),
      title: Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(tr(subtitle), style: TextStyle(color: cs.onSurfaceVariant)),
      onTap: onTap,
    );
  }

  bool _scanOnCreate = false;

  Future<void> _create({bool scan = false}) async {
    final twoPane = NxBreakpoint.of(context).twoPane;
    if (twoPane) {
      setState(() {
        _creating = true;
        _scanOnCreate = scan;
        _selected = null;
      });
      return;
    }
    final created = await nxPush<bool>(
      context,
      EntityCreateScreen(module: widget.module, title: 'สร้าง$_title', autoScan: scan),
      root: true,
    );
    if (created == true) _load(reset: true);
  }

  Widget _detail() {
    if (_creating) {
      return EntityCreateScreen(
        key: ValueKey('create-$_scanOnCreate'),
        module: widget.module,
        title: 'สร้าง$_title',
        embedded: true,
        autoScan: _scanOnCreate,
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
      onDeleted: () => setState(() => _selected = null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final twoPane = NxBreakpoint.of(context).twoPane;
    final bp = NxBreakpoint.of(context);
    final toolbar = NxListToolbar(
      query: _query,
      prefs: _prefs,
      groups: _groups,
      sorts: _sorts,
      quickGroup: _statusKey == null ? 'scope' : 'pl:$_statusKey',
      leading: [if (_cvs != null && twoPane) _cvChip()],
      allowSavedViews: false,
      searchHint: 'ค้นหา$_title',
      resultCount: _loading ? null : (_total ?? _visible.length),
      onChanged: _onQuery,
    );
    final list = Column(
      children: [
        if (_refreshing) const LinearProgressIndicator(minHeight: 2),
        if (twoPane) toolbar,
        Expanded(
          child: _body(Theme.of(context), twoPane: twoPane, bp: bp),
        ),
      ],
    );

    final PreferredSizeWidget header = _picked.isNotEmpty
        ? AppBar(
            leading: IconButton(
              tooltip: tr('ยกเลิก'),
              icon: const Icon(NxI.x),
              onPressed: () => setState(_picked.clear),
            ),
            title: Text(tr('เลือก ${_picked.length} รายการ')),
            actions: [
              IconButton(
                tooltip: tr('เลือกทั้งหมด'),
                icon: const Icon(NxI.checkCircle),
                onPressed: () => setState(
                  () => _picked.addAll([
                    for (final r in _visible)
                      if (r['id'] != null) r['id'].toString(),
                  ]),
                ),
              ),
              // Job / quotation / case / contract statuses move only through
              // their workflow (dialogs, reasons, notifications) — not in bulk.
              if (_statusKey != null && !_workflowStatus && _pickGroups.any((g) => g.key == 'pl:$_statusKey'))
                IconButton(
                  tooltip: tr('เปลี่ยนสถานะที่เลือก'),
                  icon: const Icon(NxI.flag),
                  onPressed: _bulkStatus,
                ),
              IconButton(
                tooltip: tr('ลบที่เลือก'),
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
            title: _title,
            largeTitle: true,
            subtitleWidget: _cvs == null || twoPane ? null : _cvTitleRow(),
            menu: [
              if (_cardCtx != null)
                NxHeaderMenuItem(label: 'ปรับแต่งการ์ด', icon: NxI.squaresFour, onTap: _openCardEditor),
            ],
            actions: [
              if (twoPane) NxAddButton(onPressed: _openCreate),
            ],
          );
    if (twoPane) {
      return Scaffold(
        appBar: header,
        body: NxSplitView(
          list: list,
          detail: _creating || _selected != null ? _detail() : null,
          onClose: () => setState(() {
            _selected = null;
            _creating = false;
          }),
        ),
      );
    }
    // Phone: search + filters float on the glass header; the list scrolls under both.
    return NxScrollScaffold(
      insetBody: false,
      header: header,
      // Measured: the search box only takes room once it is opened.
      headerBottom: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: 0,
        maxHeight: 400,
        child: NxMeasureSize(
          onChange: (sz) {
            // Ignore the folded (scrolled-away) toolbar: only real content changes count.
            if (sz.height < 24) return;
            if (mounted && (sz.height - _toolbarHeight).abs() > 0.5) setState(() => _toolbarHeight = sz.height);
          },
          child: toolbar,
        ),
      ),
      headerBottomHeight: _toolbarHeight,
      floatingActionButton: NxCreateFab(
        onPressed: _openCreate,
        // Long-press: straight to the card scanner.
        onLongPress: kCardScanModules.contains(widget.module) ? () => _create(scan: true) : null,
      ),
      body: Builder(
        builder: (context) {
          _inset = NxScrollScaffold.topInset(context);
          return Column(
            children: [
              Expanded(
                child: _body(Theme.of(context), twoPane: twoPane, bp: bp),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Status chips (+ search box when open) floating under the header on phones.
  double _toolbarHeight = 96;

  /// Space the list leaves for the floating header + toolbar (phones only).
  double _top(bool twoPane) => twoPane ? 0 : _inset;

  /// Header + toolbar height, read from inside NxScrollScaffold (see build).
  double _inset = 0;

  Widget _body(
    ThemeData theme, {
    required bool twoPane,
    required NxBreakpoint bp,
  }) {
    final top = _top(twoPane);
    if (_loading && _items.isEmpty) {
      // Same gutters and tile as the list it stands for: cards when the module
      // has a card layout, else 68 px rows (avatar left).
      final p = bp.scrollPadding(context, hasFab: !twoPane);
      return Padding(
        key: const ValueKey('entity-list-skeleton'),
        padding: EdgeInsets.only(top: top, left: p.left, right: p.right),
        child: _layout != null ? const NxSkeletonEntityCards(padded: false) : const NxSkeletonRows(count: 8, padded: false),
      );
    }
    if (_error != null && _items.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: top),
        child: NxErrorRetry(error: _error!, onRetry: () => _load(reset: true)),
      );
    }
    final items = _visible;
    if (items.isEmpty) {
      return NxRefresh(
        color: theme.colorScheme.primary,
        onRefresh: () => _load(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(top: top),
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
                      Text(
                        tr('ยังไม่มี$_title'),
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tr(twoPane
                            ? 'กดปุ่มสร้างด้านบนขวาเพื่อเพิ่มรายการแรก'
                            : 'กดปุ่มสร้างมุมล่างเพื่อเพิ่มรายการแรก'),
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
    return NxRefresh(
      edgeOffset: top,
      color: theme.colorScheme.primary,
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: () {
          final p = bp.scrollPadding(context, hasFab: !twoPane);
          return p.copyWith(top: p.top + top);
        }(),
        itemCount: items.length + (_loadingMore ? 1 : 0) + (_showHint ? 1 : 0),
        itemBuilder: (context, i) {
          if (_showHint) {
            if (i == 0) return _hintBanner(theme);
            i -= 1;
          }
          if (i >= items.length) {
            // Next page: one more tile of the same kind.
            return KeyedSubtree(
              key: const ValueKey('entity-list-more'),
              child: _layout != null ? const NxSkeletonEntityCard() : const NxSkeletonRow(),
            );
          }
          final row = items[i];
          final id = row['id']?.toString() ?? '';
          final picked = _picked.contains(id);
          final phones = nxRowPhones(row);
          void open() {
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
          }

          final tile = _layout != null && _cardCtx != null
              ? NxEntityCard(
                  row: row,
                  layout: _layout!,
                  fields: _cardCtx!,
                  module: widget.module,
                  onTap: open,
                  onLongPress: () => _rowActions(row),
                )
              : NxEntityRow.fromRow(
                  row,
                  module: widget.module,
                  onLongPress: () => _rowActions(row),
                  onTap: open,
                );
          final decorated = picked
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  child: tile,
                )
              : tile;
          if (_picked.isNotEmpty || id.isEmpty) return decorated;
          // Swipe left = delete (undo 5 s), swipe right = call — both ask
          // first (accidental swipes); cancel snaps the card back.
          final canDelete = EntityRowPerms.of(widget.module, row).canDelete;
          if (phones.isEmpty && !canDelete) return decorated;
          final name = entityTitle(row, module: widget.module);
          return Dismissible(
            key: ValueKey('row-${widget.module}-$id'),
            direction: phones.isEmpty
                ? DismissDirection.endToStart
                : (canDelete ? DismissDirection.horizontal : DismissDirection.startToEnd),
            background: _swipeBg(
              theme.colorScheme.primary,
              NxI.phoneCall,
              'โทร',
              Alignment.centerLeft,
            ),
            secondaryBackground: _swipeBg(
              theme.colorScheme.error,
              NxI.trash,
              'ลบ',
              Alignment.centerRight,
            ),
            confirmDismiss: (dir) async {
              if (dir == DismissDirection.startToEnd) {
                final number = await showCallConfirm(context, name: name, phones: phones);
                if (number != null) launchUrl(Uri(scheme: 'tel', path: number));
                return false;
              }
              return showDeleteConfirm(context, name: name, loses: entityDeleteLoses(widget.module));
            },
            onDismissed: (_) => _deleteIds([id], name),
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
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: align,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            tr(label),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

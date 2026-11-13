import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/card_layout.dart' show formatMoney;
import '../../core/doc_form/doc_pick_rules.dart';
import '../../core/doc_form/quotation_math.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_icons.dart';
import 'barcode_scan_sheet.dart';

/// Search pages of the quotation form: customer (account / contact / lead),
/// contact of the chosen account, product / service (multi-select with
/// quantities) and plain option lists. Full-screen on a phone, a dialog on a
/// tablet — never a list dumped inside the form.

/// Opens [builder] as a full-screen page (phone) or a large dialog (tablet).
Future<T?> showDocPicker<T>(BuildContext context, WidgetBuilder builder) {
  final size = MediaQuery.sizeOf(context);
  if (size.width >= 700) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: SizedBox(width: 640, height: math.min(820, size.height * 0.9), child: builder(ctx)),
      ),
    );
  }
  return Navigator.of(context).push<T>(MaterialPageRoute(fullscreenDialog: true, builder: builder));
}

/// A record picked in a picker. [module] `none` = "ไม่ระบุ".
class PickedRecord {
  const PickedRecord(this.module, this.row);
  final String module;
  final Map<String, dynamic> row;
  bool get isNone => module == 'none';
}

/// One product / service with its quantity from the catalog picker.
class PickedCatalogItem {
  const PickedCatalogItem(this.module, this.row, this.qty);
  final String module;
  final Map<String, dynamic> row;
  final double qty;
}

/// Result of the catalog picker: items to add, or a typed line.
class CatalogPickResult {
  const CatalogPickResult({this.items = const [], this.freeLine = false});
  final List<PickedCatalogItem> items;
  final bool freeLine;
}

const _kindIcons = {'account': NxI.buildings, 'contact': NxI.user, 'lead': NxI.userPlus, 'product': NxI.package, 'service': NxI.wrench};
const _kindColors = {
  'account': Color(0xFF2563EB),
  'contact': Color(0xFF10B981),
  'lead': Color(0xFFF59E0B),
  'product': Color(0xFF6366F1),
  'service': Color(0xFFDB2777),
};
const _kindNames = {'account': 'บัญชีลูกค้า', 'contact': 'ผู้ติดต่อ', 'lead': 'ผู้มุ่งหวัง', 'product': 'สินค้า', 'service': 'บริการ'};

// ─────────────────────────────────────────────────────────── shared chrome

class _PickerFrame extends StatelessWidget {
  const _PickerFrame({
    required this.title,
    required this.search,
    required this.body,
    this.filters,
    this.bottom,
    this.actions,
    this.pageKey,
  });
  final String title;
  final Widget search;
  final Widget? filters;
  final Widget body;
  final Widget? bottom;
  final List<Widget>? actions;
  final Key? pageKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      key: pageKey,
      backgroundColor: theme.brightness == Brightness.dark ? cs.surface : cs.surfaceContainerLowest,
      appBar: AppBar(
        leading: IconButton(key: const ValueKey('picker-close'), tooltip: tr('ปิด'), icon: const Icon(NxI.x), onPressed: () => Navigator.of(context).pop()),
        title: Text(tr(title), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        titleSpacing: 0,
        actions: actions,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: search),
        ?filters,
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
        Expanded(child: body),
      ]),
      bottomNavigationBar: bottom,
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.hint, required this.fieldKey, this.loading = false, this.autofocus = true});
  final TextEditingController controller;
  final String hint;
  final Key fieldKey;
  final bool loading;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      key: fieldKey,
      controller: controller,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: tr(hint),
        prefixIcon: const Icon(NxI.magnifyingGlass, size: 20),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: cs.primary, width: 1.4)),
        suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
          if (loading) const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, v, _) => v.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(tooltip: tr('ล้าง'), icon: const Icon(NxI.x, size: 18), onPressed: controller.clear),
          ),
        ]),
      ),
    );
  }
}

/// Horizontal row of filter chips.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 8), children[i]],
        ]),
      );
}

Widget _filterChip(BuildContext context, {required Key key, required String label, required bool selected, required VoidCallback onTap, IconData? icon, int? count}) {
  final cs = Theme.of(context).colorScheme;
  return FilterChip(
    key: key,
    showCheckmark: false,
    avatar: icon == null ? null : Icon(icon, size: 16, color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant),
    label: Text(count == null ? tr(label) : '${tr(label)} · $count'),
    selected: selected,
    onSelected: (_) {
      HapticFeedback.selectionClick();
      onTap();
    },
    shape: const StadiumBorder(),
  );
}

class _StateView extends StatelessWidget {
  const _StateView({required this.icon, required this.title, this.text, this.action, this.stateKey});
  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;
  final Key? stateKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      key: stateKey,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 28, color: cs.primary),
        ),
        const SizedBox(height: 14),
        Text(tr(title), textAlign: TextAlign.center, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (text != null) ...[
          const SizedBox(height: 4),
          Text(tr(text!), textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
        if (action != null) ...[const SizedBox(height: 14), action!],
      ]),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
      child: Row(children: [
        Expanded(
          child: Text(tr(text), style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
        ),
        ?trailing,
      ]),
    );
  }
}

/// One record row: icon, name + type badge, subtitle.
class _RecordRow extends StatelessWidget {
  const _RecordRow({super.key, required this.module, required this.title, this.subtitle, this.onTap, this.selected = false, this.trailing, this.showBadge = true});
  final String module;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool selected;
  final Widget? trailing;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tint = _kindColors[module] ?? cs.primary;
    return Material(
      color: selected ? cs.primary.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
              child: Icon(_kindIcons[module] ?? NxI.note, size: 20, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (showBadge) ...[
                    const SizedBox(width: 6),
                    _Badge(text: _kindNames[module] ?? module, color: tint),
                  ],
                ]),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ]),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
      child: Text(
        tr(text),
        maxLines: 1,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: dark ? Color.lerp(color, Colors.white, 0.35) : color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ───────────────────────── the same chrome for other forms' pickers (job)

/// Page frame of a picker (job_pickers.dart uses the quotation's look).
class DocPickerFrame extends StatelessWidget {
  const DocPickerFrame({super.key, required this.title, required this.search, required this.body, this.filters, this.bottom, this.actions, this.pageKey});
  final String title;
  final Widget search;
  final Widget? filters;
  final Widget body;
  final Widget? bottom;
  final List<Widget>? actions;
  final Key? pageKey;

  @override
  Widget build(BuildContext context) =>
      _PickerFrame(title: title, search: search, body: body, filters: filters, bottom: bottom, actions: actions, pageKey: pageKey);
}

/// Search box of a picker.
class DocPickerSearchBox extends StatelessWidget {
  const DocPickerSearchBox({super.key, required this.controller, required this.hint, required this.fieldKey, this.loading = false, this.autofocus = true});
  final TextEditingController controller;
  final String hint;
  final Key fieldKey;
  final bool loading;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => _SearchBox(controller: controller, hint: hint, fieldKey: fieldKey, loading: loading, autofocus: autofocus);
}

/// Horizontal filter chips of a picker.
class DocPickerChips extends StatelessWidget {
  const DocPickerChips({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => _ChipRow(children: children);
}

Widget docPickerFilterChip(BuildContext context, {required Key key, required String label, required bool selected, required VoidCallback onTap, IconData? icon}) =>
    _filterChip(context, key: key, label: label, selected: selected, onTap: onTap, icon: icon);

/// Empty / error state of a picker.
class DocPickerState extends StatelessWidget {
  const DocPickerState({super.key, required this.icon, required this.title, this.text, this.action});
  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => _StateView(icon: icon, title: title, text: text, action: action);
}

/// Section label of a picker list.
class DocPickerSection extends StatelessWidget {
  const DocPickerSection(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => _SectionLabel(text, trailing: trailing);
}

/// Small coloured badge of a picker row.
class DocPickerBadge extends StatelessWidget {
  const DocPickerBadge({super.key, required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => _Badge(text: text, color: color);
}

/// Debounced text → [onSearch] (300 ms), skipping repeats.
mixin _Debounced<T extends StatefulWidget> on State<T> {
  final query = TextEditingController();
  Timer? _debounce;
  String _lastQ = '';

  void onSearch();

  void initDebounce() {
    query.addListener(() {
      if (query.text.trim() == _lastQ) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        _lastQ = query.text.trim();
        onSearch();
      });
    });
  }

  void disposeDebounce() {
    _debounce?.cancel();
    query.dispose();
  }
}

// ──────────────────────────────────────────────────────────── customer

/// Account / contact / lead in one search with type chips, "ของฉัน", recent
/// picks first and paging. Returns the picked record (the form loads it).
Future<PickedRecord?> showCustomerPicker(
  BuildContext context, {
  required ApiClient api,
  required List<String> modules,
  String? userId,
  String? businessId,
}) =>
    showDocPicker<PickedRecord>(context, (_) => CustomerPickerPage(api: api, modules: modules, userId: userId, businessId: businessId));

class CustomerPickerPage extends StatefulWidget {
  const CustomerPickerPage({super.key, required this.api, required this.modules, this.userId, this.businessId});
  final ApiClient api;
  final List<String> modules;
  final String? userId;
  final String? businessId;

  @override
  State<CustomerPickerPage> createState() => _CustomerPickerPageState();
}

class _CustomerPickerPageState extends State<CustomerPickerPage> with _Debounced<CustomerPickerPage> {
  String _kind = 'all';
  bool _mine = false;
  bool _loading = false;
  Object? _error;
  int _token = 0;
  List<Map<String, dynamic>> _recent = const [];
  final Map<String, List<Map<String, dynamic>>> _hits = {};
  final Map<String, int?> _totals = {};
  int _page = 1;
  bool _hasMore = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    initDebounce();
    _scroll.addListener(() {
      if (_kind != 'all' && _hasMore && !_loading && _scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _load(more: true);
    });
    DocRecentPicks.read('customer', widget.businessId).then((r) {
      if (mounted) setState(() => _recent = [for (final x in r) if (widget.modules.contains('${x['module']}')) x]);
    });
    _load();
  }

  @override
  void dispose() {
    disposeDebounce();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void onSearch() => _load();

  Map<String, String> get _filters => {if (_mine && widget.userId != null) 'smownerid': widget.userId!};

  Future<void> _load({bool more = false}) async {
    final q = query.text.trim();
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_kind == 'all') {
        final out = <String, List<Map<String, dynamic>>>{};
        final totals = <String, int?>{};
        Object? firstError;
        await Future.wait([
          for (final m in widget.modules)
            widget.api.searchPicker(m, q: q, limit: 6, filters: _filters).then((p) {
              out[m] = p.items;
              totals[m] = p.total;
            }).catchError((Object e) {
              firstError ??= e;
              out[m] = const <Map<String, dynamic>>[];
            }),
        ]);
        if (!mounted || token != _token) return;
        if (firstError != null && out.values.every((l) => l.isEmpty)) throw firstError!;
        setState(() {
          _hits
            ..clear()
            ..addAll(out);
          _totals
            ..clear()
            ..addAll(totals);
          _hasMore = false;
          _loading = false;
        });
      } else {
        final page = more ? _page + 1 : 1;
        final p = await widget.api.searchPicker(_kind, q: q, page: page, limit: 30, filters: _filters);
        if (!mounted || token != _token) return;
        setState(() {
          final prev = more ? (_hits[_kind] ?? const []) : const <Map<String, dynamic>>[];
          _hits
            ..clear()
            ..[_kind] = [...prev, ...p.items];
          _page = page;
          _hasMore = p.items.length >= 30 && (p.total == null || _hits[_kind]!.length < p.total!);
          _totals[_kind] = p.total;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _setKind(String k) {
    if (_kind == k) return;
    setState(() {
      _kind = k;
      _hits.clear();
    });
    _load();
  }

  void _pick(String module, Map<String, dynamic> row) {
    HapticFeedback.selectionClick();
    DocRecentPicks.add('customer', widget.businessId, {
      'module': module,
      'id': '${row['id']}',
      'title': customerRowTitle(module, row),
      'subtitle': customerRowSubtitle(module, row),
    });
    Navigator.of(context).pop(PickedRecord(module, row));
  }

  Widget _row(String module, Map<String, dynamic> r) => _RecordRow(
        key: ValueKey('customer-hit-$module-${r['id']}'),
        module: module,
        title: customerRowTitle(module, r),
        subtitle: customerRowSubtitle(module, r),
        onTap: () => _pick(module, r),
        trailing: Icon(NxI.caretRight, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
      );

  @override
  Widget build(BuildContext context) {
    final q = query.text.trim();
    final children = <Widget>[];
    if (_error != null && _hits.values.every((l) => l.isEmpty)) {
      children.add(_StateView(
        stateKey: const ValueKey('picker-error'),
        icon: NxI.warningCircle,
        title: 'โหลดรายการไม่สำเร็จ',
        text: formatApiError(_error!),
        action: OutlinedButton.icon(key: const ValueKey('picker-retry'), onPressed: _load, icon: const Icon(NxI.arrowCounterClockwise, size: 18), label: Text(tr('ลองอีกครั้ง'))),
      ));
    } else {
      if (q.isEmpty && _kind == 'all' && _recent.isNotEmpty && !_mine) {
        children.add(const _SectionLabel('ใช้ล่าสุด'));
        for (final r in _recent) {
          final m = '${r['module']}';
          children.add(_RecordRow(
            key: ValueKey('customer-recent-$m-${r['id']}'),
            module: m,
            title: '${r['title'] ?? ''}',
            subtitle: '${r['subtitle'] ?? ''}',
            onTap: () => _pick(m, {'id': r['id']}),
            trailing: Icon(NxI.clockCounterClockwise, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ));
        }
      }
      final mods = _kind == 'all' ? widget.modules : [_kind];
      for (final m in mods) {
        final list = _hits[m] ?? const [];
        if (list.isEmpty) continue;
        final total = _totals[m];
        children.add(_SectionLabel(
          _kind == 'all' ? (_kindNames[m] ?? m) : (q.isEmpty ? 'ทั้งหมด' : 'ผลการค้นหา'),
          trailing: _kind == 'all' && (total ?? 0) > list.length
              ? TextButton(key: ValueKey('customer-more-$m'), onPressed: () => _setKind(m), child: Text(tr('ดูทั้งหมด $total')))
              : null,
        ));
        for (final r in list) {
          children.add(_row(m, r));
        }
      }
      if (_hasMore) {
        children.add(const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))));
      }
      if (!_loading && _hits.values.every((l) => l.isEmpty)) {
        children.add(_StateView(
          stateKey: const ValueKey('picker-empty'),
          icon: NxI.magnifyingGlass,
          title: q.isEmpty ? 'ยังไม่มีรายการ' : 'ไม่พบ "$q"',
          text: q.isEmpty ? null : 'ลองค้นด้วยชื่อบริษัท ชื่อคน เบอร์โทร อีเมล หรือเลขผู้เสียภาษี',
        ));
      }
    }
    return _PickerFrame(
      pageKey: const ValueKey('customer-picker'),
      title: 'เลือกลูกค้า',
      search: _SearchBox(controller: query, fieldKey: const ValueKey('customer-search'), hint: 'ชื่อ บริษัท เบอร์ อีเมล หรือเลขภาษี', loading: _loading),
      filters: _ChipRow(children: [
        _filterChip(context, key: const ValueKey('customer-kind-all'), label: 'ทั้งหมด', selected: _kind == 'all', onTap: () => _setKind('all')),
        for (final m in widget.modules)
          _filterChip(context, key: ValueKey('customer-kind-$m'), label: _kindNames[m] ?? m, icon: _kindIcons[m], selected: _kind == m, onTap: () => _setKind(m)),
        if (widget.userId != null)
          _filterChip(context, key: const ValueKey('customer-mine'), label: 'ของฉัน', icon: NxI.userCircle, selected: _mine, onTap: () {
            setState(() => _mine = !_mine);
            _load();
          }),
      ]),
      body: ListView(key: const ValueKey('customer-results'), controller: _scroll, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: children),
    );
  }
}

// ───────────────────────────────────────────────────────────── contact

/// Contact of the chosen account (search inside them, or all contacts), with
/// "ไม่ระบุผู้ติดต่อ". Returns [PickedRecord] (`none` = clear).
Future<PickedRecord?> showContactPicker(BuildContext context, {required ApiClient api, String? accountId, String? accountName, String? selectedId, String? noneSubtitle}) =>
    showDocPicker<PickedRecord>(context, (_) => ContactPickerPage(api: api, accountId: accountId, accountName: accountName, selectedId: selectedId, noneSubtitle: noneSubtitle));

class ContactPickerPage extends StatefulWidget {
  const ContactPickerPage({super.key, required this.api, this.accountId, this.accountName, this.selectedId, this.noneSubtitle});
  final ApiClient api;
  final String? accountId;
  final String? accountName;
  final String? selectedId;

  /// Second line of "ไม่ระบุผู้ติดต่อ" (the job form: no named person on site).
  final String? noneSubtitle;

  @override
  State<ContactPickerPage> createState() => _ContactPickerPageState();
}

class _ContactPickerPageState extends State<ContactPickerPage> with _Debounced<ContactPickerPage> {
  late bool _ofAccount = widget.accountId != null;
  List<Map<String, dynamic>> _accountRows = const [];
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  Object? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    initDebounce();
    _load();
  }

  @override
  void dispose() {
    disposeDebounce();
    super.dispose();
  }

  @override
  void onSearch() {
    if (_ofAccount) {
      setState(() {});
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_ofAccount) {
        final rows = _accountRows.isNotEmpty ? _accountRows : await widget.api.getAccountContacts(widget.accountId!);
        if (!mounted || token != _token) return;
        setState(() {
          _accountRows = rows;
          _loading = false;
        });
      } else {
        final p = await widget.api.searchPicker('contact', q: query.text.trim(), limit: 30);
        if (!mounted || token != _token) return;
        setState(() {
          _rows = p.items;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _visible {
    if (!_ofAccount) return _rows;
    final q = query.text.trim().toLowerCase();
    if (q.isEmpty) return _accountRows;
    return [
      for (final r in _accountRows)
        if ('${customerRowTitle('contact', r)} ${customerRowSubtitle('contact', r)}'.toLowerCase().contains(q)) r,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = _visible;
    final q = query.text.trim();
    return _PickerFrame(
      pageKey: const ValueKey('contact-picker'),
      title: 'เลือกผู้ติดต่อ',
      search: _SearchBox(controller: query, fieldKey: const ValueKey('contact-search'), hint: 'ชื่อ เบอร์ หรืออีเมล', loading: _loading, autofocus: false),
      filters: widget.accountId == null
          ? null
          : _ChipRow(children: [
              _filterChip(context, key: const ValueKey('contact-of-account'), label: widget.accountName == null ? 'ของลูกค้านี้' : 'ของ ${widget.accountName}', icon: NxI.buildings, selected: _ofAccount, onTap: () {
                setState(() => _ofAccount = true);
                _load();
              }),
              _filterChip(context, key: const ValueKey('contact-all'), label: 'ผู้ติดต่อทั้งหมด', selected: !_ofAccount, onTap: () {
                setState(() => _ofAccount = false);
                _load();
              }),
            ]),
      body: ListView(key: const ValueKey('contact-results'), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
        _RecordRow(
          key: const ValueKey('contact-none'),
          module: 'contact',
          showBadge: false,
          title: tr('ไม่ระบุผู้ติดต่อ'),
          subtitle: tr(widget.noneSubtitle ?? 'ส่งถึงลูกค้าโดยไม่ระบุชื่อคน'),
          selected: widget.selectedId == null,
          trailing: widget.selectedId == null ? Icon(NxI.check, color: cs.primary, size: 20) : null,
          onTap: () => Navigator.of(context).pop(const PickedRecord('none', {})),
        ),
        if (_error != null)
          _StateView(stateKey: const ValueKey('picker-error'), icon: NxI.warningCircle, title: 'โหลดรายการไม่สำเร็จ', text: formatApiError(_error!), action: OutlinedButton(onPressed: _load, child: Text(tr('ลองอีกครั้ง'))))
        else ...[
          if (rows.isNotEmpty) _SectionLabel(_ofAccount ? 'ผู้ติดต่อของลูกค้า (${rows.length})' : 'ผู้ติดต่อ'),
          for (final r in rows)
            _RecordRow(
              key: ValueKey('contact-hit-${r['id']}'),
              module: 'contact',
              showBadge: false,
              title: customerRowTitle('contact', r),
              subtitle: customerRowSubtitle('contact', r),
              selected: '${r['id']}' == widget.selectedId,
              trailing: '${r['id']}' == widget.selectedId ? Icon(NxI.check, color: cs.primary, size: 20) : null,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop(PickedRecord('contact', r));
              },
            ),
          if (!_loading && rows.isEmpty)
            _StateView(
              stateKey: const ValueKey('picker-empty'),
              icon: NxI.addressBook,
              title: q.isEmpty ? (_ofAccount ? 'ลูกค้านี้ยังไม่มีผู้ติดต่อ' : 'ยังไม่มีผู้ติดต่อ') : 'ไม่พบ "$q"',
              text: _ofAccount ? 'ค้นจากผู้ติดต่อทั้งหมดได้ที่ "ผู้ติดต่อทั้งหมด"' : null,
            ),
        ],
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────────── catalog

/// Products + services: search by name / code / barcode, type and category
/// filters, price / unit / stock / image per row, multi-select with
/// quantities, "เพิ่ม N รายการ", and a typed line.
Future<CatalogPickResult?> showCatalogPicker(
  BuildContext context, {
  required ApiClient api,
  List<String> modules = const ['product', 'service'],
  String initialQuery = '',
  bool th = true,
}) =>
    showDocPicker<CatalogPickResult>(context, (_) => CatalogPickerPage(api: api, modules: modules, initialQuery: initialQuery, th: th));

class CatalogPickerPage extends StatefulWidget {
  const CatalogPickerPage({super.key, required this.api, this.modules = const ['product', 'service'], this.initialQuery = '', this.th = true});
  final ApiClient api;
  final List<String> modules;
  final String initialQuery;
  final bool th;

  @override
  State<CatalogPickerPage> createState() => _CatalogPickerPageState();
}

class _Sel {
  _Sel(this.module, this.row, this.qty);
  final String module;
  final Map<String, dynamic> row;
  double qty;
}

class _CatalogPickerPageState extends State<CatalogPickerPage> with _Debounced<CatalogPickerPage> {
  late String _kind = widget.modules.length == 1 ? widget.modules.first : 'all';
  String? _category;
  final Map<String, List<String>> _categories = {};
  final List<(String, Map<String, dynamic>)> _items = [];
  final Map<String, int> _page = {};
  final Map<String, bool> _more = {};
  final Map<String, _Sel> _sel = {};
  bool _loading = false;
  Object? _error;
  int _token = 0;
  bool _stockApi = true;
  final _scroll = ScrollController();

  static const _limit = 30;

  @override
  void initState() {
    super.initState();
    query.text = widget.initialQuery;
    _lastQ = widget.initialQuery.trim();
    initDebounce();
    _scroll.addListener(() {
      if (!_loading && _more.values.any((x) => x) && _scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _load(more: true);
    });
    for (final m in widget.modules) {
      widget.api.getFieldSchema(m).then((s) {
        final list = s.picklists[catalogCategoryField(m)] ?? const [];
        final values = [
          for (final o in list)
            if ('${o['value'] ?? o['label'] ?? ''}'.trim().isNotEmpty) '${o['value'] ?? o['label']}'.trim(),
        ];
        if (mounted && values.isNotEmpty) setState(() => _categories[m] = values);
      }).catchError((_) {});
    }
    _load();
  }

  @override
  void dispose() {
    disposeDebounce();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void onSearch() => _load();

  List<String> get _mods => _kind == 'all' ? widget.modules : [_kind];

  Future<void> _load({bool more = false}) async {
    final q = query.text.trim();
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    final got = <String, List<(String, Map<String, dynamic>)>>{};
    Object? err;
    final pages = <String, int>{};
    final mores = <String, bool>{};
    await Future.wait([
      for (final m in _mods)
        if (!more || (_more[m] ?? false))
          () async {
            final page = more ? (_page[m] ?? 1) + 1 : 1;
            try {
              final p = await widget.api.searchPicker(m, q: q, page: page, limit: _limit, filters: {
                if (_category != null && _kind == m) catalogCategoryField(m): _category!,
              });
              var rows = p.items;
              if (m == 'product' && _stockApi && rows.isNotEmpty) {
                try {
                  rows = mergeCatalogStock(rows, await widget.api.searchPartCatalog(q));
                } catch (_) {
                  _stockApi = false;
                }
              }
              got[m] = [for (final r in rows) (m, r)];
              pages[m] = page;
              mores[m] = p.items.length >= _limit && (p.total == null || page * _limit < p.total!);
            } catch (e) {
              err ??= e;
              mores[m] = false;
            }
          }(),
    ]);
    if (!mounted || token != _token) return;
    setState(() {
      if (!more) _items.clear();
      // Module order (products, then services), whichever answered first.
      for (final m in _mods) {
        _items.addAll(got[m] ?? const []);
      }
      _page.addAll(pages);
      if (!more) _more.clear();
      _more.addAll(mores);
      _error = got.values.every((l) => l.isEmpty) && !more ? err : null;
      _loading = false;
    });
  }

  void _setKind(String k) {
    if (_kind == k) return;
    setState(() {
      _kind = k;
      _category = null;
    });
    _load();
  }

  Future<void> _pickCategory() async {
    final values = _categories[_kind] ?? const [];
    final v = await showDocOptionPicker(
      context,
      title: 'หมวดหมู่',
      selected: _category ?? '',
      options: [const DocOption('', 'ทุกหมวดหมู่'), for (final c in values) DocOption(c, c)],
    );
    if (v == null || !mounted) return;
    setState(() => _category = v.isEmpty ? null : v);
    _load();
  }

  String _key(String m, Map<String, dynamic> r) => '$m:${r['id']}';

  void _toggle(String m, Map<String, dynamic> r) {
    HapticFeedback.selectionClick();
    setState(() {
      final k = _key(m, r);
      if (_sel.containsKey(k)) {
        _sel.remove(k);
      } else {
        _sel[k] = _Sel(m, r, 1);
      }
    });
  }

  void _qty(String k, double d) {
    HapticFeedback.selectionClick();
    setState(() {
      final s = _sel[k];
      if (s == null) return;
      s.qty += d;
      if (s.qty <= 0) _sel.remove(k);
    });
  }

  Future<void> _scan() async {
    final code = await scanProductBarcode(context);
    if (code == null || code.trim().isEmpty || !mounted) return;
    query.text = code.trim();
    _lastQ = code.trim();
    _debounce?.cancel();
    await _load();
    if (!mounted) return;
    // One exact match → select it (again = one more).
    if (_items.length == 1) {
      final (m, r) = _items.first;
      final k = _key(m, r);
      if (_sel.containsKey(k)) {
        _qty(k, 1);
      } else {
        _toggle(m, r);
      }
    }
  }

  void _done() {
    Navigator.of(context).pop(CatalogPickResult(items: [for (final s in _sel.values) PickedCatalogItem(s.module, s.row, s.qty)]));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final q = query.text.trim();
    final count = _sel.length;
    final hasCat = _kind != 'all' && (_categories[_kind] ?? const []).isNotEmpty;
    Widget body;
    if (_error != null && _items.isEmpty) {
      body = ListView(children: [
        _StateView(
          stateKey: const ValueKey('picker-error'),
          icon: NxI.warningCircle,
          title: 'โหลดรายการไม่สำเร็จ',
          text: formatApiError(_error!),
          action: OutlinedButton.icon(key: const ValueKey('picker-retry'), onPressed: _load, icon: const Icon(NxI.arrowCounterClockwise, size: 18), label: Text(tr('ลองอีกครั้ง'))),
        ),
      ]);
    } else if (!_loading && _items.isEmpty) {
      body = ListView(children: [
        _StateView(
          stateKey: const ValueKey('picker-empty'),
          icon: NxI.package,
          title: q.isEmpty ? 'ยังไม่มีสินค้า / บริการ' : 'ไม่พบ "$q"',
          text: q.isEmpty ? null : 'ค้นได้ทั้งชื่อไทย / อังกฤษ รหัส หรือบาร์โค้ด',
          action: OutlinedButton.icon(
            key: const ValueKey('catalog-free-line-empty'),
            onPressed: () => Navigator.of(context).pop(const CatalogPickResult(freeLine: true)),
            icon: const Icon(NxI.pencilSimple, size: 18),
            label: Text(tr('เพิ่มบรรทัดพิมพ์เอง')),
          ),
        ),
      ]);
    } else {
      body = ListView.builder(
        key: const ValueKey('catalog-results'),
        controller: _scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        itemCount: _items.length + (_more.values.any((x) => x) ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))));
          }
          final (m, r) = _items[i];
          final k = _key(m, r);
          return _CatalogRow(
            key: ValueKey('catalog-hit-$m-${r['id']}'),
            module: m,
            view: catalogItemView(m, r, th: widget.th),
            selected: _sel[k],
            imageUrl: (u) => u.startsWith('http') ? u : widget.api.absoluteUrl(u.startsWith('/') ? u : '/uploads/$u'),
            onTap: () => _toggle(m, r),
            onQty: (d) => _qty(k, d),
          );
        },
      );
    }
    final totalQty = _sel.values.fold<double>(0, (a, s) => a + s.qty);
    final totalPrice = _sel.values.fold<double>(0, (a, s) => a + s.qty * catalogItemView(s.module, s.row).price);
    return _PickerFrame(
      pageKey: const ValueKey('catalog-picker'),
      title: 'เพิ่มสินค้า / บริการ',
      actions: [
        IconButton(key: const ValueKey('catalog-scan'), tooltip: tr('สแกนบาร์โค้ด'), onPressed: _scan, icon: const Icon(NxI.scanLine)),
        const SizedBox(width: 4),
      ],
      search: _SearchBox(controller: query, fieldKey: const ValueKey('catalog-search'), hint: 'ชื่อ รหัส หรือบาร์โค้ด', loading: _loading),
      filters: _ChipRow(children: [
        if (widget.modules.length > 1)
          _filterChip(context, key: const ValueKey('catalog-kind-all'), label: 'ทั้งหมด', selected: _kind == 'all', onTap: () => _setKind('all')),
        for (final m in widget.modules)
          _filterChip(context, key: ValueKey('catalog-kind-$m'), label: _kindNames[m] ?? m, icon: _kindIcons[m], selected: _kind == m, onTap: () => _setKind(m)),
        if (hasCat)
          InputChip(
            key: const ValueKey('catalog-category'),
            avatar: Icon(NxI.funnel, size: 16, color: _category == null ? cs.onSurfaceVariant : cs.onSecondaryContainer),
            label: Text(_category ?? tr('หมวดหมู่')),
            selected: _category != null,
            showCheckmark: false,
            shape: const StadiumBorder(),
            onPressed: _pickCategory,
            deleteIcon: const Icon(NxI.x, size: 16),
            onDeleted: _category == null
                ? null
                : () {
                    setState(() => _category = null);
                    _load();
                  },
          ),
      ]),
      body: body,
      bottom: Material(
        color: theme.brightness == Brightness.dark ? cs.surfaceContainer : cs.surface,
        shape: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: count == 0
                ? Row(children: [
                    Expanded(child: Text(tr('แตะรายการเพื่อเลือก เลือกได้หลายรายการ'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('catalog-free-line'),
                      style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                      onPressed: () => Navigator.of(context).pop(const CatalogPickResult(freeLine: true)),
                      icon: const Icon(NxI.pencilSimple, size: 16),
                      label: Text(tr('พิมพ์เอง')),
                    ),
                  ])
                : Row(children: [
                    Expanded(
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('เลือก $count รายการ · ${_fmtQty(totalQty)} ชิ้น'), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                        Text('฿${formatMoney(totalPrice)}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: FilledButton.icon(
                        key: const ValueKey('catalog-confirm'),
                        style: FilledButton.styleFrom(shape: const StadiumBorder()),
                        onPressed: _done,
                        icon: const Icon(NxI.plus, size: 18),
                        label: Text(tr('เพิ่ม $count รายการ')),
                      ),
                    ),
                  ]),
          ),
        ),
      ),
    );
  }
}

String _fmtQty(double q) => q == q.roundToDouble() ? '${q.toInt()}' : q.toStringAsFixed(2);

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({super.key, required this.module, required this.view, required this.onTap, required this.onQty, required this.imageUrl, this.selected});
  final String module;
  final CatalogItemView view;
  final _Sel? selected;
  final VoidCallback onTap;
  final ValueChanged<double> onQty;
  final String Function(String) imageUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tint = _kindColors[module] ?? cs.primary;
    final on = selected != null;
    final stock = view.stock;
    final icon = Icon(_kindIcons[module], size: 22, color: tint);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: on ? cs.primary.withValues(alpha: 0.1) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: on ? cs.primary.withValues(alpha: 0.6) : Colors.transparent, width: 1.4),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child: view.image == null
                    ? icon
                    : CachedNetworkImage(imageUrl: imageUrl(view.image!), fit: BoxFit.cover, errorWidget: (_, _, _) => icon, placeholder: (_, _) => icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(view.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
                  const SizedBox(height: 3),
                  Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    _Badge(text: _kindNames[module] ?? module, color: tint),
                    if (view.code.isNotEmpty) Text(view.code, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    if (stock != null)
                      _Badge(
                        text: stock > 0 ? 'คงเหลือ ${_fmtQty(stock)}' : 'หมดสต็อก',
                        color: stock > 0 ? const Color(0xFF16A34A) : cs.error,
                      ),
                  ]),
                  const SizedBox(height: 3),
                  Text(view.priceText, key: ValueKey('catalog-price-$module'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
                ]),
              ),
              const SizedBox(width: 6),
              on
                  ? DocQtyStepper(
                      key: const ValueKey('catalog-qty'),
                      value: selected!.qty,
                      onMinus: () => onQty(-1),
                      onPlus: () => onQty(1),
                    )
                  : Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: cs.outlineVariant)),
                      child: Icon(NxI.plus, size: 18, color: cs.primary),
                    ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Compact − qty + (buttons only; the line card has its own typed field).
class DocQtyStepper extends StatelessWidget {
  const DocQtyStepper({super.key, required this.value, required this.onMinus, required this.onPlus});
  final double value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget b(Key key, IconData icon, VoidCallback onTap, String tip) => IconButton(
          key: key,
          tooltip: tr(tip),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(backgroundColor: cs.primary.withValues(alpha: 0.12), foregroundColor: cs.primary),
          onPressed: onTap,
          icon: Icon(icon, size: 16),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      b(const ValueKey('qty-minus'), value <= 1 ? NxI.trash : NxI.minus, onMinus, value <= 1 ? 'เอาออก' : 'ลด'),
      SizedBox(
        width: 30,
        child: Text(_fmtQty(value), key: const ValueKey('qty-value'), textAlign: TextAlign.center, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      ),
      b(const ValueKey('qty-plus'), NxI.plus, onPlus, 'เพิ่ม'),
    ]);
  }
}

// ─────────────────────────────────────────────────────────── option lists

class DocOption {
  const DocOption(this.value, this.label, {this.subtitle, this.icon});
  final String value;
  final String label;
  final String? subtitle;
  final IconData? icon;
}

/// A plain list to pick one of (template, category …), searchable when long.
Future<String?> showDocOptionPicker(BuildContext context, {required String title, required List<DocOption> options, String? selected, String keyPrefix = 'option'}) =>
    showDocPicker<String>(context, (_) => _OptionPickerPage(title: title, options: options, selected: selected, keyPrefix: keyPrefix));

class _OptionPickerPage extends StatefulWidget {
  const _OptionPickerPage({required this.title, required this.options, this.selected, required this.keyPrefix});
  final String title;
  final List<DocOption> options;
  final String? selected;
  final String keyPrefix;

  @override
  State<_OptionPickerPage> createState() => _OptionPickerPageState();
}

class _OptionPickerPageState extends State<_OptionPickerPage> {
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final q = _q.text.trim().toLowerCase();
    final list = [for (final o in widget.options) if (q.isEmpty || '${o.label} ${o.subtitle ?? ''}'.toLowerCase().contains(q)) o];
    return _PickerFrame(
      pageKey: ValueKey('${widget.keyPrefix}-picker'),
      title: widget.title,
      search: _SearchBox(controller: _q, fieldKey: ValueKey('${widget.keyPrefix}-search'), hint: 'ค้นหา', autofocus: false),
      body: list.isEmpty
          ? ListView(children: [_StateView(icon: NxI.magnifyingGlass, title: 'ไม่พบ "${_q.text.trim()}"')])
          : ListView(padding: const EdgeInsets.symmetric(vertical: 6), children: [
              for (final o in list)
                ListTile(
                  key: ValueKey('${widget.keyPrefix}-${o.value.isEmpty ? 'none' : o.value}'),
                  leading: o.icon == null ? null : Icon(o.icon, color: cs.primary),
                  title: Text(tr(o.label), style: theme.textTheme.bodyLarge?.copyWith(fontWeight: o.value == widget.selected ? FontWeight.w800 : FontWeight.w500)),
                  subtitle: o.subtitle == null ? null : Text(tr(o.subtitle!)),
                  selected: o.value == widget.selected,
                  trailing: o.value == widget.selected ? Icon(NxI.check, color: cs.primary) : null,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).pop(o.value);
                  },
                ),
            ]),
    );
  }
}

/// Quantity text of a line (`2`, `1.5`).
String docQtyText(Object? v) => _fmtQty(qNum(v));

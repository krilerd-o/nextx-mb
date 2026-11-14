import 'package:flutter/material.dart';
import '../../core/thai_time.dart';
import '../../widgets/nx_search_debounce.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/menu_access.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_split_view.dart';
import '../../widgets/nx_icons.dart';
import '../crm/order_summary_screen.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_list_toolbar.dart';
import '../../widgets/nx_refresh.dart';

/// NEXTX order queues (backend/src/services/commercialOrderQueueService.js).
const orderQueues = <String, String>{
  'new_today': 'ใหม่วันนี้',
  'awaiting_payment': 'รอชำระ',
  'awaiting_label': 'รอพิมพ์ใบปะหน้า',
  'awaiting_pickup': 'รอขนส่งรับ',
  'in_transit': 'กำลังส่ง',
  'delivered': 'ส่งแล้ว',
  'cancelled': 'ยกเลิก',
  'all': 'ทั้งหมด',
};

String paymentStatusLabel(String? s) {
  switch ((s ?? '').toLowerCase()) {
    case 'paid':
      return 'ชำระแล้ว';
    case 'unpaid':
    case '':
      return 'ยังไม่ชำระ';
    case 'refunded':
      return 'คืนเงินแล้ว';
    case 'partial':
      return 'ชำระบางส่วน';
    default:
      return s!;
  }
}

String formatBaht(dynamic v) {
  final n = num.tryParse(v?.toString() ?? '');
  if (n == null) return '';
  final fixed = n.toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '฿$whole.${parts[1]}';
}

class CommerceHomeScreen extends StatelessWidget {
  const CommerceHomeScreen({super.key});

  static const ordersMenu = MenuAccess.storeOrders;
  static const stockMenu = MenuAccess.storeStock;

  @override
  Widget build(BuildContext context) {
    final session = context.select((AppConfig c) => c.session);
    // Stock endpoints are owner/admin only on the server (requireCommercialAdmin).
    final tabs = <(String, Widget)>[
      if (MenuAccess.allow(session, ordersMenu)) ('ออเดอร์', const _OrdersTab()),
      if (MenuAccess.allow(session, stockMenu) && session.isBusinessAdmin) ('สต็อก', const _StockTab()),
    ];
    if (tabs.isEmpty) {
      return NxScrollScaffold(
        header: NxAppHeader(title: 'ร้านค้า'),
        body: Center(child: Text(tr('ไม่มีสิทธิ์เข้าถึงร้านค้า (สต็อกดูได้เฉพาะเจ้าของหรือแอดมิน)'))),
      );
    }
    return DefaultTabController(
      length: tabs.length,
      child: NxScrollScaffold(
        header: const NxAppHeader(title: 'ร้านค้า'),
        body: Column(
          children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              labelPadding: const EdgeInsets.symmetric(horizontal: 20),
              tabs: [for (final t in tabs) Tab(text: t.$1)],
            ),
            Expanded(child: TabBarView(children: [for (final t in tabs) t.$2])),
          ],
        ),
      ),
    );
  }
}

class _OrdersTab extends StatefulWidget {
  const _OrdersTab();

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  String _queue = 'new_today';
  NxListQuery _lq = const NxListQuery();

  String _at(Map o) => '${o['created_at'] ?? o['order_date'] ?? o['id'] ?? ''}';
  num _amount(Map o) => num.tryParse('${o['grand_total'] ?? 0}') ?? 0;

  /// Queue comes from the server; search and sort apply to the loaded page.
  List<Map<String, dynamic>> get _shown => nxApplyLocalQuery<Map<String, dynamic>>(
        _items,
        _lq,
        text: (o) => '${o['order_number'] ?? ''} ${o['customer_name'] ?? ''} ${o['customer_phone'] ?? ''} ${o['id'] ?? ''}',
        sorts: {
          'new': (a, b) => _at(b).compareTo(_at(a)),
          'old': (a, b) => _at(a).compareTo(_at(b)),
          'amount': (a, b) => _amount(b).compareTo(_amount(a)),
        },
      );
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _counts = {};
  Map<String, dynamic>? _selected;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final r = await context.read<AppConfig>().apiClient.getCommercialOrders(queue: _queue, limit: 50);
      if (!mounted) return;
      setState(() {
        _items = r.items;
        final qc = r.meta['queue_counts'];
        if (qc is Map) _counts = Map<String, dynamic>.from(qc);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _markPaid(Map<String, dynamic> o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ยืนยันรับชำระ?')),
        content: Text(tr('ออเดอร์ ${o['order_number'] ?? o['id']} ${formatBaht(o['grand_total'])}')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('รับชำระแล้ว'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppConfig>().apiClient.markCommercialOrderPaid(o['id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('บันทึกการชำระแล้ว'))));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            children: [
              for (final e in orderQueues.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(tr(_counts[e.key] != null ? '${e.value} (${_counts[e.key]})' : e.value)),
                    selected: _queue == e.key,
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() {
                        _queue = e.key;
                        _items = [];
                      });
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        NxListToolbar(
          query: _lq,
          liveSearch: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          searchHint: 'ค้นหาเลขออเดอร์ / ลูกค้า',
          sorts: const [
            NxSortOption('new', 'ใหม่ล่าสุด'),
            NxSortOption('old', 'เก่าสุด'),
            NxSortOption('amount', 'ยอดสูงสุด'),
          ],
          onChanged: (q) => setState(() => _lq = q),
        ),
        Expanded(
          child: NxSplitView(
            onClose: () => setState(() => _selected = null),
            detail: _selected == null
                ? null
                : OrderSummaryScreen(
                    key: ValueKey(_selected!['id']),
                    orderId: _selected!['id'].toString(),
                    preview: _selected!,
                  ),
            list: NxRefresh(
            onRefresh: _load,
            child: _loading
                ? const NxSkeletonList()
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      if (_error != null) Text(tr(formatApiError(_error!)), style: TextStyle(color: cs.error)),
                      if (_error == null && _shown.isEmpty)
                        Padding(padding: EdgeInsets.all(48), child: Center(child: Text(tr('ไม่มีออเดอร์ในคิวนี้')))),
                      for (final o in _shown)
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: cs.primaryContainer,
                              child: Icon(NxI.receipt, color: cs.onPrimaryContainer),
                            ),
                            title: Text(tr('${o['order_number'] ?? '#${o['id']}'}'), style: theme.textTheme.titleSmall),
                            subtitle: Text(
                              tr([
                                o['customer_name']?.toString() ?? '',
                                paymentStatusLabel(o['payment_status']?.toString()),
                                thaiDate(o['order_date'], year: uiYear),
                              ].where((e) => e.isNotEmpty).join(' · ')),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(tr(formatBaht(o['grand_total'])), style: theme.textTheme.titleSmall),
                                if ((o['payment_status']?.toString() ?? 'unpaid') != 'paid' &&
                                    context.read<AppConfig>().session.isBusinessAdmin)
                                  InkWell(
                                    onTap: () => _markPaid(o),
                                    child: Text(tr('รับชำระ'), style: theme.textTheme.labelMedium?.copyWith(color: cs.primary)),
                                  ),
                              ],
                            ),
                            selected: _selected?['id'] == o['id'],
                            onTap: () {
                              if (NxBreakpoint.of(context).twoPane) {
                                setState(() => _selected = o);
                                return;
                              }
                              nxPush<void>(
                                context,
                                OrderSummaryScreen(orderId: o['id'].toString(), preview: o),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
          ),
          ),
        ),
      ],
    );
  }
}

class _StockTab extends StatefulWidget {
  const _StockTab();

  @override
  State<_StockTab> createState() => _StockTabState();
}

class _StockTabState extends State<_StockTab> {
  final _q = TextEditingController();
  final _wait = NxSearchDebounce();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _wait.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final list = await context.read<AppConfig>().apiClient.getStockBalance(q: _q.text);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _move(Map<String, dynamic> product, {Map<String, dynamic>? variant}) async {
    var kind = 'in';
    final qty = TextEditingController();
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          scrollable: true,
          title: Text(tr('${product['name'] ?? ''}${variant != null ? ' · ${variant['sku_code'] ?? ''}' : ''}')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'in', label: Text(tr('รับเข้า'))),
                  ButtonSegment(value: 'out', label: Text(tr('จ่ายออก'))),
                  ButtonSegment(value: 'adjust', label: Text(tr('ปรับยอด'))),
                ],
                selected: {kind},
                onSelectionChanged: (v) => setD(() => kind = v.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qty,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: InputDecoration(labelText: trn(kind == 'adjust' ? 'เพิ่ม/ลด (เช่น -2)' : 'จำนวน')),
              ),
              TextField(controller: notes, decoration: InputDecoration(labelText: tr('หมายเหตุ'))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('บันทึก'))),
          ],
        ),
      ),
    );
    final amount = num.tryParse(qty.text.trim());
    final note = notes.text.trim();
    qty.dispose();
    notes.dispose();
    if (ok != true || !mounted) return;
    if (amount == null || amount == 0 || (kind != 'adjust' && amount < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('จำนวนไม่ถูกต้อง'))));
      return;
    }
    try {
      await context.read<AppConfig>().apiClient.moveStock(
            kind: kind,
            productId: product['product_id'].toString(),
            variantId: variant?['id']?.toString(),
            amount: amount,
            notes: note,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('บันทึกสต็อกแล้ว'))));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NxRefresh(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onChanged: (_) => _wait.schedule(() {
              if (mounted) _load();
            }),
            onSubmitted: (_) {
              _wait.cancel();
              _load();
            },
            decoration: InputDecoration(
              hintText: tr('ค้นหาชื่อหรือรหัสสินค้า'),
              prefixIcon: const Icon(NxI.magnifyingGlass),
              filled: true,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading) const NxSkeletonList(rows: 6, padded: false),
          if (_error != null) Text(tr(formatApiError(_error!)), style: TextStyle(color: cs.error)),
          if (!_loading && _error == null && _items.isEmpty)
            Padding(padding: EdgeInsets.all(48), child: Center(child: Text(tr('ไม่พบสินค้า')))),
          for (final p in _items)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: [
                  ListTile(
                    leading: CircleAvatar(backgroundColor: cs.surfaceContainerHighest, child: Icon(NxI.package, color: cs.onSurfaceVariant)),
                    title: Text(tr(p['name']?.toString() ?? '')),
                    subtitle: Text(tr(p['code']?.toString() ?? '')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tr('${p['stock_qty'] ?? '—'}'), style: theme.textTheme.titleMedium?.copyWith(
                          color: (num.tryParse('${p['stock_qty']}') ?? 1) <= 0 ? cs.error : null,
                        )),
                        IconButton(icon: const Icon(NxI.pencilSimple), onPressed: () => _move(p)),
                      ],
                    ),
                  ),
                  for (final v in (p['variants'] is List ? p['variants'] as List : const []).whereType<Map>())
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 72, right: 16),
                      title: Text(tr(v['sku_code']?.toString() ?? 'ตัวเลือก')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(tr('${v['stock_qty'] ?? '—'}')),
                          IconButton(
                            icon: const Icon(NxI.pencilSimple, size: 18),
                            onPressed: () => _move(p, variant: Map<String, dynamic>.from(v)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

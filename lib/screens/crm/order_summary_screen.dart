import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../services/api_client.dart';
import '../../services/file_open.dart';
import '../../widgets/key_value_card.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import '../commerce/commerce_home_screen.dart' show formatBaht, paymentStatusLabel;
import '../../core/i18n.dart';

/// `GET /api/commercial/orders/:id` returns `{order, lines, address}`; older
/// callers passed the order row directly — accept both.
({Map<String, dynamic> order, List<Map<String, dynamic>> lines, Map<String, dynamic>? address}) parseOrderDetail(
  Map<String, dynamic> data,
) {
  final order = asStringKeyedMap(data['order']) ?? data;
  final lines = extractMapList(data['lines']);
  return (order: order, lines: lines, address: asStringKeyedMap(data['address']));
}

class OrderSummaryScreen extends StatefulWidget {
  const OrderSummaryScreen({
    super.key,
    required this.orderId,
    this.preview = const {},
  });

  final String orderId;
  final Map<String, dynamic> preview;

  @override
  State<OrderSummaryScreen> createState() => _OrderSummaryScreenState();
}

class _OrderSummaryScreenState extends State<OrderSummaryScreen> {
  Map<String, dynamic> _row = {};
  List<Map<String, dynamic>> _lines = [];
  Map<String, dynamic>? _address;
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _row = Map<String, dynamic>.from(widget.preview);
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AppConfig>().apiClient.getCommercialOrder(widget.orderId);
      final d = parseOrderDetail(data);
      if (mounted) {
        setState(() {
          _row = {..._row, ...d.order, 'id': widget.orderId};
          _lines = d.lines;
          _address = d.address;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _pdf({required bool label, bool share = false}) async {
    setState(() => _busy = true);
    final api = context.read<AppConfig>().apiClient;
    try {
      final bytes = label ? await api.downloadShippingLabel(widget.orderId) : await api.downloadOrderReceipt(widget.orderId);
      final name = '${label ? 'label' : 'receipt'}-${_row['order_number'] ?? widget.orderId}.pdf';
      share ? await shareFileBytes(bytes, name) : await openFileBytes(bytes, name);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markPaid() async {
    setState(() => _busy = true);
    try {
      await context.read<AppConfig>().apiClient.markCommercialOrderPaid(widget.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('บันทึกการชำระแล้ว'))));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final no = _row['order_number'] ?? _row['order_no'] ?? widget.orderId;
    final paid = (_row['payment_status']?.toString() ?? '') == 'paid';
    final isAdmin = context.select((AppConfig c) => c.session).isBusinessAdmin;
    final addr = _address;
    return NxScrollScaffold(
      header: NxAppHeader(
        title: 'ออเดอร์ $no',
        menu: [
          NxHeaderMenuItem(label: 'แชร์ใบเสร็จ', icon: NxI.shareNetwork, onTap: () => _pdf(label: false, share: true)),
          NxHeaderMenuItem(label: 'ใบปะหน้าพัสดุ', icon: NxI.package, onTap: () => _pdf(label: true)),
        ],
      ),
      body: _loading
          ? const NxSkeletonForm(fields: 4)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_busy) const LinearProgressIndicator(minHeight: 2),
                if (_error != null) Text(tr(formatApiError(_error!)), style: TextStyle(color: theme.colorScheme.error)),
                KeyValueCard(
                  entries: [
                    MapEntry('เลขที่', no.toString()),
                    MapEntry('วันที่', (_row['order_date']?.toString() ?? '—').split('T').first),
                    MapEntry('สถานะ', (_row['status'] ?? '—').toString()),
                    MapEntry('การชำระ', paymentStatusLabel(_row['payment_status']?.toString())),
                    MapEntry('ยอดรวม', formatBaht(_row['grand_total'] ?? _row['total']).isEmpty ? '—' : formatBaht(_row['grand_total'] ?? _row['total'])),
                    MapEntry('ลูกค้า', (_row['customer_name'] ?? '—').toString()),
                    if (_row['customer_phone'] != null) MapEntry('โทร', _row['customer_phone'].toString()),
                  ],
                ),
                if (addr != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(NxI.mapPin),
                      title: Text(tr('ที่อยู่จัดส่ง')),
                      subtitle: Text(
                        tr([
                          addr['recipient_name'],
                          addr['address_line'] ?? addr['address'],
                          addr['subdistrict'],
                          addr['district'],
                          addr['province'],
                          addr['postal_code'],
                          addr['phone'],
                        ].where((e) => e != null && e.toString().trim().isNotEmpty).join(' ')),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(tr('รายการสินค้า (${_lines.length})'), style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final l in _lines)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(NxI.package),
                      title: Text(tr(l['product_name']?.toString() ?? 'สินค้า')),
                      subtitle: Text(
                        tr([
                          if ((l['variant_options_label']?.toString() ?? '').isNotEmpty) l['variant_options_label'].toString(),
                          '${l['quantity'] ?? 0} ${l['unit'] ?? ''} × ${formatBaht(l['unit_price'])}',
                        ].join(' · ')),
                      ),
                      trailing: Text(tr(formatBaht(l['line_total'])), style: theme.textTheme.titleSmall),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _pdf(label: false),
                        icon: const Icon(NxI.filePdf),
                        label: Text(tr('ใบเสร็จ')),
                      ),
                    ),
                    if (!paid && isAdmin) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _markPaid,
                          icon: const Icon(NxI.checkCircle),
                          label: Text(tr('รับชำระแล้ว')),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
    );
  }
}

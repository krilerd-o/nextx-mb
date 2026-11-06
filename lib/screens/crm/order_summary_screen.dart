import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../services/api_client.dart';
import '../../widgets/key_value_card.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_skeleton.dart';

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
  bool _loading = true;
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
      if (mounted) {
        setState(() {
          _row = {..._row, ...data, 'id': widget.orderId};
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

  @override
  Widget build(BuildContext context) {
    final no = _row['order_no'] ?? _row['order_number'] ?? widget.preview['order_number'] ?? widget.orderId;
    return Scaffold(
      appBar: NxAppHeader(title: 'ออเดอร์ $no'),
      body: _loading
          ? const NxSkeletonForm(fields: 4)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) Text(formatApiError(_error!)),
                KeyValueCard(
                  entries: [
                    MapEntry('เลขที่', no.toString()),
                    MapEntry('สถานะ', (_row['status'] ?? '—').toString()),
                    MapEntry(
                      'ยอด',
                      (_row['grand_total'] ?? _row['total'] ?? _row['amount'] ?? '—').toString(),
                    ),
                    MapEntry('ลูกค้า', (_row['customer_name'] ?? _row['name'] ?? '—').toString()),
                  ],
                ),
              ],
            ),
    );
  }
}

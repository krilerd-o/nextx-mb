import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';

num _n(Object? v) => num.tryParse('${v ?? ''}') ?? 0;
String _qty(Object? v) {
  final n = _n(v);
  return n == n.roundToDouble() ? '${n.toInt()}' : '$n';
}

/// Parts used on a job (optional — never required to close the job).
/// Shows who added each line, and stock taken / returned for tracked products.
class JobPartsSection extends StatelessWidget {
  const JobPartsSection({super.key, required this.jobId, required this.parts, required this.canEdit, required this.onChanged});
  final String jobId;
  final List<Map<String, dynamic>> parts;
  final bool canEdit;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      key: const ValueKey('job-parts'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Text(tr('อะไหล่ / ชิ้นส่วน'), style: theme.textTheme.titleSmall),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(99)),
            child: Text(tr('ไม่บังคับ'), style: theme.textTheme.labelSmall),
          ),
        ]),
        const SizedBox(height: 4),
        Text(tr('บันทึกเมื่อมีการใช้อะไหล่ ไม่มีผลกับการปิดงาน'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        if (parts.isEmpty)
          Text(tr('ยังไม่มีอะไหล่'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        for (final p in parts) _PartRow(jobId: jobId, part: p, canEdit: canEdit, onChanged: onChanged),
        if (canEdit)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('job-part-add'),
              onPressed: () async {
                final ok = await showAddJobPartSheet(context, jobId);
                if (ok == true) await onChanged();
              },
              icon: const Icon(NxI.plus, size: 18),
              label: Text(tr('เพิ่มอะไหล่')),
            ),
          ),
      ],
    );
  }
}

class _PartRow extends StatelessWidget {
  const _PartRow({required this.jobId, required this.part, required this.canEdit, required this.onChanged});
  final String jobId;
  final Map<String, dynamic> part;
  final bool canEdit;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = part;
    final name = '${p['product_name'] ?? p['description'] ?? p['part_name'] ?? 'อะไหล่'}';
    final unit = '${p['unit'] ?? ''}'.trim();
    final who = '${p['created_by_name'] ?? ''}'.trim();
    final when = formatThaiField(p['created_at'], 'created_at', year: uiYear);
    final fromStock = _n(p['stock_qty_deducted']) > 0;
    return Container(
      key: ValueKey('job-part-${p['id']}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: const Color(0xFF8B5CF6).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
          child: const Icon(NxI.package, size: 18, color: Color(0xFF8B5CF6)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (fromStock)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFF16A34A).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
                  child: Text(tr('ตัดสต็อกแล้ว'), style: theme.textTheme.labelSmall?.copyWith(color: const Color(0xFF16A34A), fontWeight: FontWeight.w700)),
                ),
              if (who.isNotEmpty || when.isNotEmpty)
                Text([who, when].where((e) => e.isNotEmpty).join(' · '), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ]),
        ),
        Text('× ${_qty(p['quantity'] ?? p['qty'] ?? 1)}${unit.isEmpty ? '' : ' $unit'}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        if (canEdit)
          IconButton(
            key: ValueKey('job-part-del-${p['id']}'),
            tooltip: tr('ลบ'),
            icon: Icon(NxI.trash, size: 18, color: cs.error),
            onPressed: () => _delete(context),
          ),
      ]),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final fromStock = _n(part['stock_qty_deducted']) > 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('ลบรายการอะไหล่?')),
        content: Text(tr(fromStock ? 'จำนวนที่ตัดสต็อกไว้จะถูกคืนเข้าสต็อก' : 'รายการจะถูกซ่อนจากใบสั่งงานนี้')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('ยกเลิก'))),
          FilledButton(key: const ValueKey('job-part-del-ok'), onPressed: () => Navigator.pop(d, true), child: Text(tr('ลบ'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final r = await context.read<AppConfig>().apiClient.deleteJobPart(jobId, '${part['id']}');
      messenger?.showSnackBar(SnackBar(content: Text(tr(r['stock_returned'] is Map ? 'ลบแล้ว และคืนสต็อกแล้ว' : 'ลบแล้ว'))));
      await onChanged();
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }
}

/// Pick a product (with stock on hand) or type a free-text part.
Future<bool?> showAddJobPartSheet(BuildContext context, String jobId) {
  return showAppBottomSheet<bool>(context: context, title: tr('เพิ่มอะไหล่'), child: _AddPartForm(jobId: jobId));
}

class _AddPartForm extends StatefulWidget {
  const _AddPartForm({required this.jobId});
  final String jobId;

  @override
  State<_AddPartForm> createState() => _AddPartFormState();
}

class _AddPartFormState extends State<_AddPartForm> {
  final _name = TextEditingController();
  num _qtyValue = 1;
  Map<String, dynamic>? _product;
  List<Map<String, dynamic>> _hits = const [];
  bool _catalog = true, _saving = false;
  String? _error;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    if (!_catalog || q.trim().length < 2) {
      setState(() => _hits = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await context.read<AppConfig>().apiClient.searchPartCatalog(q.trim());
        if (mounted) setState(() => _hits = r);
      } catch (_) {
        if (mounted) setState(() => _catalog = false); // older server: free text only
      }
    });
  }

  Future<void> _save() async {
    if (_product == null && _name.text.trim().isEmpty) {
      setState(() => _error = tr('ระบุชื่ออะไหล่หรือเลือกสินค้า'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final pr = _product;
      await context.read<AppConfig>().apiClient.addJobPart(widget.jobId, {
        if (pr != null) ...{
          'product_id': pr['product_id'],
          if (pr['unit'] != null) 'unit': pr['unit'],
          if (pr['unit_cost'] != null) 'unit_cost': pr['unit_cost'],
        } else
          'description': _name.text.trim(),
        'quantity': _qtyValue,
      });
      HapticFeedback.lightImpact();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = formatApiError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pr = _product;
    final stock = pr == null ? null : (pr['stock_qty'] == null ? null : _n(pr['stock_qty']));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pr == null) ...[
          TextField(
            key: const ValueKey('job-part-name'),
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(
              labelText: tr('ค้นหาสินค้า หรือพิมพ์ชื่ออะไหล่'),
              prefixIcon: const Icon(NxI.magnifyingGlass, size: 18),
            ),
            onChanged: _search,
          ),
          if (_hits.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final h in _hits)
                    ListTile(
                      key: ValueKey('job-part-hit-${h['product_id']}'),
                      dense: true,
                      leading: const Icon(NxI.package, size: 18),
                      title: Text('${h['name'] ?? ''}'),
                      subtitle: Text('${h['code'] ?? ''}'),
                      trailing: Text(
                        h['stock_qty'] == null ? tr('ไม่ได้ติดตามสต็อก') : tr('คงเหลือ ${_qty(h['stock_qty'])}'),
                        style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      onTap: () => setState(() {
                        _product = h;
                        _hits = const [];
                      }),
                    ),
                ],
              ),
            ),
          ],
        ] else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Icon(NxI.package, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${pr['name']}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                    stock == null ? tr('ไม่ได้ติดตามสต็อก') : tr('จะตัดสต็อก (คงเหลือ ${_qty(stock)})'),
                    key: const ValueKey('job-part-stock'),
                    style: theme.textTheme.bodySmall,
                  ),
                ]),
              ),
              IconButton(icon: const Icon(NxI.x, size: 18), onPressed: () => setState(() => _product = null)),
            ]),
          ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text(tr('จำนวน'), style: theme.textTheme.titleSmall)),
          IconButton.filledTonal(
            key: const ValueKey('job-part-minus'),
            onPressed: _qtyValue > 1 ? () => setState(() => _qtyValue -= 1) : null,
            icon: const Icon(NxI.minus, size: 18),
          ),
          SizedBox(
            width: 56,
            child: Text(_qty(_qtyValue), key: const ValueKey('job-part-qty'), textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ),
          IconButton.filledTonal(
            key: const ValueKey('job-part-plus'),
            onPressed: () => setState(() => _qtyValue += 1),
            icon: const Icon(NxI.plus, size: 18),
          ),
        ]),
        if (stock != null && _qtyValue > stock)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr('สต็อกไม่พอ — คงเหลือ ${_qty(stock)}'), style: TextStyle(color: cs.error)),
          ),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: cs.error))),
        const SizedBox(height: 18),
        FilledButton(
          key: const ValueKey('job-part-save'),
          onPressed: _saving || (stock != null && _qtyValue > stock) ? null : _save,
          child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('บันทึก')),
        ),
      ],
    );
  }
}

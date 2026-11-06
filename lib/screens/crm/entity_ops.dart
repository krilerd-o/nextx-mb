import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/entity_modules.dart';
import '../../core/menu_access.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../services/file_open.dart';
import '../../widgets/dense_card_tile.dart';
import '../../widgets/fields/nx_entity_picker_sheet.dart';
import '../../widgets/fields/nx_lift_sheet.dart';
import '../../widgets/fields/nx_pick_option.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_surface_card.dart';
import '../calendar/activity_detail_screen.dart';
import '../deep_link_loaders.dart';
import '../workspace/workspace_board_screen.dart';
import 'entity_create_screen.dart';
import 'order_summary_screen.dart';
import '../../core/error_reporting.dart';

typedef OpenEntityFn = void Function(String module, String id, {Map<String, dynamic>? row});

class _RelatedSpec {
  const _RelatedSpec(this.module, this.fk);
  final String module;
  final String fk;
}

const _relatedByParent = <String, List<_RelatedSpec>>{
  'account': [
    _RelatedSpec('contact', 'account_id'),
    _RelatedSpec('deal', 'related_account_id'),
    _RelatedSpec('quotation', 'related_account_id'),
    _RelatedSpec('case', 'related_account_id'),
    _RelatedSpec('job', 'related_account_id'),
    _RelatedSpec('asset', 'related_account_id'),
    _RelatedSpec('service_contract', 'related_account_id'),
    _RelatedSpec('service_location', 'related_account_id'),
    _RelatedSpec('inspection', 'related_account_id'),
  ],
  'lead': [
    _RelatedSpec('deal', 'related_lead_id'),
    _RelatedSpec('quotation', 'related_lead_id'),
    _RelatedSpec('contact', 'related_lead_id'),
  ],
  'contact': [
    _RelatedSpec('deal', 'related_contact_id'),
    _RelatedSpec('quotation', 'related_contact_id'),
  ],
  'case': [
    _RelatedSpec('job', 'related_case_id'),
    _RelatedSpec('activity', 'related_case_id'),
  ],
  'job': [
    _RelatedSpec('inspection', 'related_job_id'),
    _RelatedSpec('activity', 'related_job_id'),
  ],
  'service_contract': [
    _RelatedSpec('asset', 'related_contract_id'),
    _RelatedSpec('job', 'related_contract_id'),
  ],
  'deal': [
    _RelatedSpec('quotation', 'related_deal_id'),
  ],
};

class EntityOpsSection extends StatelessWidget {
  const EntityOpsSection({
    super.key,
    required this.module,
    required this.id,
    required this.row,
    required this.onOpen,
    this.canEdit = true,
  });

  final String module;
  final String id;
  final Map<String, dynamic> row;
  final OpenEntityFn onOpen;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppConfig>().session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (module == 'quotation') ...[
          QuotationLinesPanel(id: id, canEdit: canEdit),
          const SizedBox(height: 12),
          QuotationConvertBar(id: id, onOpen: onOpen),
          const SizedBox(height: 12),
          QuotationMailApprovalBar(id: id, onOpen: onOpen),
        ],
        if (module == 'deal') ...[
          DealLinesPanel(id: id, canEdit: canEdit),
          const SizedBox(height: 12),
          DealContactsPanel(id: id, onOpen: onOpen, canEdit: canEdit),
          const SizedBox(height: 12),
          DealQuoteBar(id: id, onOpen: onOpen),
          const SizedBox(height: 12),
          DealPrimaryQuoteBar(id: id, onOpen: onOpen, canEdit: canEdit),
        ],
        if (module == 'lead') LeadConvertBar(id: id, row: row, onOpen: onOpen),
        if (module == 'inspection') InspectionLinesPanel(id: id, canEdit: canEdit),
        if (module == 'job') JobExtrasPanel(id: id, row: row, canEdit: canEdit, onOpen: onOpen),
        if (module == 'asset') AssetGenerateJobsBar(id: id, onOpen: onOpen),
        if (module == 'service_contract') ...[
          CreateJobFromParentBar(
            label: 'สร้างใบสั่งงานจากสัญญา',
            create: (api) => api.createJobFromContract(id),
            onOpen: onOpen,
          ),
          const SizedBox(height: 12),
          ContractMandayPanel(id: id, canEdit: canEdit),
        ],
        if (module == 'case') ...[
          CreateJobFromParentBar(
            label: 'สร้างใบสั่งงานจากเคส',
            create: (api) => api.createJobFromCase(id),
            onOpen: onOpen,
          ),
          const SizedBox(height: 12),
          CreateActivityFromCaseBar(id: id, onOpen: onOpen),
          const SizedBox(height: 12),
          CaseMandayPanel(id: id, canEdit: canEdit),
        ],
        if (module == 'account') ...[
          const SizedBox(height: 12),
          AccountMandayPanel(id: id, canEdit: canEdit),
        ],
        _RelatedHubPanel(
          module: module,
          id: id,
          onOpen: onOpen,
          canCreate: canEdit,
          fallback: [
            for (final spec in _relatedByParent[module] ?? const <_RelatedSpec>[])
              if (MenuAccess.allow(session, EntityModules.menuKeyOf(spec.module))) spec,
          ],
        ),
      ],
    );
  }
}

class QuotationLinesPanel extends StatefulWidget {
  const QuotationLinesPanel({
    super.key,
    required this.id,
    this.canEdit = true,
  });

  final String id;
  final bool canEdit;

  @override
  State<QuotationLinesPanel> createState() => _QuotationLinesPanelState();
}

class _QuotationLinesPanelState extends State<QuotationLinesPanel> {
  List<Map<String, dynamic>> _lines = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!context.read<AppConfig>().isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    try {
      final lines = await context.read<AppConfig>().apiClient.getQuotationLines(widget.id);
      if (mounted) setState(() => _lines = lines.map((e) => Map<String, dynamic>.from(e)).toList());
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = [
        for (var i = 0; i < _lines.length; i++)
          {
            'line_no': _lines[i]['line_no'] ?? i + 1,
            'line_type': _lines[i]['line_type'],
            'product_id': _lines[i]['product_id'],
            'service_id': _lines[i]['service_id'],
            'description': _lines[i]['description'] ?? _lines[i]['product_name'] ?? _lines[i]['name'],
            'quantity': _num(_lines[i]['quantity'] ?? _lines[i]['qty']),
            'unit': _lines[i]['unit'],
            'unit_price': _num(_lines[i]['unit_price']),
            'discount_pct': _num(_lines[i]['discount_pct']),
            'tax_pct': _num(_lines[i]['tax_pct']),
            'line_amount': _num(_lines[i]['line_amount'] ?? _lines[i]['amount']),
          },
      ];
      final saved = await context.read<AppConfig>().apiClient.putQuotationLines(widget.id, payload);
      if (mounted) {
        setState(() => _lines = saved.isEmpty ? _lines : saved.map((e) => Map<String, dynamic>.from(e)).toList());
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกบรรทัดแล้ว')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _LinesCard(
      title: 'บรรทัด',
      loading: _loading,
      saving: _saving,
      canEdit: widget.canEdit,
      empty: _lines.isEmpty,
      onAdd: widget.canEdit
          ? () => setState(() {
                _lines.add({
                  'line_no': _lines.length + 1,
                  'description': '',
                  'quantity': 1,
                  'unit_price': 0,
                });
              })
          : null,
      onSave: widget.canEdit ? _save : null,
      children: [
        for (var i = 0; i < _lines.length; i++)
          _QuoteLineEditor(
            line: _lines[i],
            canEdit: widget.canEdit,
            onChanged: (next) => setState(() => _lines[i] = next),
          ),
      ],
    );
  }
}

class _QuoteLineEditor extends StatelessWidget {
  const _QuoteLineEditor({
    required this.line,
    required this.canEdit,
    required this.onChanged,
  });

  final Map<String, dynamic> line;
  final bool canEdit;
  final ValueChanged<Map<String, dynamic>> onChanged;

  Future<void> _pickCatalog(BuildContext context, String module) async {
    final opt = await showNxEntityPickerSheet(
      context: context,
      title: module == 'service' ? 'เลือกบริการ' : 'เลือกสินค้า',
      search: (q) async {
        final page = await context.read<AppConfig>().apiClient.getEntityList(module, q: q, limit: 40);
        return [
          for (final row in page.items)
            NxPickOption(
              value: strId(row['id']),
              label: entityTitle(row, module: module),
            ),
        ];
      },
    );
    if (opt == null) return;
    if (module == 'service') {
      onChanged({
        ...line,
        'service_id': opt.value,
        'service_name': opt.label,
        'product_id': null,
        'description': (line['description']?.toString().trim().isNotEmpty == true) ? line['description'] : opt.label,
      });
    } else {
      onChanged({
        ...line,
        'product_id': opt.value,
        'product_name': opt.label,
        'service_id': null,
        'description': (line['description']?.toString().trim().isNotEmpty == true) ? line['description'] : opt.label,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = line['product_name']?.toString() ??
        line['service_name']?.toString() ??
        line['description']?.toString() ??
        line['name']?.toString() ??
        'รายการ';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NxSurfaceCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            if (canEdit)
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => _pickCatalog(context, 'product'),
                    icon: const Icon(NxI.package, size: 18),
                    label: const Text('เลือกสินค้า'),
                  ),
                  TextButton.icon(
                    onPressed: () => _pickCatalog(context, 'service'),
                    icon: const Icon(NxI.wrench, size: 18),
                    label: const Text('เลือกบริการ'),
                  ),
                ],
              ),
            TextFormField(
              enabled: canEdit,
              initialValue: line['description']?.toString() ?? title,
              decoration: const InputDecoration(labelText: 'รายละเอียด'),
              onChanged: (v) => onChanged({...line, 'description': v}),
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    enabled: canEdit,
                    initialValue: '${line['quantity'] ?? line['qty'] ?? ''}',
                    decoration: const InputDecoration(labelText: 'จำนวน'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => onChanged({...line, 'quantity': v, 'qty': v}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    enabled: canEdit,
                    initialValue: '${line['unit_price'] ?? ''}',
                    decoration: const InputDecoration(labelText: 'ราคา'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => onChanged({...line, 'unit_price': v}),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class QuotationConvertBar extends StatelessWidget {
  const QuotationConvertBar({super.key, required this.id, required this.onOpen});

  final String id;
  final OpenEntityFn onOpen;

  Future<void> _run(
    BuildContext context, {
    required String ok,
    required Future<Map<String, dynamic>> Function(ApiClient api) fn,
    required List<String> idKeys,
    required String module,
  }) async {
    try {
      final data = await fn(context.read<AppConfig>().apiClient);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      if (module.isNotEmpty) {
        final nextId = pickRecordId(data, idKeys);
        if (nextId.isNotEmpty) onOpen(module, nextId, row: data);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        NxHeroCta(
          label: 'แปลงเป็นออเดอร์',
          onPressed: () async {
            try {
              final data = await context.read<AppConfig>().apiClient.convertQuotationToOrder(id);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('แปลงเป็นออเดอร์แล้ว')));
              final orderId = pickRecordId(data, const ['commercial_order_id', 'order_id', 'id']);
              if (orderId.isNotEmpty) {
                nxPush<void>(context, OrderSummaryScreen(orderId: orderId, preview: data));
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
              }
            }
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _run(
            context,
            ok: 'แปลงเป็นสัญญาบริการแล้ว',
            fn: (api) => api.convertQuotationToContract(id),
            idKeys: const ['service_contract_id', 'contract_id'],
            module: 'service_contract',
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          ),
          child: const Text('แปลงเป็นสัญญาบริการ'),
        ),
      ],
    );
  }
}

class DealLinesPanel extends StatefulWidget {
  const DealLinesPanel({super.key, required this.id, this.canEdit = true});
  final String id;
  final bool canEdit;

  @override
  State<DealLinesPanel> createState() => _DealLinesPanelState();
}

class _DealLinesPanelState extends State<DealLinesPanel> {
  List<Map<String, dynamic>> _lines = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!context.read<AppConfig>().isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    try {
      final lines = await context.read<AppConfig>().apiClient.getDealLines(widget.id);
      if (mounted) setState(() => _lines = lines.map((e) => Map<String, dynamic>.from(e)).toList());
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = [
        for (final line in _lines)
          {
            'product_id': line['product_id'],
            'service_id': line['service_id'],
            'description': line['description'] ?? line['product_name'] ?? line['name'],
            'quantity': _num(line['quantity'] ?? line['qty']),
            'unit_price': _num(line['unit_price']),
          },
      ];
      final saved = await context.read<AppConfig>().apiClient.putDealLines(widget.id, payload);
      if (mounted) {
        setState(() => _lines = saved.isEmpty ? _lines : saved.map((e) => Map<String, dynamic>.from(e)).toList());
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกบรรทัดดีลแล้ว')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _LinesCard(
      title: 'บรรทัดสินค้า/บริการ',
      loading: _loading,
      saving: _saving,
      canEdit: widget.canEdit,
      empty: _lines.isEmpty,
      onAdd: widget.canEdit
          ? () => setState(() {
                _lines.add({'description': '', 'quantity': 1, 'unit_price': 0});
              })
          : null,
      onSave: widget.canEdit ? _save : null,
      children: [
        for (var i = 0; i < _lines.length; i++)
          _QuoteLineEditor(
            line: _lines[i],
            canEdit: widget.canEdit,
            onChanged: (next) => setState(() => _lines[i] = next),
          ),
      ],
    );
  }
}

class DealContactsPanel extends StatefulWidget {
  const DealContactsPanel({
    super.key,
    required this.id,
    required this.onOpen,
    this.canEdit = true,
  });
  final String id;
  final OpenEntityFn onOpen;
  final bool canEdit;

  @override
  State<DealContactsPanel> createState() => _DealContactsPanelState();
}

class _DealContactsPanelState extends State<DealContactsPanel> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!context.read<AppConfig>().isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    try {
      final items = await context.read<AppConfig>().apiClient.getDealContacts(widget.id);
      if (mounted) setState(() => _items = items);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add(BuildContext context) async {
    final opt = await showNxEntityPickerSheet(
      context: context,
      title: 'เลือกผู้ติดต่อ',
      search: (q) async {
        final page = await context.read<AppConfig>().apiClient.getEntityList('contact', q: q, limit: 40);
        return [
          for (final row in page.items)
            NxPickOption(value: strId(row['id']), label: entityTitle(row, module: 'contact')),
        ];
      },
    );
    if (opt == null || !mounted) return;
    try {
      final next = [
        for (final row in _items)
          {'contact_id': row['contact_id'] ?? row['id'], 'id': row['id']},
        {'contact_id': opt.value},
      ];
      final saved = await context.read<AppConfig>().apiClient.putDealContacts(widget.id, next);
      if (mounted) setState(() => _items = saved.isEmpty ? _items : saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _RelatedCard(
      title: 'ผู้ติดต่อที่เกี่ยวข้อง',
      loading: _loading,
      empty: _items.isEmpty,
      actions: widget.canEdit
          ? [TextButton.icon(onPressed: () => _add(context), icon: const Icon(NxI.plus), label: const Text('เพิ่ม'))]
          : const [],
      children: [
        for (final row in _items)
          DenseCardTile(
            title: entityTitle(row, module: 'contact'),
            subtitle: entitySubtitle(row, module: 'contact'),
            onTap: () {
              final id = strId(row['id'] ?? row['contact_id']);
              if (id.isNotEmpty) widget.onOpen('contact', id, row: row);
            },
          ),
      ],
    );
  }
}

class DealQuoteBar extends StatelessWidget {
  const DealQuoteBar({super.key, required this.id, required this.onOpen});
  final String id;
  final OpenEntityFn onOpen;

  @override
  Widget build(BuildContext context) {
    return NxHeroCta(
      label: 'สร้างใบเสนอราคาจากดีล',
      onPressed: () async {
        try {
          final data = await context.read<AppConfig>().apiClient.createDealQuotation(id);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สร้างใบเสนอราคาแล้ว')));
          final nextId = pickRecordId(data, const ['quotation_id', 'id']);
          if (nextId.isNotEmpty) onOpen('quotation', nextId, row: data);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
          }
        }
      },
    );
  }
}

class DealPrimaryQuoteBar extends StatefulWidget {
  const DealPrimaryQuoteBar({
    super.key,
    required this.id,
    required this.onOpen,
    this.canEdit = true,
  });
  final String id;
  final OpenEntityFn onOpen;
  final bool canEdit;

  @override
  State<DealPrimaryQuoteBar> createState() => _DealPrimaryQuoteBarState();
}

class _DealPrimaryQuoteBarState extends State<DealPrimaryQuoteBar> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!context.read<AppConfig>().isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    try {
      final items = await context.read<AppConfig>().apiClient.getDealQuotations(widget.id);
      if (mounted) setState(() => _items = items);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _RelatedCard(
      title: 'ใบเสนอของดีล',
      loading: _loading,
      empty: _items.isEmpty,
      children: [
        for (final row in _items)
          DenseCardTile(
            title: entityTitle(row, module: 'quotation'),
            subtitle: row['is_primary'] == true || row['primary'] == true ? 'ใบหลัก' : entitySubtitle(row, module: 'quotation'),
            onTap: () {
              final qid = strId(row['id'] ?? row['quotation_id']);
              if (qid.isNotEmpty) widget.onOpen('quotation', qid, row: row);
            },
            trailing: widget.canEdit
                ? TextButton(
                    onPressed: () async {
                      final qid = strId(row['id'] ?? row['quotation_id']);
                      if (qid.isEmpty) return;
                      try {
                        await context.read<AppConfig>().apiClient.setDealPrimaryQuotation(widget.id, qid);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ตั้งเป็นใบเสนอหลักแล้ว')));
                          _load();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
                        }
                      }
                    },
                    child: const Text('ตั้งหลัก'),
                  )
                : null,
          ),
      ],
    );
  }
}

class QuotationMailApprovalBar extends StatelessWidget {
  const QuotationMailApprovalBar({super.key, required this.id, required this.onOpen});
  final String id;
  final OpenEntityFn onOpen;

  Future<void> _email(BuildContext context) async {
    final to = TextEditingController();
    final message = TextEditingController();
    final ok = await showNxLiftSheet<bool>(
      context: context,
      builder: (ctx, scroll) {
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Text('ส่งอีเมลใบเสนอราคา', style: Theme.of(ctx).textTheme.titleMedium),
            TextField(controller: to, decoration: const InputDecoration(labelText: 'ถึง (อีเมล)')),
            TextField(controller: message, decoration: const InputDecoration(labelText: 'ข้อความ'), maxLines: 3),
            const SizedBox(height: 12),
            NxHeroCta(
              label: 'ส่ง',
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        );
      },
    );
    if (ok != true || !context.mounted) {
      to.dispose();
      message.dispose();
      return;
    }
    try {
      await context.read<AppConfig>().apiClient.sendQuotationEmail(id, to: to.text.trim(), message: message.text.trim());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ส่งอีเมลแล้ว')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    } finally {
      to.dispose();
      message.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        OutlinedButton(
          onPressed: () => _email(context),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('ส่งอีเมลใบเสนอราคา'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            try {
              await context.read<AppConfig>().apiClient.submitQuotationApproval(id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ส่งขออนุมัติแล้ว')));
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
              }
            }
          },
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('ส่งขออนุมัติ'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  try {
                    await context.read<AppConfig>().apiClient.approveQuotation(id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('อนุมัติแล้ว')));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
                    }
                  }
                },
                child: const Text('อนุมัติ'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  try {
                    await context.read<AppConfig>().apiClient.rejectQuotation(id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ปฏิเสธแล้ว')));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
                    }
                  }
                },
                child: const Text('ปฏิเสธ'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            try {
              final data = await context.read<AppConfig>().apiClient.reviseQuotation(id);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สร้างฉบับแก้ไขแล้ว')));
              final nextId = pickRecordId(data, const ['quotation_id', 'id', 'new_id']);
              if (nextId.isNotEmpty) onOpen('quotation', nextId, row: data);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
              }
            }
          },
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('สร้างฉบับแก้ไข'),
        ),
      ],
    );
  }
}

class LeadConvertBar extends StatelessWidget {
  const LeadConvertBar({
    super.key,
    required this.id,
    required this.row,
    required this.onOpen,
  });

  final String id;
  final Map<String, dynamic> row;
  final OpenEntityFn onOpen;

  bool get _converted {
    final status = (row['lead_status'] ?? row['status'] ?? '').toString().toLowerCase();
    return status.contains('convert') ||
        row['convert_account_id'] != null ||
        row['convert_contact_id'] != null;
  }

  Future<void> _openPreview(BuildContext context) async {
    Map<String, dynamic> preview = {};
    try {
      preview = await context.read<AppConfig>().apiClient.previewLeadConvert(id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
      return;
    }
    if (!context.mounted) return;
    final host = context;
    var createContact = preview['can_convert_contact'] != false;
    var createAccount = preview['can_convert_account'] != false;
    var createDeal = true;
    var copyHistory = true;
    String? linkAccountId;
    String? linkContactId;
    final defaults = asStringKeyedMap(preview['form_defaults']) ?? {};
    final dup = asStringKeyedMap(preview['duplicates']) ?? {};
    final dupAccounts = extractMapList(dup['accounts']);
    final dupContacts = extractMapList(dup['contacts']);
    await showNxLiftSheet<void>(
      context: host,
      builder: (ctx, scroll) {
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Text('แปลงลีด', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(preview['lead_name']?.toString() ?? entityTitle(row, module: 'lead')),
            if (defaults['account_name'] != null) Text('บัญชี: ${defaults['account_name']}'),
            if (defaults['contact_firstname'] != null || defaults['contact_lastname'] != null)
              Text('ผู้ติดต่อ: ${defaults['contact_firstname'] ?? ''} ${defaults['contact_lastname'] ?? ''}'),
            const SizedBox(height: 8),
            StatefulBuilder(
              builder: (context, setLocal) {
                return Column(
                  children: [
                    SwitchListTile(
                      title: const Text('สร้างบัญชีลูกค้า'),
                      value: createAccount,
                      onChanged: (v) => setLocal(() {
                        createAccount = v;
                        if (v) linkAccountId = null;
                      }),
                    ),
                    SwitchListTile(
                      title: const Text('สร้างผู้ติดต่อ'),
                      value: createContact,
                      onChanged: (v) => setLocal(() {
                        createContact = v;
                        if (v) linkContactId = null;
                      }),
                    ),
                    SwitchListTile(
                      title: const Text('สร้างดีล'),
                      value: createDeal,
                      onChanged: (v) => setLocal(() => createDeal = v),
                    ),
                    SwitchListTile(
                      title: const Text('คัดลอกประวัติ'),
                      value: copyHistory,
                      onChanged: (v) => setLocal(() => copyHistory = v),
                    ),
                    if (dupAccounts.isNotEmpty) ...[
                      const Align(alignment: Alignment.centerLeft, child: Text('บัญชีที่อาจซ้ำ')),
                      for (final a in dupAccounts)
                        RadioListTile<String>(
                          title: Text(entityTitle(a, module: 'account')),
                          value: strId(a['id']),
                          groupValue: linkAccountId,
                          onChanged: (v) => setLocal(() {
                            linkAccountId = v;
                            createAccount = false;
                          }),
                        ),
                    ],
                    if (dupContacts.isNotEmpty) ...[
                      const Align(alignment: Alignment.centerLeft, child: Text('ผู้ติดต่อที่อาจซ้ำ')),
                      for (final c in dupContacts)
                        RadioListTile<String>(
                          title: Text(entityTitle(c, module: 'contact')),
                          value: strId(c['id']),
                          groupValue: linkContactId,
                          onChanged: (v) => setLocal(() {
                            linkContactId = v;
                            createContact = false;
                          }),
                        ),
                    ],
                    NxHeroCta(
                      label: 'แปลง',
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _convert(
                          host,
                          createAccount: createAccount,
                          createContact: createContact,
                          createDeal: createDeal,
                          copyHistory: copyHistory,
                          existingAccountId: linkAccountId,
                          existingContactId: linkContactId,
                          defaults: defaults,
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _convert(
    BuildContext context, {
    required bool createAccount,
    required bool createContact,
    required bool createDeal,
    required bool copyHistory,
    String? existingAccountId,
    String? existingContactId,
    required Map<String, dynamic> defaults,
  }) async {
    try {
      final data = await context.read<AppConfig>().apiClient.convertLead(id, {
        'create_account': createAccount || (existingAccountId != null && existingAccountId.isNotEmpty),
        'create_contact': createContact || (existingContactId != null && existingContactId.isNotEmpty),
        'create_deal': createDeal,
        'copy_history': copyHistory,
        if (existingAccountId != null && existingAccountId.isNotEmpty) 'existing_account_id': existingAccountId,
        if (existingContactId != null && existingContactId.isNotEmpty) 'existing_contact_id': existingContactId,
        ...defaults,
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('แปลงลีดแล้ว')));
      final accountId = pickRecordId(data, const ['account_id']);
      final contactId = pickRecordId(data, const ['contact_id']);
      final dealId = pickRecordId(data, const ['deal_id']);
      await showNxLiftSheet<void>(
        context: context,
        builder: (ctx, scroll) {
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Text('เปิดรายการที่แปลงแล้ว', style: Theme.of(ctx).textTheme.titleMedium),
              if (accountId.isNotEmpty)
                DenseCardTile(
                  title: 'บัญชีลูกค้า',
                  onTap: () {
                    Navigator.pop(ctx);
                    onOpen('account', accountId, row: data);
                  },
                ),
              if (contactId.isNotEmpty)
                DenseCardTile(
                  title: 'ผู้ติดต่อ',
                  onTap: () {
                    Navigator.pop(ctx);
                    onOpen('contact', contactId, row: data);
                  },
                ),
              if (dealId.isNotEmpty)
                DenseCardTile(
                  title: 'ดีล',
                  onTap: () {
                    Navigator.pop(ctx);
                    onOpen('deal', dealId, row: data);
                  },
                ),
            ],
          );
        },
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_converted) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('ลีดนี้แปลงแล้ว', style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    return NxHeroCta(label: 'แปลงลีด', onPressed: () => _openPreview(context));
  }
}

class InspectionLinesPanel extends StatefulWidget {
  const InspectionLinesPanel({super.key, required this.id, this.canEdit = true});
  final String id;
  final bool canEdit;

  @override
  State<InspectionLinesPanel> createState() => _InspectionLinesPanelState();
}

class _InspectionLinesPanelState extends State<InspectionLinesPanel> {
  List<Map<String, dynamic>> _lines = [];
  bool _loading = true;
  bool _saving = false;

  String _inspectionResult(Map<String, dynamic> line) {
    final v = (line['item_result'] ?? line['result'] ?? line['status'] ?? '').toString();
    if (v == 'pass' || v == 'fail' || v == 'na') return v;
    return '';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!context.read<AppConfig>().isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    try {
      final lines = await context.read<AppConfig>().apiClient.getInspectionLines(widget.id);
      if (mounted) setState(() => _lines = lines.map((e) => Map<String, dynamic>.from(e)).toList());
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = [
        for (var i = 0; i < _lines.length; i++)
          {
            'line_no': _lines[i]['line_no'] ?? i + 1,
            'item_label': _lines[i]['item_label'] ?? _lines[i]['label'],
            'item_result': _lines[i]['item_result'] ?? _lines[i]['result'] ?? _lines[i]['status'],
            'result': _lines[i]['result'] ?? _lines[i]['item_result'],
            'remark': _lines[i]['remark'],
            'sort_order': _lines[i]['sort_order'] ?? i + 1,
          },
      ];
      final saved = await context.read<AppConfig>().apiClient.putInspectionLines(widget.id, payload);
      if (mounted) {
        setState(() => _lines = saved.isEmpty ? _lines : saved.map((e) => Map<String, dynamic>.from(e)).toList());
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกผลตรวจแล้ว')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _LinesCard(
      title: 'บรรทัดตรวจรับ',
      loading: _loading,
      saving: _saving,
      canEdit: widget.canEdit,
      empty: _lines.isEmpty,
      onAdd: widget.canEdit
          ? () => setState(() {
                _lines.add({'item_label': 'รายการใหม่', 'item_result': '', 'remark': ''});
              })
          : null,
      onSave: widget.canEdit ? _save : null,
      extra: OutlinedButton(
        onPressed: () async {
          try {
            final bytes = await context.read<AppConfig>().apiClient.getInspectionPdf(widget.id);
            await openPdfBytes(bytes, 'inspection-${widget.id}.pdf');
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
            }
          }
        },
        child: const Text('เปิด PDF'),
      ),
      children: [
        for (var i = 0; i < _lines.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: NxSurfaceCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    enabled: widget.canEdit,
                    initialValue: _lines[i]['item_label']?.toString() ?? _lines[i]['label']?.toString() ?? '',
                    decoration: const InputDecoration(labelText: 'รายการ'),
                    onChanged: (v) => _lines[i]['item_label'] = v,
                  ),
                  DropdownButtonFormField<String>(
                    value: _inspectionResult(_lines[i]),
                    decoration: const InputDecoration(labelText: 'ผลตรวจ'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('—')),
                      DropdownMenuItem(value: 'pass', child: Text('Pass')),
                      DropdownMenuItem(value: 'fail', child: Text('Fail')),
                      DropdownMenuItem(value: 'na', child: Text('N/A')),
                    ],
                    onChanged: widget.canEdit
                        ? (v) => setState(() {
                              _lines[i]['item_result'] = v;
                              _lines[i]['result'] = v;
                            })
                        : null,
                  ),
                  TextFormField(
                    enabled: widget.canEdit,
                    initialValue: _lines[i]['remark']?.toString() ?? '',
                    decoration: const InputDecoration(labelText: 'หมายเหตุ'),
                    onChanged: (v) => _lines[i]['remark'] = v,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class JobExtrasPanel extends StatefulWidget {
  const JobExtrasPanel({
    super.key,
    required this.id,
    required this.row,
    required this.onOpen,
    this.canEdit = true,
  });

  final String id;
  final Map<String, dynamic> row;
  final OpenEntityFn onOpen;
  final bool canEdit;

  @override
  State<JobExtrasPanel> createState() => _JobExtrasPanelState();
}

class _JobExtrasPanelState extends State<JobExtrasPanel> {
  List<Map<String, dynamic>> _skills = [];
  List<Map<String, dynamic>> _catalog = [];
  List<Map<String, dynamic>> _parts = [];
  List<Map<String, dynamic>> _matches = [];
  List<Map<String, dynamic>> _workspace = [];
  Map<String, dynamic> _sla = {};
  String? _mismatch;
  bool _loading = true;
  bool _busy = false;

  Set<String> get _skillIds => {
        for (final s in _skills) strId(s['skill_id'] ?? s['id']),
      }.where((e) => e.isNotEmpty).toSet();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!context.read<AppConfig>().isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    final api = context.read<AppConfig>().apiClient;
    try {
      final skills = await api.getJobSkills(widget.id);
      var catalog = <Map<String, dynamic>>[];
      try {
        catalog = (await api.getEntityList('skill', limit: 80)).items;
      } catch (e, s) {
      ErrorReporting.report(e, s);
    }
      final parts = await api.getJobParts(widget.id);
      Map<String, dynamic> sla = {};
      try {
        sla = await api.getJobSla(widget.id);
      } catch (e, s) {
      ErrorReporting.report(e, s);
    }
      var workspace = <Map<String, dynamic>>[];
      try {
        workspace = await api.getJobWorkspaceItems(widget.id);
      } catch (e, s) {
      ErrorReporting.report(e, s);
    }
      if (mounted) {
        setState(() {
          _skills = skills;
          _catalog = catalog;
          _parts = parts;
          _sla = sla;
          _workspace = workspace;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSkills(Set<String> ids) async {
    setState(() => _busy = true);
    try {
      final saved = await context.read<AppConfig>().apiClient.setJobSkills(widget.id, ids.toList());
      if (mounted) setState(() => _skills = saved.isEmpty ? _skills : saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('งานสนาม', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_sla.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  _sla['overdue'] == true || _sla['is_overdue'] == true
                      ? 'SLA เกินกำหนด${_sla['message'] != null ? ' · ${_sla['message']}' : ''}'
                      : (_sla['remaining_text'] ?? _sla['message'] ?? _sla['status'] ?? 'SLA').toString(),
                ),
              ),
            ),
          ),
        if (_mismatch != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_mismatch!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  final bytes = await context.read<AppConfig>().apiClient.downloadJobPdf(widget.id);
                  await openPdfBytes(bytes, 'job-${widget.id}.pdf');
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
                  }
                }
              },
              icon: const Icon(NxI.filePdf),
              label: const Text('PDF ใบสั่งงาน'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _schedule(context),
              icon: const Icon(NxI.calendarBlank),
              label: const Text('นัดหมาย'),
            ),
            if (strId(widget.row['related_activity_id']).isNotEmpty)
              OutlinedButton.icon(
                onPressed: () {
                  nxPush<void>(
                    context,
                    ActivityDetailScreen(row: {'id': strId(widget.row['related_activity_id'])}),
                  );
                },
                icon: const Icon(NxI.clock),
                label: const Text('เช็คอิน'),
              ),
            if (_workspace.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () {
                  final item = _workspace.first;
                  final boardId = strId(item['board_id'] ?? item['related_board_id']);
                  if (boardId.isEmpty) return;
                  nxPush<void>(context, WorkspaceBoardScreen(board: {'id': boardId, 'name': item['board_name'] ?? 'บอร์ด'}));
                },
                icon: const Icon(NxI.kanban),
                label: const Text('เปิดบอร์ด'),
              ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        final data = await context.read<AppConfig>().apiClient.matchJobUsers(widget.id);
                        if (mounted) setState(() => _matches = extractMapList(data));
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: const Text('ช่างที่ตรงทักษะ'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Text('ทักษะงาน', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final skill in _catalog)
              FilterChip(
                label: Text(entityTitle(skill, module: 'skill')),
                selected: _skillIds.contains(strId(skill['id'])),
                onSelected: widget.canEdit && !_busy
                    ? (on) {
                        final next = {..._skillIds};
                        final sid = strId(skill['id']);
                        if (on) {
                          next.add(sid);
                        } else {
                          next.remove(sid);
                        }
                        _saveSkills(next);
                      }
                    : null,
              ),
            if (_catalog.isEmpty && _skills.isNotEmpty)
              for (final s in _skills)
                Chip(label: Text(s['skill_name']?.toString() ?? s['skill_code']?.toString() ?? 'ทักษะ')),
          ],
        ),
        if (_matches.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final u in _matches)
            DenseCardTile(
              title: u['display_name']?.toString() ?? u['name']?.toString() ?? 'ผู้ใช้',
              subtitle: u['email']?.toString(),
              onTap: widget.canEdit ? () => _assign(u) : null,
            ),
        ],
        const SizedBox(height: 12),
        Text('อะไหล่', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_parts.isEmpty)
          Text('ยังไม่มีอะไหล่', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        for (final part in _parts)
          DenseCardTile(
            title: part['description']?.toString() ?? part['product_name']?.toString() ?? 'อะไหล่',
            subtitle: 'จำนวน ${part['quantity'] ?? part['qty'] ?? 1}',
            trailing: widget.canEdit
                ? IconButton(
                    icon: const Icon(NxI.trash),
                    onPressed: () async {
                      final partId = strId(part['id']);
                      if (partId.isEmpty) return;
                      try {
                        await context.read<AppConfig>().apiClient.deleteJobPart(widget.id, partId);
                        await _load();
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
                      }
                    },
                  )
                : null,
          ),
        if (widget.canEdit)
          TextButton.icon(
            onPressed: () => _addPart(context),
            icon: const Icon(NxI.plus),
            label: const Text('เพิ่มอะไหล่'),
          ),
      ],
    );
  }

  Future<void> _schedule(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null || !context.mounted) return;
    final when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => _busy = true);
    try {
      final data = await context.read<AppConfig>().apiClient.scheduleJob(widget.id, when: when.toIso8601String());
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สร้างนัดหมายแล้ว')));
      final actId = pickRecordId(data, const ['activity_id', 'related_activity_id']);
      if (actId.isNotEmpty) {
        nxPush<void>(context, ActivityByIdLoader(id: actId));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assign(Map<String, dynamic> user) async {
    final uid = strId(user['id'] ?? user['user_id'] ?? user['smownerid']);
    if (uid.isEmpty) return;
    setState(() => _busy = true);
    try {
      final api = context.read<AppConfig>().apiClient;
      await api.putEntity('job', widget.id, {'smownerid': int.tryParse(uid) ?? uid});
      try {
        final mm = await api.getJobSkillMismatch(widget.id, userId: uid);
        if (mounted) {
          final warn = mm['mismatch'] == true || mm['has_mismatch'] == true || mm['warning'] != null;
          setState(() => _mismatch = warn ? (mm['message'] ?? mm['warning'] ?? 'ทักษะไม่ตรงทั้งหมด').toString() : null);
        }
      } catch (e, s) {
      ErrorReporting.report(e, s);
    }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('มอบหมายให้ ${user['display_name'] ?? user['name'] ?? uid}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPart(BuildContext context) async {
    final desc = TextEditingController();
    final qty = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เพิ่มอะไหล่'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: desc, decoration: const InputDecoration(labelText: 'รายละเอียด')),
            TextField(
              controller: qty,
              decoration: const InputDecoration(labelText: 'จำนวน'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('บันทึก')),
        ],
      ),
    );
    if (ok != true || !context.mounted) {
      desc.dispose();
      qty.dispose();
      return;
    }
    try {
      await context.read<AppConfig>().apiClient.addJobPart(widget.id, {
        'description': desc.text.trim(),
        'quantity': num.tryParse(qty.text.trim()) ?? 1,
      });
      await _load();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    } finally {
      desc.dispose();
      qty.dispose();
    }
  }
}

class AssetGenerateJobsBar extends StatelessWidget {
  const AssetGenerateJobsBar({super.key, required this.id, required this.onOpen});
  final String id;
  final OpenEntityFn onOpen;

  @override
  Widget build(BuildContext context) {
    return NxHeroCta(
      label: 'สร้างใบสั่งงานจากสินทรัพย์',
      onPressed: () async {
        try {
          final data = await context.read<AppConfig>().apiClient.generateJobsFromAsset(id);
          if (!context.mounted) return;
          final created = extractMapList(data['created'] ?? data);
          final count = data['count'] ?? created.length;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('สร้างใบสั่งงาน $count รายการ')));
          if (created.isEmpty) return;
          await showNxLiftSheet<void>(
            context: context,
            builder: (ctx, scroll) {
              return ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  Text('งานที่สร้าง', style: Theme.of(ctx).textTheme.titleMedium),
                  for (final job in created)
                    DenseCardTile(
                      title: entityTitle(job, module: 'job'),
                      onTap: () {
                        Navigator.pop(ctx);
                        final jobId = pickRecordId(job, const ['job_id', 'id']);
                        if (jobId.isNotEmpty) onOpen('job', jobId, row: job);
                      },
                    ),
                ],
              );
            },
          );
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
          }
        }
      },
    );
  }
}

class CreateJobFromParentBar extends StatelessWidget {
  const CreateJobFromParentBar({
    super.key,
    required this.label,
    required this.create,
    required this.onOpen,
  });

  final String label;
  final Future<Map<String, dynamic>> Function(ApiClient api) create;
  final OpenEntityFn onOpen;

  @override
  Widget build(BuildContext context) {
    return NxHeroCta(
      label: label,
      onPressed: () async {
        try {
          final data = await create(context.read<AppConfig>().apiClient);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$labelแล้ว')));
          final jobId = pickRecordId(data, const ['job_id', 'id']);
          if (jobId.isNotEmpty) onOpen('job', jobId, row: data);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
          }
        }
      },
    );
  }
}

class ContractMandayPanel extends StatefulWidget {
  const ContractMandayPanel({super.key, required this.id, this.canEdit = true});
  final String id;
  final bool canEdit;

  @override
  State<ContractMandayPanel> createState() => _ContractMandayPanelState();
}

class _ContractMandayPanelState extends State<ContractMandayPanel> {
  Map<String, dynamic> _ledger = {};
  bool _loading = true;

  List<Map<String, dynamic>> get _rows => extractMapList(_ledger);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!context.read<AppConfig>().isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    try {
      final data = await context.read<AppConfig>().apiClient.getContractMandayLedger(widget.id);
      if (mounted) setState(() => _ledger = data);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final qty = TextEditingController(text: '1');
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เพิ่ม manday'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qty,
              decoration: const InputDecoration(labelText: 'จำนวน'),
              keyboardType: TextInputType.number,
            ),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'หมายเหตุ')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('บันทึก')),
        ],
      ),
    );
    if (ok != true || !mounted) {
      qty.dispose();
      note.dispose();
      return;
    }
    try {
      await context.read<AppConfig>().apiClient.addContractManday(widget.id, {
        'qty': num.tryParse(qty.text.trim()) ?? 1,
        'note': note.text.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    } finally {
      qty.dispose();
      note.dispose();
    }
  }

  Future<void> _adjust() async {
    final qty = TextEditingController(text: '1');
    final note = TextEditingController();
    var direction = 'debit';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ปรับ manday'),
        content: StatefulBuilder(
          builder: (context, setLocal) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: direction,
                  items: const [
                    DropdownMenuItem(value: 'debit', child: Text('หัก')),
                    DropdownMenuItem(value: 'credit', child: Text('เพิ่ม')),
                  ],
                  onChanged: (v) => setLocal(() => direction = v ?? 'debit'),
                ),
                TextField(
                  controller: qty,
                  decoration: const InputDecoration(labelText: 'จำนวน'),
                  keyboardType: TextInputType.number,
                ),
                TextField(controller: note, decoration: const InputDecoration(labelText: 'หมายเหตุ')),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('บันทึก')),
        ],
      ),
    );
    if (ok != true || !mounted) {
      qty.dispose();
      note.dispose();
      return;
    }
    try {
      await context.read<AppConfig>().apiClient.adjustContractManday(widget.id, {
        'qty': num.tryParse(qty.text.trim()) ?? 1,
        'direction': direction,
        'note': note.text.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    } finally {
      qty.dispose();
      note.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final remain = _ledger['md_remain_hours'];
    return _RelatedCard(
      title: 'สมุด manday',
      loading: _loading,
      empty: _rows.isEmpty,
      trailing: remain != null ? Text('คงเหลือ $remain ชม.') : null,
      actions: widget.canEdit
          ? [
              TextButton(onPressed: _add, child: const Text('เพิ่ม')),
              TextButton(onPressed: _adjust, child: const Text('ปรับ')),
            ]
          : const [],
      children: [
        for (final row in _rows)
          DenseCardTile(
            title: row['entry_kind']?.toString() ?? row['note']?.toString() ?? 'รายการ',
            subtitle: [
              row['hours'],
              row['manday_qty'],
              row['note'],
            ].where((e) => e != null && e.toString().isNotEmpty).join(' · '),
          ),
      ],
    );
  }
}

class CaseMandayPanel extends StatefulWidget {
  const CaseMandayPanel({super.key, required this.id, this.canEdit = true});
  final String id;
  final bool canEdit;

  @override
  State<CaseMandayPanel> createState() => _CaseMandayPanelState();
}

class _CaseMandayPanelState extends State<CaseMandayPanel> {
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!context.read<AppConfig>().isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    final api = context.read<AppConfig>().apiClient;
    try {
      final summary = await api.getCaseMandaySummary(widget.id);
      var requests = <Map<String, dynamic>>[];
      try {
        requests = await api.getCaseMandayRequests(widget.id);
      } catch (e, s) {
      ErrorReporting.report(e, s);
    }
      if (mounted) {
        setState(() {
          _summary = summary;
          _requests = requests;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _request() async {
    final qty = TextEditingController(text: '1');
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ขอ manday'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qty,
              decoration: const InputDecoration(labelText: 'จำนวน'),
              keyboardType: TextInputType.number,
            ),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'หมายเหตุ')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ส่ง')),
        ],
      ),
    );
    if (ok != true || !mounted) {
      qty.dispose();
      note.dispose();
      return;
    }
    try {
      await context.read<AppConfig>().apiClient.postCaseMandayRequest(widget.id, {
        'qty': num.tryParse(qty.text.trim()) ?? 1,
        'note': note.text.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    } finally {
      qty.dispose();
      note.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _RelatedCard(
      title: 'Manday ของเคส',
      loading: _loading,
      empty: _summary.isEmpty && _requests.isEmpty,
      trailing: _summary['remain_hours'] != null || _summary['md_remain_hours'] != null
          ? Text('คงเหลือ ${_summary['remain_hours'] ?? _summary['md_remain_hours']} ชม.')
          : null,
      actions: widget.canEdit ? [TextButton(onPressed: _request, child: const Text('ขอ manday'))] : const [],
      children: [
        if (_summary.isNotEmpty)
          DenseCardTile(
            title: 'สรุป',
            subtitle: _summary.entries
                .where((e) => e.value != null && e.value is! List && e.value is! Map)
                .take(4)
                .map((e) => '${e.key}: ${e.value}')
                .join(' · '),
          ),
        for (final req in _requests)
          DenseCardTile(
            title: req['status']?.toString() ?? 'คำขอ',
            subtitle: [
              req['qty'] ?? req['manday_qty'],
              req['note'],
            ].where((e) => e != null).join(' · '),
            trailing: widget.canEdit
                ? Wrap(
                    children: [
                      TextButton(
                        onPressed: () async {
                          final rid = strId(req['id']);
                          if (rid.isEmpty) return;
                          try {
                            await context.read<AppConfig>().apiClient.approveMandayRequest(rid);
                            await _load();
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
                            }
                          }
                        },
                        child: const Text('อนุมัติ'),
                      ),
                      TextButton(
                        onPressed: () async {
                          final rid = strId(req['id']);
                          if (rid.isEmpty) return;
                          try {
                            await context.read<AppConfig>().apiClient.rejectMandayRequest(rid);
                            await _load();
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
                            }
                          }
                        },
                        child: const Text('ปฏิเสธ'),
                      ),
                      TextButton(
                        onPressed: () async {
                          final rid = strId(req['id']);
                          if (rid.isEmpty) return;
                          try {
                            await context.read<AppConfig>().apiClient.cancelMandayRequest(rid);
                            await _load();
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
                            }
                          }
                        },
                        child: const Text('ยกเลิก'),
                      ),
                    ],
                  )
                : null,
          ),
      ],
    );
  }
}

class CreateActivityFromCaseBar extends StatelessWidget {
  const CreateActivityFromCaseBar({super.key, required this.id, required this.onOpen});
  final String id;
  final OpenEntityFn onOpen;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final saved = await nxPush<bool>(
          context,
          EntityCreateScreen(
            module: 'activity',
            title: 'สร้างนัดหมายจากเคส',
            initialValues: {'related_case_id': id},
          ),
        );
        if (saved == true && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สร้างนัดหมายแล้ว')));
        }
      },
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: const Text('สร้างนัดหมายจากเคส'),
    );
  }
}

class AccountMandayPanel extends StatefulWidget {
  const AccountMandayPanel({super.key, required this.id, this.canEdit = true});
  final String id;
  final bool canEdit;

  @override
  State<AccountMandayPanel> createState() => _AccountMandayPanelState();
}

class _AccountMandayPanelState extends State<AccountMandayPanel> {
  Map<String, dynamic> _summary = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!context.read<AppConfig>().isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    try {
      final data = await context.read<AppConfig>().apiClient.getAccountMandaySummary(widget.id);
      if (mounted) setState(() => _summary = data);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final qty = TextEditingController(text: '1');
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เพิ่มพูล manday'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: qty, decoration: const InputDecoration(labelText: 'จำนวน'), keyboardType: TextInputType.number),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'หมายเหตุ')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('บันทึก')),
        ],
      ),
    );
    if (ok != true || !mounted) {
      qty.dispose();
      note.dispose();
      return;
    }
    try {
      await context.read<AppConfig>().apiClient.addAccountManday(widget.id, {
        'qty': num.tryParse(qty.text.trim()) ?? 1,
        'note': note.text.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    } finally {
      qty.dispose();
      note.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _RelatedCard(
      title: 'พูล manday ของบัญชี',
      loading: _loading,
      empty: _summary.isEmpty,
      trailing: _summary['remain_hours'] != null || _summary['md_remain_hours'] != null
          ? Text('คงเหลือ ${_summary['remain_hours'] ?? _summary['md_remain_hours']} ชม.')
          : null,
      actions: widget.canEdit ? [TextButton(onPressed: _add, child: const Text('เพิ่ม'))] : const [],
      children: [
        if (_summary.isNotEmpty)
          DenseCardTile(
            title: 'สรุปพูล',
            subtitle: _summary.entries
                .where((e) => e.value != null && e.value is! List && e.value is! Map)
                .take(4)
                .map((e) => '${e.key}: ${e.value}')
                .join(' · '),
          ),
      ],
    );
  }
}

class _RelatedHubPanel extends StatefulWidget {
  const _RelatedHubPanel({
    required this.module,
    required this.id,
    required this.onOpen,
    required this.fallback,
    this.canCreate = true,
  });

  final String module;
  final String id;
  final OpenEntityFn onOpen;
  final List<_RelatedSpec> fallback;
  final bool canCreate;

  @override
  State<_RelatedHubPanel> createState() => _RelatedHubPanelState();
}

class _RelatedHubPanelState extends State<_RelatedHubPanel> {
  List<Map<String, dynamic>> _groups = [];
  bool _loading = true;
  bool _fromApi = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!context.read<AppConfig>().isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    try {
      final data = await context.read<AppConfig>().apiClient.getEntityRelated(widget.module, widget.id);
      var groups = extractMapList(data['groups']);
      if (groups.isEmpty) groups = _legacyGroups(data);
      if (mounted) {
        setState(() {
          _groups = groups;
          _fromApi = groups.isNotEmpty;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _legacyGroups(Map<String, dynamic> data) {
    final out = <Map<String, dynamic>>[];
    void add(String module, dynamic raw, String title) {
      final items = extractMapList(raw);
      if (raw is Map && items.isEmpty && (raw['id'] != null)) {
        out.add({
          'key': module,
          'label_th': title,
          'items': [
            {'id': raw['id'], 'module': module, 'title': entityTitle(Map<String, dynamic>.from(raw), module: module)},
          ],
        });
        return;
      }
      if (items.isEmpty) return;
      out.add({
        'key': module,
        'label_th': title,
        'items': [
          for (final row in items)
            {
              'id': row['id'],
              'module': module,
              'title': entityTitle(row, module: module),
              'subtitle': entitySubtitle(row, module: module),
            },
        ],
      });
    }

    add('account', data['account'] ?? data['accounts'], 'บัญชีลูกค้า');
    add('contact', data['contacts'], 'ผู้ติดต่อ');
    add('deal', data['deals'], 'ดีล');
    add('quotation', data['quotations'], 'ใบเสนอราคา');
    add('job', data['jobs'], 'ใบสั่งงาน');
    add('activity', data['activities'] ?? data['work'], 'นัดหมาย');
    add('service_location', data['locations'], 'พื้นที่บริการ');
    add('inspection', data['inspections'], 'ใบตรวจรับ');
    return out;
  }

  String _moduleOf(Map<String, dynamic> group, Map<String, dynamic> item) {
    final m = item['module']?.toString() ?? group['module']?.toString() ?? group['key']?.toString() ?? '';
    switch (m) {
      case 'accounts':
        return 'account';
      case 'contacts':
        return 'contact';
      case 'deals':
        return 'deal';
      case 'quotations':
        return 'quotation';
      case 'jobs':
        return 'job';
      case 'inspections':
        return 'inspection';
      case 'locations':
      case 'service_locations':
        return 'service_location';
      case 'contracts':
        return 'service_contract';
      case 'assets':
        return 'asset';
      case 'work':
      case 'activities':
        return 'activity';
      case 'leads':
        return 'lead';
      default:
        return EntityModules.normalize(m);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator(minHeight: 2));
    if (_fromApi) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final g in _groups) ...[
            const SizedBox(height: 12),
            _RelatedCard(
              title: g['label_th']?.toString() ?? g['label']?.toString() ?? g['key']?.toString() ?? 'ที่เกี่ยวข้อง',
              loading: false,
              empty: extractMapList(g['items']).isEmpty,
              children: [
                for (final item in extractMapList(g['items']))
                  DenseCardTile(
                    title: item['title']?.toString() ?? entityTitle(item, module: _moduleOf(g, item)),
                    subtitle: item['subtitle']?.toString(),
                    onTap: () {
                      final module = _moduleOf(g, item);
                      final id = strId(item['id']);
                      if (id.isEmpty || module.isEmpty) return;
                      if (module == 'activity') {
                        nxPush<void>(context, ActivityByIdLoader(id: id));
                        return;
                      }
                      widget.onOpen(module, id, row: item);
                    },
                  ),
              ],
            ),
          ],
        ],
      );
    }
    return Column(
      children: [
        for (final spec in widget.fallback) ...[
          const SizedBox(height: 12),
          _RelatedRecordsPanel(
            parentId: widget.id,
            spec: spec,
            onOpen: widget.onOpen,
            canCreate: widget.canCreate,
          ),
        ],
      ],
    );
  }
}

class _RelatedRecordsPanel extends StatefulWidget {
  const _RelatedRecordsPanel({
    required this.parentId,
    required this.spec,
    required this.onOpen,
    this.canCreate = true,
  });

  final String parentId;
  final _RelatedSpec spec;
  final OpenEntityFn onOpen;
  final bool canCreate;

  @override
  State<_RelatedRecordsPanel> createState() => _RelatedRecordsPanelState();
}

class _RelatedRecordsPanelState extends State<_RelatedRecordsPanel> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!context.read<AppConfig>().isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    try {
      final page = await context.read<AppConfig>().apiClient.getEntityList(
            widget.spec.module,
            limit: 12,
            extra: {widget.spec.fk: widget.parentId},
          );
      if (mounted) setState(() => _items = page.items);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final saved = await nxPush<bool>(
      context,
      EntityCreateScreen(
        module: widget.spec.module,
        title: 'สร้าง${EntityModules.titleOf(widget.spec.module)}',
        initialValues: {widget.spec.fk: widget.parentId},
      ),
    );
    if (saved == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return _RelatedCard(
      title: EntityModules.titleOf(widget.spec.module),
      loading: _loading,
      empty: _items.isEmpty,
      actions: widget.canCreate
          ? [
              TextButton.icon(
                onPressed: _create,
                icon: const Icon(NxI.plus),
                label: const Text('สร้าง'),
              ),
            ]
          : const [],
      children: [
        for (final row in _items)
          DenseCardTile(
            title: entityTitle(row, module: widget.spec.module),
            subtitle: entitySubtitle(row),
            onTap: () {
              final id = strId(row['id']);
              if (id.isNotEmpty) widget.onOpen(widget.spec.module, id, row: row);
            },
          ),
      ],
    );
  }
}

class _LinesCard extends StatelessWidget {
  const _LinesCard({
    required this.title,
    required this.loading,
    required this.saving,
    required this.canEdit,
    required this.empty,
    required this.children,
    this.onAdd,
    this.onSave,
    this.extra,
  });

  final String title;
  final bool loading;
  final bool saving;
  final bool canEdit;
  final bool empty;
  final List<Widget> children;
  final VoidCallback? onAdd;
  final VoidCallback? onSave;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        NxSurfaceCard(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Column(
            children: [
              if (loading) const LinearProgressIndicator(minHeight: 2),
              if (empty && !loading)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'ไม่มีรายการ',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ...children,
              if (canEdit) ...[
                if (onAdd != null)
                  TextButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(NxI.plus),
                    label: const Text('เพิ่มบรรทัด'),
                  ),
                if (onSave != null) NxHeroCta(label: 'บันทึกบรรทัด', busy: saving, onPressed: saving ? null : onSave),
              ],
              if (extra != null) ...[
                const SizedBox(height: 8),
                extra!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RelatedCard extends StatelessWidget {
  const _RelatedCard({
    required this.title,
    required this.loading,
    required this.empty,
    required this.children,
    this.actions = const [],
    this.trailing,
  });

  final String title;
  final bool loading;
  final bool empty;
  final List<Widget> children;
  final List<Widget> actions;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            if (trailing != null) trailing!,
            ...actions,
          ],
        ),
        const SizedBox(height: 8),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        if (empty && !loading)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'ยังไม่มีรายการ',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ...children,
      ],
    );
  }
}

num? _num(dynamic v) {
  if (v == null || v.toString().trim().isEmpty) return null;
  return num.tryParse(v.toString());
}

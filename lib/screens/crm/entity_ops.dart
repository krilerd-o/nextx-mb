import 'package:flutter/material.dart';
import '../docs/document_preview.dart';
import '../fsm/case_manday.dart';
import '../fsm/service_more.dart';
import 'lead_convert_sheet.dart';
import '../journey/job_parts.dart';
import '../journey/job_work_sections.dart' show jobSlaChip;
import '../journey/journey_widgets.dart' show JourneySection;
import '../fsm/inspection_lines.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/entity_modules.dart';
import '../../core/menu_access.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../widgets/dense_card_tile.dart';
import '../dashboard/home_boxes.dart' show RecentStrip;
import '../../widgets/fields/nx_entity_picker_sheet.dart';
import '../../widgets/fields/nx_form_field.dart' show NxDecimalInputFormatter;
import '../../widgets/fields/nx_lift_sheet.dart';
import '../../widgets/fields/nx_pick_option.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_surface_card.dart';
import '../calendar/activity_detail_screen.dart';
import '../calendar/activity_form_screen.dart';
import '../deep_link_loaders.dart';
import '../workspace/workspace_board_screen.dart';
import 'entity_create_screen.dart';
import 'order_summary_screen.dart';
import '../../core/error_reporting.dart';
import '../../core/thai_time.dart';
import '../../core/i18n.dart';
import '../../core/status_labels.dart';
import '../doc_form/doc_form_launcher.dart';

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
    this.journey = false,
  });

  final String module;
  final String id;
  final Map<String, dynamic> row;
  final OpenEntityFn onOpen;
  final bool canEdit;

  /// Service Journey page: lines / approval / job tools live in their own tabs.
  final bool journey;

  @override
  Widget build(BuildContext context) {
    final session = context.select((AppConfig c) => c.session);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (module == 'quotation' && !journey) ...[
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
          DealWorkspacePanel(dealId: id, canEdit: canEdit),
        ],
        if (module == 'lead') LeadConvertBar(id: id, row: row, onOpen: onOpen),
        if (module == 'job' && !journey) ...[
          JobExtrasPanel(id: id, row: row, canEdit: canEdit, onOpen: onOpen),
          if (canEdit) ...[const SizedBox(height: 8), JobWorkspaceButton(jobId: id)],
        ],
        if (module == 'asset') ...[
          AssetGenerateJobsBar(id: id, onOpen: onOpen),
          if (canEdit) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('asset-recompute'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await context.read<AppConfig>().apiClient.recomputeAssetCycles(id);
                  messenger.showSnackBar(SnackBar(content: Text(tr('คำนวณรอบ PM / สอบเทียบใหม่แล้ว — ดึงลงเพื่อดูวันครบกำหนดล่าสุด'))));
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
                }
              },
              icon: const Icon(NxI.arrowClockwise, size: 18),
              label: Text(tr('คำนวณรอบ PM / สอบเทียบใหม่')),
            ),
          ],
        ],
        if (module == 'service_contract') ...[
          CreateJobFromParentBar(
            label: 'สร้างใบสั่งงานจากสัญญา',
            parentModule: 'service_contract',
            parent: row,
            onOpen: onOpen,
          ),
          const SizedBox(height: 12),
          ContractMandayPanel(id: id, canEdit: canEdit),
          ContractExtrasPanel(id: id, row: row, canEdit: canEdit),
        ],
        if (module == 'case') ...[
          CreateJobFromParentBar(
            label: 'สร้างใบสั่งงานจากเคส',
            parentModule: 'case',
            parent: row,
            onOpen: onOpen,
          ),
          const SizedBox(height: 12),
          CreateActivityFromCaseBar(id: id, onOpen: onOpen),
          const SizedBox(height: 12),
          CaseMandayPanel(id: id, row: row, canEdit: canEdit),
          if (canEdit) CaseWorkspacePanel(caseId: id, row: row),
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
            // Keep every field the server knows (line_comment, item_label,
            // model, discount_type/amount…) — the save replaces all lines.
            ..._lines[i],
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('บันทึกบรรทัดแล้ว'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
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
            Text(tr(title), style: Theme.of(context).textTheme.titleSmall),
            if (canEdit)
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => _pickCatalog(context, 'product'),
                    icon: const Icon(NxI.package, size: 18),
                    label: Text(tr('เลือกสินค้า')),
                  ),
                  TextButton.icon(
                    onPressed: () => _pickCatalog(context, 'service'),
                    icon: const Icon(NxI.wrench, size: 18),
                    label: Text(tr('เลือกบริการ')),
                  ),
                ],
              ),
            TextFormField(
              enabled: canEdit,
              initialValue: line['description']?.toString() ?? title,
              decoration: InputDecoration(labelText: tr('รายละเอียด')),
              onChanged: (v) => onChanged({...line, 'description': v}),
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    enabled: canEdit,
                    initialValue: '${line['quantity'] ?? line['qty'] ?? ''}',
                    decoration: InputDecoration(labelText: tr('จำนวน')),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: const [NxDecimalInputFormatter()],
                    onChanged: (v) => onChanged({...line, 'quantity': v, 'qty': v}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    enabled: canEdit,
                    initialValue: '${line['unit_price'] ?? ''}',
                    decoration: InputDecoration(labelText: tr('ราคา')),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: const [NxDecimalInputFormatter()],
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(ok))));
      if (module.isNotEmpty) {
        final nextId = pickRecordId(data, idKeys);
        if (nextId.isNotEmpty) onOpen(module, nextId, row: data);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
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
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('แปลงเป็นออเดอร์แล้ว'))));
              final orderId = pickRecordId(data, const ['commercial_order_id', 'order_id', 'id']);
              if (orderId.isNotEmpty) {
                nxPush<void>(context, OrderSummaryScreen(orderId: orderId, preview: data));
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
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
          child: Text(tr('แปลงเป็นสัญญาบริการ')),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('บันทึกบรรทัดดีลแล้ว'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
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
          ? [TextButton.icon(onPressed: () => _add(context), icon: const Icon(NxI.plus), label: Text(tr('เพิ่ม')))]
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('สร้างใบเสนอราคาแล้ว'))));
          final nextId = pickRecordId(data, const ['quotation_id', 'id']);
          if (nextId.isNotEmpty) onOpen('quotation', nextId, row: data);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
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
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ตั้งเป็นใบเสนอหลักแล้ว'))));
                          _load();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
                        }
                      }
                    },
                    child: Text(tr('ตั้งหลัก')),
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
            Text(tr('ส่งอีเมลใบเสนอราคา'), style: Theme.of(ctx).textTheme.titleMedium),
            TextField(controller: to, decoration: InputDecoration(labelText: tr('ถึง (อีเมล)'))),
            TextField(controller: message, decoration: InputDecoration(labelText: tr('ข้อความ')), maxLines: 3),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ส่งอีเมลแล้ว'))));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
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
          child: Text(tr('ส่งอีเมลใบเสนอราคา')),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            try {
              await context.read<AppConfig>().apiClient.submitQuotationApproval(id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ส่งขออนุมัติแล้ว'))));
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
              }
            }
          },
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(tr('ส่งขออนุมัติ')),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final ok = await showStatusChangeConfirm(
                    context,
                    from: 'รออนุมัติ',
                    fromColor: const Color(0xFFF59E0B),
                    to: 'อนุมัติ',
                    toColor: const Color(0xFF16A34A),
                    confirmLabel: 'อนุมัติ',
                  );
                  if (ok == null || !context.mounted) return;
                  try {
                    await context.read<AppConfig>().apiClient.approveQuotation(id);
                    if (context.mounted) {
                      showNxStatusChangedSnack(ScaffoldMessenger.of(context), label: 'อนุมัติแล้ว');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
                    }
                  }
                },
                child: Text(tr('อนุมัติ')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final ok = await showStatusChangeConfirm(
                    context,
                    from: 'รออนุมัติ',
                    fromColor: const Color(0xFFF59E0B),
                    to: 'ไม่อนุมัติ',
                    requireReason: true,
                    reasons: kNxRejectReasons,
                    confirmLabel: 'ปฏิเสธ',
                  );
                  if (ok == null || !context.mounted) return;
                  try {
                    await context.read<AppConfig>().apiClient.rejectQuotation(id, reason: ok.note);
                    if (context.mounted) {
                      showNxStatusChangedSnack(ScaffoldMessenger.of(context), label: 'ปฏิเสธแล้ว');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
                    }
                  }
                },
                child: Text(tr('ปฏิเสธ')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          // Revise in the step form (edit first, reason required) → POST /quotation/:id/revise.
          onPressed: () async {
            final data = await openDocForm(context, module: 'quotation', mode: DocFormMode.revise, id: id);
            if (data == null || !context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('สร้างฉบับแก้ไขแล้ว'))));
            final nextId = pickRecordId(data, const ['quotation_id', 'id', 'new_id']);
            if (nextId.isNotEmpty) onOpen('quotation', nextId, row: data);
          },
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(tr('สร้างฉบับแก้ไข')),
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

  /// Same convert window as the web (settings, duplicates, owners,
  /// move activities); the old inline dialog is gone.
  Future<void> _openPreview(BuildContext context) async {
    final r = await showLeadConvertSheet(context, leadId: id);
    if (r == null || !context.mounted) return;
    final accountId = pickRecordId(r, const ['account_id']);
    if (accountId.isNotEmpty) onOpen('account', accountId);
  }

  @override
  Widget build(BuildContext context) {
    if (_converted) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(tr('ลีดนี้แปลงแล้ว'), style: Theme.of(context).textTheme.bodyMedium),
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
  @override
  Widget build(BuildContext context) => InspectionLinesEditor(inspectionId: widget.id, canEdit: widget.canEdit);
}

class JobExtrasPanel extends StatefulWidget {
  const JobExtrasPanel({
    super.key,
    required this.id,
    required this.row,
    required this.onOpen,
    this.canEdit = true,
    this.sectioned = false,
    this.extra = const [],
  });

  final String id;
  final Map<String, dynamic> row;
  final OpenEntityFn onOpen;
  final bool canEdit;

  /// Job summary: one "งานสนาม" card (SLA is shown by the work-info card).
  final bool sectioned;

  /// More rows at the end of the card (Workspace, inspection…).
  final List<Widget> extra;

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
        if (!widget.sectioned) sla = await api.getJobSla(widget.id); // summary: the work-info card shows SLA
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _body(context);
    if (!widget.sectioned) return body;
    return JourneySection(key: const ValueKey('job-field-ops'), title: tr('งานสนาม'), icon: NxI.wrench, child: body);
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    // SLA as a chip (`{policy, response_due, resolve_due, breached_*}`); a job
    // without an SLA policy shows nothing (no empty bar).
    final sla = widget.sectioned ? null : jobSlaChip(_sla, widget.row);
    final small = OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.sectioned) ...[
          Text(tr('งานสนาม'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
        ],
        if (sla != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                key: const ValueKey('job-sla-chip'),
                avatar: Icon(sla.icon, size: 16, color: sla.color),
                label: Text(sla.label),
                side: BorderSide(color: sla.color.withValues(alpha: 0.4)),
                backgroundColor: sla.color.withValues(alpha: 0.08),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        if (_mismatch != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(tr(_mismatch!), style: TextStyle(color: theme.colorScheme.error)),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              style: small,
              onPressed: () => openRecordDocument(context, 'job', {...widget.row, 'id': widget.id}),
              icon: const Icon(NxI.filePdf),
              label: Text(tr('PDF ใบสั่งงาน')),
            ),
            OutlinedButton.icon(
              key: const ValueKey('job-ops-schedule'),
              style: small,
              onPressed: _busy ? null : () => _schedule(context),
              icon: const Icon(NxI.calendarBlank),
              label: Text(tr('นัดหมาย')),
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
                label: Text(tr('เช็คอิน')),
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
                label: Text(tr('เปิดบอร์ด')),
              ),
            OutlinedButton.icon(
              key: const ValueKey('job-ops-match'),
              style: small,
              icon: const Icon(NxI.users),
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        final data = await context.read<AppConfig>().apiClient.matchJobUsers(widget.id);
                        if (mounted) setState(() => _matches = extractMapList(data));
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              label: Text(tr('ช่างที่ตรงทักษะ')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Text(tr('ทักษะงาน'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final skill in _catalog)
              FilterChip(
                label: Text(tr(entityTitle(skill, module: 'skill'))),
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
                Chip(label: Text(tr(s['skill_name']?.toString() ?? s['skill_code']?.toString() ?? 'ทักษะ'))),
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
        JobPartsSection(jobId: widget.id, parts: _parts, canEdit: widget.canEdit, onChanged: _load),
        ...widget.extra,
      ],
    );
  }

  Future<void> _schedule(BuildContext context) async {
    final date = await showDatePicker(
        switchToInputEntryModeIcon: const Icon(NxI.pencilSimple),
        switchToCalendarEntryModeIcon: const Icon(NxI.calendarBlank),
      context: context,
      initialDate: thaiNow(),
      firstDate: thaiNow().subtract(const Duration(days: 1)),
      lastDate: thaiNow().add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(thaiNow()));
    if (time == null || !context.mounted) return;
    final when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => _busy = true);
    try {
      final data = await context.read<AppConfig>().apiClient.scheduleJob(widget.id, when: when.toIso8601String());
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('สร้างนัดหมายแล้ว'))));
      final actId = pickRecordId(data, const ['activity_id', 'related_activity_id']);
      if (actId.isNotEmpty) {
        nxPush<void>(context, ActivityByIdLoader(id: actId));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('มอบหมายให้ ${user['display_name'] ?? user['name'] ?? uid}'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('สร้างใบสั่งงาน $count รายการ'))));
          if (created.isEmpty) return;
          await showNxLiftSheet<void>(
            context: context,
            builder: (ctx, scroll) {
              return ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  Text(tr('งานที่สร้าง'), style: Theme.of(ctx).textTheme.titleMedium),
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
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
          }
        }
      },
    );
  }
}

/// "สร้างใบสั่งงานจากเคส / สัญญา": the job step form pre-filled from the
/// case / contract (same values the server's create-job writes), so the user
/// reviews time, technician and place before the job exists.
class CreateJobFromParentBar extends StatelessWidget {
  const CreateJobFromParentBar({
    super.key,
    required this.label,
    required this.parentModule,
    required this.parent,
    required this.onOpen,
  });

  final String label;
  final String parentModule;
  final Map<String, dynamic> parent;
  final OpenEntityFn onOpen;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey('create-job-from-$parentModule'),
      child: NxHeroCta(
        label: label,
        onPressed: () async {
          final data = await openDocForm(context, module: 'job', parent: (module: parentModule, row: parent));
          if (data == null || !context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('$labelแล้ว'))));
          final jobId = pickRecordId(data, const ['job_id', 'id']);
          if (jobId.isNotEmpty) onOpen('job', jobId, row: data);
        },
      ),
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
        scrollable: true, // fields stay reachable above the keyboard
        title: Text(tr('เพิ่ม manday')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qty,
              decoration: InputDecoration(labelText: tr('จำนวน (ชั่วโมง)')),
              keyboardType: TextInputType.number,
            ),
            TextField(controller: note, decoration: InputDecoration(labelText: tr('หมายเหตุ'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('บันทึก'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppConfig>().apiClient.addContractManday(widget.id, {
        'qty': num.tryParse(qty.text.trim()) ?? 1,
        'unit': 'Hour', // same as the web: the amount is in hours
        'note': note.text.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      }
    }
  }

  Future<void> _adjust() async {
    final qty = TextEditingController(text: '1');
    final note = TextEditingController();
    var direction = 'debit';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true, // fields stay reachable above the keyboard
        title: Text(tr('ปรับ manday')),
        content: StatefulBuilder(
          builder: (context, setLocal) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
        icon: const Icon(NxI.caretDown, size: 18),
                  value: direction,
                  items: [
                    DropdownMenuItem(value: 'debit', child: Text(tr('หัก'))),
                    DropdownMenuItem(value: 'credit', child: Text(tr('เพิ่ม'))),
                  ],
                  onChanged: (v) => setLocal(() => direction = v ?? 'debit'),
                ),
                TextField(
                  controller: qty,
                  decoration: InputDecoration(labelText: tr('จำนวน (ชั่วโมง)')),
                  keyboardType: TextInputType.number,
                ),
                TextField(controller: note, decoration: InputDecoration(labelText: tr('หมายเหตุ'))),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('บันทึก'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppConfig>().apiClient.adjustContractManday(widget.id, {
        'qty': num.tryParse(qty.text.trim()) ?? 1,
        'unit': 'Hour',
        'direction': direction,
        'note': note.text.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remain = _ledger['md_remain_hours'];
    return _RelatedCard(
      title: 'สมุด manday',
      loading: _loading,
      empty: _rows.isEmpty,
      trailing: remain != null ? Text(tr('คงเหลือ $remain ชม.')) : null,
      actions: widget.canEdit
          ? [
              TextButton(onPressed: _add, child: Text(tr('เพิ่ม'))),
              TextButton(onPressed: _adjust, child: Text(tr('ปรับ'))),
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
          ActivityFormScreen(
            title: 'สร้างนัดหมายจากเคส',
            initial: {'related_module': 'case', 'related_id': int.tryParse(id) ?? id, 'related_case_id': id},
          ),
        );
        if (saved == true && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('สร้างนัดหมายแล้ว'))));
        }
      },
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: Text(tr('สร้างนัดหมายจากเคส')),
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
        scrollable: true, // fields stay reachable above the keyboard
        title: Text(tr('เพิ่มพูล manday')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: qty, decoration: InputDecoration(labelText: tr('จำนวน')), keyboardType: TextInputType.number),
            TextField(controller: note, decoration: InputDecoration(labelText: tr('หมายเหตุ'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('บันทึก'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppConfig>().apiClient.addAccountManday(widget.id, {
        'qty': num.tryParse(qty.text.trim()) ?? 1,
        'note': note.text.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _RelatedCard(
      title: 'พูล manday ของบัญชี',
      loading: _loading,
      empty: _summary.isEmpty,
      trailing: _summary['remain_hours'] != null || _summary['md_remain_hours'] != null
          ? Text(tr('คงเหลือ ${_summary['remain_hours'] ?? _summary['md_remain_hours']} ชม.'))
          : null,
      actions: widget.canEdit ? [TextButton(onPressed: _add, child: Text(tr('เพิ่ม')))] : const [],
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
          // Relations with no rows are hidden entirely (header too).
          for (final g in _groups.where((g) => extractMapList(g['items']).isNotEmpty)) ...[
            _RelatedCard(
              title: g['label_th']?.toString() ?? g['label']?.toString() ?? g['key']?.toString() ?? 'ที่เกี่ยวข้อง',
              module: _moduleOf(g, extractMapList(g['items']).first),
              count: extractMapList(g['items']).length,
              loading: false,
              empty: false,
              children: [
                for (final item in extractMapList(g['items']))
                  RelatedItemTile(
                    module: _moduleOf(g, item),
                    name: item['title']?.toString() ?? entityTitle(item, module: _moduleOf(g, item)),
                    no: relatedNo(_moduleOf(g, item), item),
                    status: relatedStatus(_moduleOf(g, item), item),
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
    if (!_loading && _items.isEmpty) return const SizedBox.shrink();
    return _RelatedCard(
      title: EntityModules.titleOf(widget.spec.module),
      module: widget.spec.module,
      count: _items.length,
      loading: _loading,
      empty: _items.isEmpty,
      actions: widget.canCreate
          ? [
              TextButton.icon(
                onPressed: _create,
                icon: const Icon(NxI.plus),
                label: Text(tr('สร้าง')),
              ),
            ]
          : const [],
      children: [
        for (final row in _items)
          RelatedItemTile(
            module: widget.spec.module,
            name: entityTitle(row, module: widget.spec.module),
            no: relatedNo(widget.spec.module, row),
            status: relatedStatus(widget.spec.module, row),
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
  });

  final String title;
  final bool loading;
  final bool saving;
  final bool canEdit;
  final bool empty;
  final List<Widget> children;
  final VoidCallback? onAdd;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr(title), style: theme.textTheme.titleMedium),
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
                    tr('ไม่มีรายการ'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ...children,
              if (canEdit) ...[
                if (onAdd != null)
                  TextButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(NxI.plus),
                    label: Text(tr('เพิ่มบรรทัด')),
                  ),
                if (onSave != null) NxHeroCta(label: 'บันทึกบรรทัด', busy: saving, onPressed: saving ? null : onSave),
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
    this.module,
    this.count,
  });

  final String title;
  final bool loading;
  final bool empty;
  final List<Widget> children;
  final List<Widget> actions;
  final Widget? trailing;
  final String? module;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = RecentStrip.colorOf(module ?? '');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (module != null) ...[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
                    child: Icon(RecentStrip.iconOf(module!), size: 16, color: color),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(child: Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                if (count != null && count! > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(10)),
                    child: Text('$count', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                if (trailing != null) trailing!,
                ...actions,
              ],
            ),
            const SizedBox(height: 6),
            if (loading) const LinearProgressIndicator(minHeight: 2),
            if (empty && !loading)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  tr('ยังไม่มีรายการ'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Record number of a related row (`no` from the API, else `<module>_no`).
String relatedNo(String module, Map<String, dynamic> row) {
  final short = switch (module) {
    'service_contract' => 'contract',
    'service_location' => 'location',
    _ => module,
  };
  for (final k in ['no', '_no', '${short}_no', '${module}_no']) {
    final v = '${row[k] ?? ''}'.trim();
    if (v.isNotEmpty && v != 'null') return v;
  }
  return '';
}

/// Status of a related row (`status` from the API, else `<module>_status` / stage).
String relatedStatus(String module, Map<String, dynamic> row) {
  final short = switch (module) {
    'service_contract' => 'contract',
    'service_location' => 'location',
    _ => module,
  };
  for (final k in ['status', '_status', '${short}_status', '${module}_status', 'deal_stage', 'stage']) {
    final v = '${row[k] ?? ''}'.trim();
    if (v.isNotEmpty && v != 'null') return v;
  }
  return '';
}

/// One related record: name, number and status always on the row.
class RelatedItemTile extends StatelessWidget {
  const RelatedItemTile({super.key, required this.module, required this.name, required this.no, required this.status, this.onTap});
  final String module;
  final String name;
  final String no;
  final String status;
  final VoidCallback? onTap;

  static Color statusColor(ColorScheme cs, String v) {
    final s = v.toLowerCase();
    if (RegExp(r'won|approved|accept|done|complete|closed|qualified|paid|active|อนุมัติ|สำเร็จ|เสร็จ|ปิด').hasMatch(s)) return const Color(0xFF16A34A);
    if (RegExp(r'lost|reject|cancel|expired|unqualified|ยกเลิก|ไม่อนุมัติ').hasMatch(s)) return cs.error;
    if (RegExp(r'draft|new|ร่าง|ใหม่').hasMatch(s)) return cs.onSurfaceVariant;
    return const Color(0xFFF59E0B);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sc = statusColor(cs, status);
    return InkWell(
      key: ValueKey('related-$module-$no$name'),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isEmpty ? '—' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(no.isEmpty ? '—' : no, style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
                      if (status.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                            decoration: BoxDecoration(color: sc.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
                            child: Text(statusValueLabel(status, module: module), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: sc, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(NxI.caretRight, size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

num? _num(dynamic v) {
  if (v == null || v.toString().trim().isEmpty) return null;
  return num.tryParse(v.toString());
}

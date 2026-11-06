import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/menu_access.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../services/file_open.dart';
import '../../widgets/fields/field_ui_type.dart';
import '../../widgets/fields/nx_field_value.dart';
import '../../widgets/fields/nx_lift_sheet.dart';
import '../../widgets/fields/nx_pick_option.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_surface_card.dart';
import '../deep_link_loaders.dart';
import '../jobs/job_inspection_screen.dart';
import 'entity_create_screen.dart';
import 'entity_ops.dart';

class EntityDetailScreen extends StatefulWidget {
  const EntityDetailScreen({
    super.key,
    required this.module,
    required this.row,
    this.embedded = false,
  });

  final String module;
  final Map<String, dynamic> row;
  final bool embedded;

  @override
  State<EntityDetailScreen> createState() => _EntityDetailScreenState();
}

class _EntityDetailScreenState extends State<EntityDetailScreen> {
  final _noteController = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  List<Map<String, dynamic>> _tags = [];
  List<Map<String, dynamic>> _catalog = [];
  List<Map<String, dynamic>> _fields = [];
  Map<String, List<Map<String, dynamic>>> _picklists = {};
  bool _loading = true;
  Object? _error;
  late Map<String, dynamic> _row;

  String get _id => strId(widget.row['id']);

  @override
  void initState() {
    super.initState();
    _row = Map<String, dynamic>.from(widget.row);
    _reload();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = _comments.isEmpty && _fields.isEmpty;
      _error = null;
    });
    if (!context.read<AppConfig>().isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    final api = context.read<AppConfig>().apiClient;
    try {
      final record = await api.getEntity(widget.module, _id);
      final comments = await api.getEntityComments(widget.module, _id);
      final tags = await api.getEntityTags(widget.module, _id);
      var catalog = <Map<String, dynamic>>[];
      var fields = <Map<String, dynamic>>[];
      var picklists = <String, List<Map<String, dynamic>>>{};
      try {
        catalog = await api.getTags(module: widget.module);
      } catch (_) {}
      try {
        final schema = await api.getFieldSchema(widget.module);
        fields = schema.fields;
        picklists = schema.picklists;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        if (record.isNotEmpty) _row = {..._row, ...record};
        _comments = comments;
        _tags = tags;
        _catalog = catalog;
        _fields = fields;
        _picklists = picklists;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _postComment() async {
    final body = _noteController.text.trim();
    if (body.isEmpty) return;
    try {
      await context.read<AppConfig>().apiClient.postEntityComment(widget.module, _id, body);
      _noteController.clear();
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }

  Future<void> _toggleTag(Map<String, dynamic> tag) async {
    final tagId = int.tryParse(tag['id']?.toString() ?? '');
    if (tagId == null) return;
    final assigned = _tags.any((t) => t['id']?.toString() == tagId.toString());
    try {
      final api = context.read<AppConfig>().apiClient;
      if (assigned) {
        await api.removeEntityTag(widget.module, _id, tagId);
      } else {
        await api.assignEntityTag(widget.module, _id, tagId);
      }
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }

  String _labelFor(String key) {
    for (final f in _fields) {
      if (f['name']?.toString() == key) {
        return f['label_th']?.toString() ?? f['label']?.toString() ?? key;
      }
    }
    return key;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = context.watch<AppConfig>().session;
    final title = entityTitle(_row, module: widget.module);
    final people = entityPeopleLine(_row);
    final status = entityStatus(_row);

    final canEdit = _editableFields().isNotEmpty || _fields.isEmpty;
    return Scaffold(
      appBar: NxAppHeader(
        title: title,
        automaticallyImplyLeading: !widget.embedded,
        actions: [
          if (widget.module == 'quotation' || widget.module == 'inspection' || widget.module == 'job') ...[
            IconButton(
              tooltip: 'เปิด PDF',
              icon: const Icon(NxI.filePdf),
              onPressed: _openPdf,
            ),
            IconButton(
              tooltip: 'แชร์ PDF',
              icon: const Icon(NxI.shareNetwork),
              onPressed: _sharePdf,
            ),
          ],
          if (canEdit)
            IconButton(
              tooltip: 'แก้ไข',
              icon: const Icon(NxI.pencilSimple),
              onPressed: () => _openEdit(context),
            ),
        ],
        menu: canEdit && context.watch<AppConfig>().isLoggedIn
            ? [
                NxHeaderMenuItem(
                  label: 'ลบ',
                  icon: NxI.trash,
                  onTap: _confirmDelete,
                ),
              ]
            : null,
      ),
      body: RefreshIndicator(
        color: theme.colorScheme.primary,
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            NxSurfaceCard(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
              child: Column(
                children: [
                  NxAvatar(label: title, size: 76),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  if (people != null && people.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      people,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (status != null) ...[
                    const SizedBox(height: 12),
                    Chip(
                      label: Text(status),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 16),
              const SizedBox(height: 180, child: NxSkeletonForm(fields: 4)),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 12),
                child: Column(
                  children: [
                    Text(formatApiError(_error!), style: TextStyle(color: theme.colorScheme.error)),
                    TextButton(onPressed: _reload, child: const Text('ลองใหม่')),
                  ],
                ),
              ),
            if (!_loading) ...[
              if (widget.module == 'job' && MenuAccess.allow(session, MenuAccess.inspection)) ...[
                const SizedBox(height: 16),
                NxHeroCta(
                  label: 'สร้างใบตรวจรับ',
                  onPressed: () => nxPush<void>(
                    context,
                    JobInspectionScreen(job: _row),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              NxSurfaceCard(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  children: _valueRows(),
                ),
              ),
              const SizedBox(height: 16),
              EntityOpsSection(
                module: widget.module,
                id: _id,
                row: _row,
                canEdit: canEdit,
                onOpen: (module, id, {row}) {
                  nxPush<void>(
                    context,
                    row != null
                        ? EntityDetailScreen(module: module, row: {...row, 'id': id})
                        : EntityByIdLoader(module: module, id: id),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text('แท็ก', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              NxSurfaceCard(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in _tags)
                      InputChip(
                        label: Text(t['name']?.toString() ?? ''),
                        onDeleted: () => _toggleTag(t),
                      ),
                    ActionChip(
                      label: const Text('เลือกแท็ก'),
                      onPressed: _catalog.isEmpty ? null : _pickTags,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('บันทึกบนเซิร์ฟเวอร์', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (_comments.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'ยังไม่มีบันทึก',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ..._comments.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: NxSurfaceCard(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c['user_name']?.toString().trim().isNotEmpty == true
                              ? c['user_name'].toString()
                              : 'บันทึก',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        NxHtmlView(html: c['body']?.toString() ?? ''),
                        if (entityWhen({'created_at': c['created_at']}) != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              entityWhen({'created_at': c['created_at']})!,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              NxSurfaceCard(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: [
                    TextField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        hintText: 'เพิ่มบันทึก',
                      ),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 12),
                    NxHeroCta(label: 'บันทึก', onPressed: _postComment),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickTags() async {
    await showNxLiftSheet<void>(
      context: context,
      builder: (ctx, scroll) {
        return ListView(
          controller: scroll,
          children: [
            for (final t in _catalog)
              CheckboxListTile(
                title: Text(t['name']?.toString() ?? ''),
                value: _tags.any((x) => x['id']?.toString() == t['id']?.toString()),
                onChanged: (_) {
                  Navigator.pop(ctx);
                  _toggleTag(t);
                },
              ),
          ],
        );
      },
    );
  }

  static const _skipKeys = {
    'id',
    'business_id',
    '_shared_permission',
    '_dashboard_unowned',
  };

  List<Widget> _valueRows() {
    final byName = <String, Map<String, dynamic>>{};
    for (final f in _fields) {
      final name = fieldName(f);
      if (name.isNotEmpty) byName[name] = f;
    }
    final keys = <String>[];
    if (_fields.isNotEmpty) {
      for (final f in _fields) {
        final name = fieldName(f);
        if (name.isEmpty || _skipKeys.contains(name)) continue;
        if (f['access']?.toString().toLowerCase() == 'hidden') continue;
        keys.add(name);
      }
    } else {
      for (final k in _row.keys) {
        if (_skipKeys.contains(k) || k.startsWith('_')) continue;
        keys.add(k);
      }
    }
    if (keys.isEmpty) {
      return [const Padding(padding: EdgeInsets.all(8), child: Text('—'))];
    }
    return [
      for (final name in keys)
        () {
          var uiType = byName[name] == null ? FieldUiType.text : resolveFieldUiType(byName[name]!);
          final recId = lookupRecordId(_row[name]);
          final related = uiType.entityModule ?? _relatedModuleForField(name);
          if (related != null && uiType.entityModule == null) {
            uiType = _selectTypeForModule(related);
          }
          return NxFieldValueView(
            uiType: uiType,
            label: _labelFor(name),
            value: _row[name],
            relatedModule: related,
            options: [
              for (final o in _picklists[name] ?? const <Map<String, dynamic>>[]) NxPickOption.fromMap(o),
              if (_row['${name}_name'] != null && _row[name] != null)
                NxPickOption(
                  value: _row[name].toString(),
                  label: _row['${name}_name'].toString(),
                ),
            ],
            onOpen: related != null && recId.isNotEmpty
                ? () => nxPush<void>(
                      context,
                      EntityByIdLoader(module: related, id: recId),
                    )
                : null,
          );
        }(),
    ];
  }

  List<Map<String, dynamic>> _editableFields() {
    if (_fields.isNotEmpty) {
      return _fields.where((f) {
        final name = fieldName(f);
        if (name.isEmpty || name == 'id' || name == 'business_id') return false;
        return !fieldIsReadonly(f);
      }).toList();
    }
    return _row.keys
        .where((k) {
          final lower = k.toLowerCase();
          return k != 'id' &&
              k != 'business_id' &&
              !lower.startsWith('_') &&
              lower != 'created_at' &&
              lower != 'updated_at';
        })
        .map((k) => {'name': k, 'label_th': _labelFor(k)})
        .toList();
  }

  String? _relatedModuleForField(String name) {
    switch (name) {
      case 'related_account_id':
      case 'account_id':
      case 'convert_account_id':
        return 'account';
      case 'related_contact_id':
      case 'contact_id':
      case 'convert_contact_id':
        return 'contact';
      case 'related_lead_id':
      case 'lead_id':
        return 'lead';
      case 'related_deal_id':
      case 'deal_id':
      case 'convert_deal_id':
        return 'deal';
      case 'related_job_id':
      case 'job_id':
        return 'job';
      case 'related_case_id':
      case 'case_id':
        return 'case';
      case 'related_contract_id':
      case 'contract_id':
        return 'service_contract';
      case 'related_asset_id':
      case 'asset_id':
        return 'asset';
      case 'related_quotation_id':
      case 'quotation_id':
        return 'quotation';
      case 'related_product_id':
      case 'product_id':
        return 'product';
      case 'related_service_id':
      case 'service_id':
        return 'service';
      case 'related_location_id':
      case 'location_id':
        return 'service_location';
      case 'related_inspection_id':
      case 'inspection_id':
        return 'inspection';
      default:
        return null;
    }
  }

  FieldUiType _selectTypeForModule(String module) {
    switch (module) {
      case 'lead':
        return FieldUiType.leadSelect;
      case 'account':
        return FieldUiType.accountSelect;
      case 'contact':
        return FieldUiType.contactSelect;
      case 'product':
        return FieldUiType.productSelect;
      case 'service':
        return FieldUiType.serviceSelect;
      case 'quotation':
        return FieldUiType.quotationSelect;
      case 'asset':
        return FieldUiType.assetSelect;
      case 'job':
        return FieldUiType.jobSelect;
      case 'service_location':
        return FieldUiType.locationSelect;
      case 'case':
        return FieldUiType.caseSelect;
      case 'service_contract':
        return FieldUiType.contractSelect;
      case 'inspection':
        return FieldUiType.inspectionSelect;
      case 'skill':
        return FieldUiType.skillSelect;
      default:
        return FieldUiType.picklist;
    }
  }

  Future<({List<int> bytes, String name})> _pdfPayload() async {
    final api = context.read<AppConfig>().apiClient;
    if (widget.module == 'inspection') {
      return (bytes: await api.getInspectionPdf(_id), name: 'inspection-$_id.pdf');
    }
    if (widget.module == 'job') {
      return (bytes: await api.downloadJobPdf(_id), name: 'job-$_id.pdf');
    }
    return (bytes: await api.getQuotationPdf(_id), name: 'quotation-$_id.pdf');
  }

  Future<void> _openPdf() async {
    try {
      final pdf = await _pdfPayload();
      await openPdfBytes(pdf.bytes, pdf.name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }

  Future<void> _sharePdf() async {
    try {
      final pdf = await _pdfPayload();
      await sharePdfBytes(pdf.bytes, pdf.name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบรายการนี้?'),
        content: Text('ลบ ${entityTitle(_row, module: widget.module)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ลบ')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppConfig>().apiClient.deleteEntity(widget.module, _id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ลบแล้ว')));
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }

  Future<void> _openEdit(BuildContext context) async {
    final fields = _editableFields();
    if (!context.mounted) return;
    final saved = await nxPush<bool>(
      context,
      EntityCreateScreen(
        module: widget.module,
        title: 'แก้ไข',
        recordId: _id,
        initialValues: Map<String, dynamic>.from(_row),
        fields: fields,
        picklists: _picklists,
      ),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกแล้ว')));
      _reload();
    }
  }
}


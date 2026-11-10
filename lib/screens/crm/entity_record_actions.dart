import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/entity_form_rules.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/fields/field_ui_type.dart';
import '../../widgets/fields/nx_pick_option.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_skeleton.dart';
import '../deep_link_loaders.dart';
import 'entity_create_screen.dart';
import 'entity_detail_parts.dart';
import 'lead_convert_sheet.dart';

/// What the current user may do with one record (same rules as the web list:
/// `_shared_permission` read_only = view only, edit = edit/duplicate, full =
/// also delete; a converted lead is locked).
class EntityRowPerms {
  const EntityRowPerms({required this.canEdit, required this.canDelete, required this.canStatus});

  final bool canEdit;
  final bool canDelete;

  /// Status can change here (not for cases: those move on the case screen).
  final bool canStatus;

  static const _converted = {'converted', 'แปลงแล้ว', 'แปลงเป็นลูกค้าแล้ว'};

  static bool leadLocked(Map<String, dynamic> row) {
    bool has(String k) {
      final v = row[k];
      return v != null && '$v'.trim().isNotEmpty && '$v' != '0' && '$v' != 'null';
    }

    if (has('convert_contact_id') || has('convert_account_id')) return true;
    if (has('convert_contact') && has('contact_name')) return true;
    if (has('convert_account') && has('account_name')) return true;
    final s = '${row['lead_status'] ?? row['leadstatus'] ?? ''}'.trim().toLowerCase();
    return _converted.contains(s);
  }

  factory EntityRowPerms.of(String module, Map<String, dynamic> row) {
    final perm = '${row['_shared_permission'] ?? 'full'}';
    var edit = perm != 'read_only';
    if (module == 'lead' && leadLocked(row)) edit = false;
    return EntityRowPerms(canEdit: edit, canDelete: perm == 'full', canStatus: edit && module != 'case');
  }
}

/// Record commands shared by the list (long-press sheet) and the detail
/// screen: change status, comments, edit, duplicate, delete.
class EntityRecordActions {
  EntityRecordActions._();

  /// Status column per module, like the web (`getEntityStatusColumn`).
  static String webStatusColumn(String module) => switch (module) {
        'contact' => 'contact_status',
        'account' => 'account_status',
        'case' => 'case_status',
        'product' => 'product_status',
        'service' => 'service_status',
        'deal' => 'deal_stage',
        'quotation' => 'quotation_status',
        'service_contract' => 'contract_status',
        'activity' => 'status',
        _ => 'lead_status',
      };

  static const _statusCandidates = [
    'status', 'leadstatus', 'lead_status', 'deal_stage', 'sales_stage', 'case_status', 'quotation_status',
    'job_status', 'inspection_status', 'account_status', 'contact_status', 'activity_status', 'contract_status',
  ];

  /// The picklist field that holds the record's status (null = none).
  static String? statusKey(String module, Map<String, List<Map<String, dynamic>>> picklists, [Map<String, dynamic>? row]) {
    for (final k in [webStatusColumn(module), '${module}_status', '${module}_stage', ..._statusCandidates]) {
      if ((picklists[k] ?? const []).isNotEmpty) return k;
    }
    return row == null ? null : entityStatusKey(row, module);
  }

  /// Status choices in their real order (Product / Service: draft first).
  static List<({String value, String label, String? color})> statusOptions(
    String module,
    String? key,
    Map<String, List<Map<String, dynamic>>> picklists, {
    String? current,
  }) {
    if (key == null) return const [];
    final raw = picklists[key] ?? const <Map<String, dynamic>>[];
    final colors = <String, String?>{};
    final opts = <({String value, String label})>[];
    for (final o in raw) {
      final p = NxPickOption.fromMap(o);
      colors[p.value] = o['color']?.toString();
      final canon = statusCurrent(module, p.value);
      if (canon != null) colors.putIfAbsent(canon, () => o['color']?.toString());
      opts.add((value: p.value, label: p.label));
    }
    return [
      for (final o in orderStatusOptions(module, opts, current: current)) (value: o.value, label: o.label, color: colors[o.value]),
    ];
  }

  /// Colour for a status: the picklist's own colour, else from the word.
  static Color statusColor(ColorScheme cs, String value, [String? hex]) {
    final s = (hex ?? '').replaceAll('#', '');
    if (s.length == 6) {
      final v = int.tryParse(s, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    final w = value.toLowerCase();
    if (RegExp(r'won|approved|accept|done|complete|qualified|paid|active|อนุมัติ|สำเร็จ|เสร็จ|ใช้งาน$').hasMatch(w)) {
      return const Color(0xFF16A34A);
    }
    if (RegExp(r'lost|reject|cancel|expired|unqualified|inactive|discontinued|ยกเลิก|ไม่อนุมัติ|ไม่ใช้งาน|เลิก').hasMatch(w)) {
      return cs.error;
    }
    if (RegExp(r'draft|new|ร่าง|ใหม่').hasMatch(w)) return cs.onSurfaceVariant;
    return const Color(0xFFF59E0B);
  }

  /// Fields the edit / duplicate form shows (schema, else the row's keys).
  static List<Map<String, dynamic>> editableFields(List<Map<String, dynamic>> fields, Map<String, dynamic> row) {
    if (fields.isNotEmpty) {
      return fields.where((f) {
        final name = fieldName(f);
        if (name.isEmpty || name == 'id' || name == 'business_id') return false;
        return !fieldIsReadonly(f);
      }).toList();
    }
    return row.keys
        .where((k) {
          final lower = k.toLowerCase();
          return k != 'id' && k != 'business_id' && !lower.startsWith('_') && lower != 'created_at' && lower != 'updated_at';
        })
        .map((k) => <String, dynamic>{'name': k, 'label_th': k})
        .toList();
  }

  static void _snack(ScaffoldMessengerState? m, String text) {
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(tr(text))));
  }

  /// Full record + schema (list rows are slim: only the card's columns).
  static Future<({Map<String, dynamic> row, ModuleFieldSchema? schema})> load(
    BuildContext context,
    String module,
    Map<String, dynamic> row,
  ) async {
    final api = context.read<AppConfig>().apiClient;
    final id = '${row['id'] ?? ''}';
    ModuleFieldSchema? schema;
    var full = row;
    await Future.wait([
      () async {
        try {
          schema = await api.getFieldSchema(module);
        } catch (_) {}
      }(),
      if (id.isNotEmpty)
        api.getEntity(module, id).then((r) {
          if (r.isNotEmpty) full = {...row, ...r};
        }),
    ]);
    return (row: full, schema: schema);
  }

  /// Sheet of status pills; picking one saves at once. Returns the new value.
  static Future<String?> changeStatus(
    BuildContext context, {
    required String module,
    required Map<String, dynamic> row,
    Map<String, List<Map<String, dynamic>>>? picklists,
    void Function(String key, String value)? onChanged,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final api = context.read<AppConfig>().apiClient;
    var lists = picklists;
    if (lists == null || lists.isEmpty) {
      try {
        lists = (await api.getFieldSchema(module)).picklists;
      } catch (e) {
        _snack(messenger, formatApiError(e));
        return null;
      }
    }
    if (!context.mounted) return null;
    final key = statusKey(module, lists, row);
    final options = statusOptions(module, key, lists, current: key == null ? null : row[key]?.toString());
    if (key == null || options.isEmpty) {
      _snack(messenger, 'เมนูนี้ไม่มีสถานะให้เปลี่ยน');
      return null;
    }
    final before = row[key]?.toString();
    final picked = await showAppBottomSheet<String>(
      context: context,
      title: tr('ปรับสถานะ'),
      child: EntityStatusPickList(options: options, current: statusCurrent(module, before)),
    );
    if (picked == null || picked == before || picked == statusCurrent(module, before) || !context.mounted) return null;
    // A lead becomes "Converted" only through the convert window (creates Account / Contact).
    if (module == 'lead' && isLeadConvertedStatus(picked)) {
      final r = await showLeadConvertSheet(context, leadId: '${row['id']}');
      if (r == null) return null;
      onChanged?.call(key, 'Converted');
      return 'Converted';
    }
    final id = '${row['id'] ?? ''}';
    final label = options.firstWhere((o) => o.value == picked).label;
    onChanged?.call(key, picked);
    try {
      await api.putEntity(module, id, {key: picked});
      HapticFeedback.mediumImpact();
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(tr('เปลี่ยนสถานะเป็น $label แล้ว')),
        persist: false,
        action: before == null
            ? null
            : SnackBarAction(
                label: tr('เลิกทำ'),
                onPressed: () async {
                  onChanged?.call(key, before);
                  try {
                    await api.putEntity(module, id, {key: before});
                  } catch (e) {
                    onChanged?.call(key, picked);
                    _snack(messenger, formatApiError(e));
                  }
                },
              ),
      ));
      return picked;
    } catch (e) {
      if (before != null) onChanged?.call(key, before);
      _snack(messenger, formatApiError(e));
      return null;
    }
  }

  /// Tall sheet: the record's comment thread + composer (reply, attach).
  static Future<void> openComments(BuildContext context, {required String module, required Map<String, dynamic> row}) {
    return showNxSnapSheet<void>(
      context: context,
      title: tr('อัปเดตคอมเมนต์'),
      snaps: const [0.6, 0.92],
      initial: 0.6,
      builder: (ctx, controller) => _CommentsSheet(module: module, row: row, controller: controller),
    );
  }

  /// Edit form for the record; true when saved.
  static Future<bool> edit(
    BuildContext context, {
    required String module,
    required Map<String, dynamic> row,
    List<Map<String, dynamic>>? fields,
    Map<String, List<Map<String, dynamic>>>? picklists,
    bool? root,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    var full = row;
    var f = fields;
    var p = picklists;
    if (f == null || p == null) {
      try {
        final l = await load(context, module, row);
        full = l.row;
        f = l.schema?.fields ?? const [];
        p = l.schema?.picklists ?? const {};
      } catch (e) {
        _snack(messenger, formatApiError(e));
        return false;
      }
    }
    if (!context.mounted) return false;
    final saved = await nxPush<bool>(
      context,
      EntityCreateScreen(
        module: module,
        title: 'แก้ไข',
        recordId: '${full['id']}',
        initialValues: Map<String, dynamic>.from(full),
        fields: editableFields(f, full),
        picklists: p,
      ),
      root: root,
    );
    if (saved == true) _snack(messenger, 'บันทึกแล้ว');
    return saved == true;
  }

  /// Duplicate like the web: a pre-filled form to review the copy; documents
  /// (quotation / job) are copied on the server with their lines.
  static Future<bool> duplicate(
    BuildContext context, {
    required String module,
    required Map<String, dynamic> row,
    List<Map<String, dynamic>>? fields,
    Map<String, List<Map<String, dynamic>>>? picklists,
    bool? root,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final config = context.read<AppConfig>();
    final title = entityTitle(row, module: module);
    if (!kServerDuplicateModules.contains(module)) {
      var full = row;
      var f = fields;
      var p = picklists;
      if (f == null || p == null) {
        try {
          final l = await load(context, module, row);
          full = l.row;
          f = l.schema?.fields ?? const [];
          p = l.schema?.picklists ?? const {};
        } catch (e) {
          _snack(messenger, formatApiError(e));
          return false;
        }
      }
      if (f.isNotEmpty) {
        final values = duplicateFormValues(module, full, userId: config.session.userId, picklists: p);
        if (values['smownerid'] != null) {
          values['smownerid'] = {
            'id': '${values['smownerid']}',
            'label': config.session.displayName ?? config.session.email ?? '${values['smownerid']}',
          };
        }
        if (!context.mounted) return false;
        final saved = await nxPush<bool>(
          context,
          EntityCreateScreen(
            module: module,
            title: 'ทำซ้ำ ${entityTitle(full, module: module)}',
            initialValues: values,
            fields: editableFields(f, full),
            picklists: p,
          ),
          root: root ?? true,
        );
        if (saved == true) _snack(messenger, 'ทำซ้ำแล้ว');
        return saved == true;
      }
    }
    if (!context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(NxI.copySimple),
        title: Text(tr('ทำซ้ำรายการนี้?')),
        content: Text(tr('สร้างสำเนาของ $title')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ทำซ้ำ'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return false;
    try {
      final newId = await config.apiClient.duplicateEntity(module, '${row['id']}');
      if (newId.isEmpty) return false;
      _snack(messenger, 'ทำซ้ำแล้ว — เปิดรายการใหม่');
      if (context.mounted) nxPush<void>(context, EntityByIdLoader(module: module, id: newId), root: root);
      return true;
    } catch (e) {
      _snack(messenger, formatApiError(e));
      return false;
    }
  }

  /// Confirm, then delete with a 5 s undo. True when scheduled.
  static Future<bool> delete(
    BuildContext context, {
    required String module,
    required Map<String, dynamic> row,
    VoidCallback? onCommitted,
  }) async {
    final title = entityTitle(row, module: module);
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(NxI.trash, color: cs.error),
        title: Text(tr('ลบรายการนี้?')),
        content: Text(tr('ลบ $title')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('ลบ')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return false;
    final api = context.read<AppConfig>().apiClient;
    final id = '${row['id']}';
    PendingEntityDeletes.instance.schedule(
      messenger: ScaffoldMessenger.of(context),
      module: module,
      ids: [id],
      label: title,
      commit: () async {
        await api.deleteEntity(module, id);
        onCommitted?.call();
      },
    );
    return true;
  }
}

/// Status choices as coloured rows; the current one is ticked.
class EntityStatusPickList extends StatelessWidget {
  const EntityStatusPickList({super.key, required this.options, required this.current});

  final List<({String value, String label, String? color})> options;
  final String? current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, o) in options.indexed)
          () {
            final c = EntityRecordActions.statusColor(cs, o.value, o.color);
            final sel = o.value == current || o.label == current;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: sel ? c.withValues(alpha: 0.14) : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: sel ? c : Colors.transparent, width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('status-opt-${o.value}'),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pop(context, o.value);
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: c.withValues(alpha: 0.18), shape: BoxShape.circle),
                            child: Text(
                              '${i + 1}',
                              style: theme.textTheme.labelMedium?.copyWith(color: c, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              tr(o.label),
                              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: sel ? FontWeight.w700 : FontWeight.w500),
                            ),
                          ),
                          if (sel) Icon(NxI.checkCircle, color: c) else Icon(NxI.caretRight, size: 18, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }(),
      ],
    );
  }
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.module, required this.row, required this.controller});

  final String module;
  final Map<String, dynamic> row;
  final ScrollController controller;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  List<Map<String, dynamic>>? _comments;
  Object? _error;

  String get _id => '${widget.row['id'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await context.read<AppConfig>().apiClient.getEntityComments(widget.module, _id);
      if (mounted) setState(() => _comments = rows);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListView(
      controller: widget.controller,
      padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.paddingOf(context).bottom + 20),
      children: [
        Row(
          children: [
            Icon(NxI.chatCircle, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entityTitle(widget.row, module: widget.module),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_error != null && _comments == null)
          NxErrorRetry(error: _error!, onRetry: () {
            setState(() => _error = null);
            _load();
          })
        else if (_comments == null)
          const NxSkeletonList(rows: 3)
        else
          EntityCommentsPanel(module: widget.module, id: _id, comments: _comments!, onChanged: _load),
      ],
    );
  }
}

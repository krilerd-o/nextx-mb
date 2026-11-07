import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
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
import '../../widgets/nx_surface_card.dart';
import '../deep_link_loaders.dart';
import '../jobs/job_inspection_screen.dart';
import 'entity_create_screen.dart';
import 'entity_detail_parts.dart';
import 'entity_ops.dart';
import '../../core/error_reporting.dart';
import '../../core/i18n.dart';
import '../../core/effects.dart';
import '../../core/entity_form_rules.dart';
import '../../core/recent_records.dart';
import '../../core/detail_fields_pref.dart';
import '../calendar/activity_detail_screen.dart';
import 'package:share_plus/share_plus.dart';

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
  List<Map<String, dynamic>> _comments = [];
  List<Map<String, dynamic>> _tags = [];
  List<Map<String, dynamic>> _catalog = [];
  List<Map<String, dynamic>> _fields = [];
  Map<String, List<Map<String, dynamic>>> _picklists = {};
  bool _loading = true;
  Object? _error;
  late Map<String, dynamic> _row;
  int _tab = 0;
  List<Map<String, dynamic>> _timeline = [];
  bool _timelineLoading = false;
  bool _timelineLoaded = false;

  String get _id => strId(widget.row['id']);

  @override
  void initState() {
    super.initState();
    _row = Map<String, dynamic>.from(widget.row);
    _reload();
    if (widget.module == 'case') _loadFollow();
    if (context.read<AppConfig>().isLoggedIn) {
      context.read<AppConfig>().apiClient.getUsersCached().then((u) {
        if (mounted) setState(() => _users = u);
      }).catchError((_) {});
    }
  }

  /// Business users (cached) so owner/assignee fields show names, not ids.
  List<Map<String, dynamic>> _users = const [];

  final _heroScroll = ScrollController();

  @override
  void dispose() {
    _heroScroll.dispose();
    super.dispose();
  }

  /// Case watchers: whether I follow this case (server supports cases only).
  bool? _following;

  Future<void> _loadFollow() async {
    try {
      final w = await context.read<AppConfig>().apiClient.getCaseWatchers(_id);
      if (mounted) setState(() => _following = w['following'] == true);
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    final next = !(_following ?? false);
    setState(() => _following = next);
    try {
      await context.read<AppConfig>().apiClient.setCaseFollow(_id, next);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(next ? 'ติดตามเคสนี้แล้ว — จะได้รับแจ้งเตือนเมื่อมีความเคลื่อนไหว' : 'เลิกติดตามแล้ว'))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _following = !next);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  /// Web link to this record (opens NEXTX on the web, or this app via deep link).
  Future<void> _shareLink() async {
    final base = Uri.tryParse(context.read<AppConfig>().apiBaseUrl);
    if (base == null) return;
    final url = base.replace(path: '/modules/${widget.module}/view/$_id', query: null).toString();
    final title = entityTitle(_row, module: widget.module);
    await Share.share('$title\n$url', subject: title);
  }

  /// Opened records feed Home's "เปิดล่าสุด".
  void _rememberRecent() {
    final config = context.read<AppConfig>();
    RecentRecords.instance.add(
      config.prefsScope,
      module: widget.module,
      id: _id,
      title: entityTitle(_row, module: widget.module),
    );
  }

  Future<bool?> _createLinkedActivity() {
    return nxPush<bool>(
      context,
      EntityCreateScreen(
        module: 'activity',
        title: 'สร้างนัดหมาย',
        initialValues: {
          'related_module': widget.module,
          'related_id': int.tryParse(_id) ?? _id,
          'subject': entityTitle(_row, module: widget.module),
          if (_row['account_name'] != null) 'account_name': _row['account_name'],
        },
      ),
      root: true,
    );
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
      } catch (e, s) {
        ErrorReporting.report(e, s);
      }
      try {
        final schema = await api.getFieldSchema(widget.module);
        fields = schema.fields;
        picklists = schema.picklists;
      } catch (e, s) {
        ErrorReporting.report(e, s);
      }
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
      _rememberRecent();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadTimeline({bool force = false}) async {
    if ((_timelineLoaded && !force) || _timelineLoading) return;
    setState(() => _timelineLoading = true);
    try {
      final rows = await context.read<AppConfig>().apiClient.getEntityTimeline(
        widget.module,
        _id,
      );
      if (!mounted) return;
      setState(() {
        _timeline = rows;
        _timelineLoaded = true;
      });
    } catch (e, s) {
      ErrorReporting.report(e, s);
    } finally {
      if (mounted) setState(() => _timelineLoading = false);
    }
  }

  String _valueLabel(String field, String value) {
    for (final o in _picklists[field] ?? const <Map<String, dynamic>>[]) {
      final p = NxPickOption.fromMap(o);
      if (p.value == value) return p.label;
    }
    return value;
  }

  List<({String value, String label})> _statusOptions(String? key) {
    if (key == null) return const [];
    return [
      for (final o in _picklists[key] ?? const <Map<String, dynamic>>[])
        () {
          final p = NxPickOption.fromMap(o);
          return (value: p.value, label: p.label);
        }(),
    ];
  }

  Future<void> _changeStatus(String key, String value) async {
    final before = _row[key];
    setState(() => _row = {..._row, key: value});
    try {
      await context.read<AppConfig>().apiClient.putEntity(widget.module, _id, {
        key: value,
      });
      _timelineLoaded = false;
      if (_tab == 3) _loadTimeline(force: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _row = {..._row, key: before});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  Future<void> _duplicate() async {
    // Like the web: most modules open a pre-filled form to review the copy;
    // documents (quotation / job) are copied on the server with their lines.
    if (!kServerDuplicateModules.contains(widget.module) && _fields.isNotEmpty) {
      final config = context.read<AppConfig>();
      final values = duplicateFormValues(
        widget.module,
        _row,
        userId: config.session.userId,
        picklists: _picklists,
      );
      if (values['smownerid'] != null) {
        values['smownerid'] = {
          'id': '${values['smownerid']}',
          'label': config.session.displayName ?? config.session.email ?? '${values['smownerid']}',
        };
      }
      final saved = await nxPush<bool>(
        context,
        EntityCreateScreen(
          module: widget.module,
          title: 'ทำซ้ำ ${entityTitle(_row, module: widget.module)}',
          initialValues: values,
          fields: _editableFields(),
          picklists: _picklists,
        ),
        root: true,
      );
      if (saved == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ทำซ้ำแล้ว'))));
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ทำซ้ำรายการนี้?')),
        content: Text(
          tr('สร้างสำเนาของ ${entityTitle(_row, module: widget.module)}'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('ยกเลิก')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('ทำซ้ำ')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final newId = await context.read<AppConfig>().apiClient.duplicateEntity(
        widget.module,
        _id,
      );
      if (!mounted || newId.isEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('ทำซ้ำแล้ว — เปิดรายการใหม่'))),
      );
      nxPush<void>(context, EntityByIdLoader(module: widget.module, id: newId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  /// Camera / gallery / file → posted as a comment with attachments.
  Future<void> _quickAttach() async {
    final files = await pickAttachments(context);
    if (files.isEmpty || !mounted) return;
    final api = context.read<AppConfig>().apiClient;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(tr('กำลังอัปโหลด…'))));
    try {
      final atts = await api.uploadCommentAttachments(files);
      await api.postEntityComment(widget.module, _id, '', attachments: atts);
      messenger.hideCurrentSnackBar();
      await _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
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
    final session = context.select((AppConfig c) => c.session);
    final title = entityTitle(_row, module: widget.module);
    final people = entityPeopleLine(_row);
    final status = entityStatus(_row);

    final canEdit = _editableFields().isNotEmpty || _fields.isEmpty;
    final statusKey = entityStatusKey(_row, widget.module);
    final statusOptions = _statusOptions(statusKey);
    return NxScrollScaffold(
      insetBody: false,
      header: NxAppHeader(
        title: title,
        automaticallyImplyLeading: !widget.embedded,
        actions: [
          if (widget.module == 'quotation' ||
              widget.module == 'inspection' ||
              widget.module == 'job') ...[
            IconButton(
              tooltip: tr('เปิด PDF'),
              icon: const Icon(NxI.filePdf),
              onPressed: _openPdf,
            ),
            IconButton(
              tooltip: tr('แชร์ PDF'),
              icon: const Icon(NxI.shareNetwork),
              onPressed: _sharePdf,
            ),
          ],
          if (canEdit)
            IconButton(
              tooltip: tr('แก้ไข'),
              icon: const Icon(NxI.pencilSimple),
              onPressed: () => _openEdit(context),
            ),
        ],
        menu: canEdit && context.select((AppConfig c) => c.isLoggedIn)
            ? [
                NxHeaderMenuItem(
                  label: 'ทำซ้ำ',
                  icon: NxI.copySimple,
                  onTap: _duplicate,
                ),
                NxHeaderMenuItem(
                  label: 'แชร์ลิงก์',
                  icon: NxI.shareNetwork,
                  onTap: _shareLink,
                ),
                if (widget.module == 'case' && _following != null)
                  NxHeaderMenuItem(
                    label: _following! ? 'เลิกติดตามเคส' : 'ติดตามเคส',
                    icon: _following! ? NxI.bellSlash : NxI.bellRinging,
                    onTap: _toggleFollow,
                  ),
                NxHeaderMenuItem(
                  label: 'ถ่ายรูป / แนบไฟล์',
                  icon: NxI.camera,
                  onTap: _quickAttach,
                ),
                NxHeaderMenuItem(
                  label: 'ลบ',
                  icon: NxI.trash,
                  onTap: _confirmDelete,
                ),
              ]
            : null,
      ),
      body: Builder(
        builder: (context) => RefreshIndicator(
          edgeOffset: NxScrollScaffold.topInset(context),
          color: theme.colorScheme.primary,
          onRefresh: _reload,
          child: ListView(
            controller: _heroScroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              8 + NxScrollScaffold.topInset(context),
              16,
              28,
            ),
            children: [
              NxSurfaceCard(
                radius: 28,
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
                child: Column(
                  children: [
                    // Lite "metaball": the avatar shrinks, rises and melts into
                    // the header as you scroll.
                    AnimatedBuilder(
                      animation: _heroScroll,
                      builder: (context, child) {
                        if (!Effects.animate(context) || !_heroScroll.hasClients) return child!;
                        final t = (_heroScroll.offset / 140).clamp(0.0, 1.0);
                        return Opacity(
                          opacity: 1 - t * 0.85,
                          child: Transform.translate(
                            offset: Offset(0, -26 * t),
                            child: Transform.scale(scale: 1 - 0.5 * t, child: child),
                          ),
                        );
                      },
                      child: Hero(
                        tag: 'entity-${widget.module}-$_id',
                        child: NxAvatar(label: title, size: 76),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tr(title),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (people != null && people.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        tr(people),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (status != null && statusOptions.isEmpty) ...[
                      const SizedBox(height: 10),
                      Chip(
                        label: Text(tr(status)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                    const SizedBox(height: 12),
                    EntityQuickActions(
                      row: _row,
                      onDuplicate: canEdit ? _duplicate : null,
                    ),
                  ],
                ),
              ),
              if (statusOptions.isNotEmpty) ...[
                const SizedBox(height: 12),
                EntityStatusStepper(
                  options: statusOptions,
                  current: statusKey == null
                      ? null
                      : _row[statusKey]?.toString(),
                  onSelect: canEdit
                      ? (v) => _changeStatus(statusKey!, v)
                      : null,
                ),
              ],
              const SizedBox(height: 14),
              NxSegmented(
                labels: [
                  'ข้อมูล',
                  _comments.isEmpty
                      ? 'ความคิดเห็น'
                      : 'ความคิดเห็น ${_comments.length}',
                  'ไฟล์',
                  'ประวัติ',
                  if (widget.module != 'activity') 'กิจกรรม',
                ],
                index: _tab,
                onChanged: (i) {
                  setState(() => _tab = i);
                  if (i == 3) _loadTimeline();
                },
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
                      Text(
                        tr(formatApiError(_error!)),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      TextButton(
                        onPressed: _reload,
                        child: Text(tr('ลองใหม่')),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              if (!_loading)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                    key: ValueKey(_tab),
                    child: switch (_tab) {
                      1 => EntityCommentsPanel(
                        module: widget.module,
                        id: _id,
                        comments: _comments,
                        onChanged: _reload,
                      ),
                      2 => EntityFilesPanel(
                        comments: _comments,
                        onAdd: _quickAttach,
                      ),
                      3 => EntityHistoryPanel(
                        events: _timeline,
                        loading: _timelineLoading,
                        valueLabel: _valueLabel,
                      ),
                      4 => EntityActivitiesPanel(
                        module: widget.module,
                        id: _id,
                        title: entityTitle(_row, module: widget.module),
                        onOpen: (r) => nxPush<void>(context, ActivityDetailScreen(row: r), root: true),
                        onCreate: _createLinkedActivity,
                      ),
                      _ => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.module == 'job' &&
                              MenuAccess.allow(
                                session,
                                MenuAccess.inspection,
                              )) ...[
                            const SizedBox(height: 16),
                            NxHeroCta(
                              label: 'สร้างใบตรวจรับ',
                              onPressed: () => nxPush<void>(
                                context,
                                JobInspectionScreen(job: _row),
                              ),
                            ),
                          ],
                          Builder(builder: (context) {
                            final rows = _valueRows();
                            return NxSurfaceCard(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6, bottom: 6),
                                    child: _fieldsToggle(),
                                  ),
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 220),
                                    alignment: Alignment.topCenter,
                                    child: Column(children: rows),
                                  ),
                                ],
                              ),
                            );
                          }),
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
                                    ? EntityDetailScreen(
                                        module: module,
                                        row: {...row, 'id': id},
                                      )
                                    : EntityByIdLoader(module: module, id: id),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          Text(tr('แท็ก'), style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          NxSurfaceCard(
                            padding: const EdgeInsets.all(12),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final t in _tags)
                                  InputChip(
        deleteIcon: const Icon(NxI.x, size: 16),
                                    label: Text(tr(t['name']?.toString() ?? '')),
                                    onDeleted: () => _toggleTag(t),
                                  ),
                                ActionChip(
                                  label: Text(tr('เลือกแท็ก')),
                                  onPressed: _catalog.isEmpty
                                      ? null
                                      : _pickTags,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    },
                  ),
                ),
            ],
          ),
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
                title: Text(tr(t['name']?.toString() ?? '')),
                value: _tags.any(
                  (x) => x['id']?.toString() == t['id']?.toString(),
                ),
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

  /// "มีข้อมูล" (default, remembered) vs "ทั้งหมด".
  bool _showAllFields = DetailFieldsPref.showAll;
  int _allFieldCount = 0;

  static bool _hasValue(dynamic v) {
    if (v == null) return false;
    if (v is String) {
      final t = v.trim();
      return t.isNotEmpty && t != 'null' && t != '[]' && t != '{}' && t != '0000-00-00';
    }
    if (v is Iterable) return v.isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    return true;
  }

  /// Header of the details card. Call after [_valueRows] (it sets the count).
  Widget _fieldsToggle() {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(tr('รายละเอียด'), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall)),
        Flexible(
          flex: 3,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: SegmentedButton<bool>(
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: false, label: Text(tr('มีข้อมูล'))),
            ButtonSegment(value: true, label: Text(tr('ทั้งหมด ($_allFieldCount)'))),
          ],
          selected: {_showAllFields},
          onSelectionChanged: (v) {
            setState(() => _showAllFields = v.first);
            DetailFieldsPref.set(v.first);
          },
            ),
          ),
        ),
      ],
    );
  }

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
    _allFieldCount = keys.length;
    // Default: only fields that have a value; "ทั้งหมด" shows every field.
    if (!_showAllFields) {
      keys.removeWhere((k) {
        final f = byName[k];
        // A yes/no left at "no" is the default, not information.
        if (f != null && resolveFieldUiType(f) == FieldUiType.yesNo) {
          final v = '${_row[k] ?? ''}'.toLowerCase();
          return v.isEmpty || v == '0' || v == 'false' || v == 'no';
        }
        return !_hasValue(_row[k]);
      });
    }
    if (keys.isEmpty) {
      return [Padding(padding: const EdgeInsets.all(8), child: Text(tr('ยังไม่มีข้อมูล — แตะ "ทั้งหมด" เพื่อดูทุกฟิลด์')))];
    }
    return [
      for (final name in keys)
        () {
          var uiType = byName[name] == null
              ? FieldUiType.text
              : resolveFieldUiType(byName[name]!);
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
              for (final o
                  in _picklists[name] ?? const <Map<String, dynamic>>[])
                NxPickOption.fromMap(o),
              // Owner / assignee ids → names.
              if (uiType == FieldUiType.picklistUser || uiType == FieldUiType.multiPicklistUser || uiType == FieldUiType.owner || name == 'smownerid')
                for (final u in _users) NxPickOption.fromMap(u),
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
      return (
        bytes: await api.getInspectionPdf(_id),
        name: 'inspection-$_id.pdf',
      );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  Future<void> _sharePdf() async {
    try {
      final pdf = await _pdfPayload();
      await sharePdfBytes(pdf.bytes, pdf.name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ลบรายการนี้?')),
        content: Text(tr('ลบ ${entityTitle(_row, module: widget.module)}')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('ยกเลิก')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('ลบ')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final api = context.read<AppConfig>().apiClient;
    PendingEntityDeletes.instance.schedule(
      messenger: ScaffoldMessenger.of(context),
      module: widget.module,
      ids: [_id],
      label: entityTitle(_row, module: widget.module),
      commit: () => api.deleteEntity(widget.module, _id),
    );
    if (!widget.embedded) Navigator.of(context).maybePop();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('บันทึกแล้ว'))));
      _reload();
    }
  }
}

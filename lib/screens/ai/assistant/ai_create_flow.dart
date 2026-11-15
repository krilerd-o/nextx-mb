import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/ai_fill.dart';
import '../../../core/app_config.dart';
import '../../../core/entity_modules.dart';
import '../../../core/i18n.dart';
import '../../../core/menu_access.dart';
import '../../../core/workspace_models.dart';
import '../../../services/api_client.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../../widgets/nx_icons.dart';
import '../../crm/entity_create_screen.dart';
import '../../doc_form/doc_form_launcher.dart';
import '../../workspace/workspace_item_form.dart';

/// A record made from the chat's create command.
class AiCreated {
  const AiCreated({required this.module, required this.id, required this.title, required this.values, required this.link, this.kind});
  final String module;
  final String id;
  final String title;
  final Map<String, dynamic> values;
  final String link;
  final String? kind;
}

/// Thai name of what a create command makes.
String aiCreateNoun(String module, {String? kind}) => switch (module) {
  'activity' => 'นัดหมาย',
  'workspace_item' => kind == 'epic' ? 'Epic' : 'งานบนบอร์ด',
  'quotation' => 'ใบเสนอราคา',
  'account' => 'บัญชีลูกค้า',
  'case' => 'เคส',
  'contact' => 'Contact',
  'lead' => 'Lead',
  _ => EntityModules.titleOf(module),
};

/// "สร้าง Lead" / "สร้างนัดหมาย" (a space before Latin names).
String aiCreateLabel(String module, {String? kind}) {
  final n = aiCreateNoun(module, kind: kind);
  return RegExp(r'^[A-Za-z]').hasMatch(n) ? 'สร้าง $n' : 'สร้าง$n';
}

/// Can this user create [module] (menu access like the rest of the app)?
bool aiCanCreate(BuildContext context, String module) {
  final session = context.read<AppConfig>().session;
  if (module == 'workspace_item') return MenuAccess.allow(session, MenuAccess.workspace);
  return MenuAccess.allow(session, EntityModules.menuKeyOf(module));
}

/// In-app link to a new record (same shapes the server's entityLink uses).
String aiRecordLink(String module, String id, {String? boardId, String? kind}) => switch (module) {
  'activity' => '/calendar?open=$id',
  'workspace_item' => '/workspace?board=$boardId&${kind == 'epic' ? 'epic' : 'task'}=$id',
  _ => '/modules/$module/view/$id',
};

/// Main text of a record for titles / the chat card.
String aiRecordTitle(String module, Map<String, dynamic> v) {
  String s(String k) => aiFillDisplay(v[k]).trim();
  final name = switch (module) {
    'lead' || 'contact' => [s('${module}_firstname'), s('${module}_lastname')].where((e) => e.isNotEmpty).join(' '),
    'account' => s('account_name'),
    'case' => s('case_name'),
    'activity' => s('subject'),
    'quotation' => s('subject').isNotEmpty ? s('subject') : s('title_th'),
    'workspace_item' => s('title'),
    _ => '',
  };
  if (name.isNotEmpty) return name;
  for (final k in ['${module}_name', 'name', 'title', 'subject', 'company_name']) {
    if (s(k).isNotEmpty) return s(k);
  }
  return '';
}

/// Opens the create form for [module]: Isaac fills it from [text] (typed
/// after the command, or anything the user types / speaks in the form);
/// the user checks and saves. Returns the saved record, or null if left.
class AiCreateFlow {
  AiCreateFlow._();

  static Future<AiCreated?> run(
    BuildContext context, {
    required String module,
    String? kind,
    String text = '',
    Map<String, dynamic> initialValues = const {},
    String? contextModule,
    String? contextId,
    String? contextTitle,
    String Function()? chatText,
  }) async {
    final api = context.read<AppConfig>().apiClient;
    Future<AiFillResult> fill(String t) => api.extractAiFields(module, t, contextModule: contextModule, contextId: contextId, contextTitle: contextTitle);

    if (module == 'workspace_item') {
      return _workspace(context, api, kind: kind ?? 'task', text: text, initial: initialValues, fill: fill);
    }
    if (module == 'quotation') {
      var values = {...initialValues};
      var lines = const <Map<String, dynamic>>[];
      if (text.trim().isNotEmpty) {
        try {
          final r = await fill(text);
          values = {...values, ...r.values};
          lines = r.lines;
        } catch (_) {
          /* open the form anyway */
        }
      }
      if (!context.mounted) return null;
      final saved = await Navigator.of(context, rootNavigator: true).push<Map<String, dynamic>>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (ctx) => docFormScreen(
            module: 'quotation',
            initialValues: values,
            initialLines: lines.isEmpty ? null : lines,
            embedded: true,
            onFinished: (r) => Navigator.of(ctx).pop(r),
          ),
        ),
      );
      final id = '${saved?['id'] ?? ''}';
      if (id.isEmpty || id == 'null') return null;
      final v = {...values, ...?saved};
      return AiCreated(module: module, id: id, title: aiRecordTitle(module, v), values: v, link: aiRecordLink(module, id));
    }

    // Lead / Contact / Account / Case / Activity: the business's own form
    // (required fields, owner = me with a user picker, picklists).
    AiCreated? created;
    final base = {...initialValues};
    if (module == 'activity' && contextModule != null && contextId != null) {
      base['related_module'] ??= contextModule;
      base['related_id'] ??= contextId;
    }
    if (!context.mounted) return null;
    await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => EntityCreateScreen(
          module: module,
          title: tr(aiCreateLabel(module, kind: kind)),
          initialValues: base,
          genericForm: true,
          aiFill: fill,
          aiFillText: text,
          aiChatText: chatText,
          onCreated: (id, values) {
            created = AiCreated(module: module, id: id, title: aiRecordTitle(module, values), values: values, link: aiRecordLink(module, id));
          },
        ),
      ),
    );
    return created;
  }

  static Future<AiCreated?> _workspace(
    BuildContext context,
    ApiClient api, {
    required String kind,
    required String text,
    required Map<String, dynamic> initial,
    required AiFillFn fill,
  }) async {
    // Board first: given by Isaac's proposal, else picked (writable boards only).
    var boardId = '${initial['board_id'] ?? ''}';
    Map<String, dynamic>? board;
    if (boardId.isEmpty || boardId == 'null') {
      board = await _pickBoard(context, api);
      if (board == null) return null;
      boardId = '${board['id']}';
    }
    try {
      final r = await Future.wait([
        api.getBoardStatuses(boardId),
        api.getBoardEpics(boardId).catchError((_) => <Map<String, dynamic>>[]),
        api.getBoard(boardId).then<Map<String, dynamic>>((b) => b).catchError((_) => <String, dynamic>{}),
        api.getUsersCached().catchError((_) => <Map<String, dynamic>>[]),
      ]);
      final statuses = WsStatus.list(r[0] as List<Map<String, dynamic>>);
      final epics = r[1] as List<Map<String, dynamic>>;
      board = {...?board, ...(r[2] as Map<String, dynamic>), 'id': boardId};
      final users = {
        for (final u in r[3] as List<Map<String, dynamic>>)
          '${u['id']}': [u['first_name'], u['last_name']].where((e) => e != null && '$e'.isNotEmpty).join(' ').trim(),
      };
      var values = {...initial}..remove('board_id');
      if (text.trim().isNotEmpty) {
        try {
          final f = await fill(text);
          values = {...values, ...f.values};
        } catch (_) {
          /* form still opens */
        }
      }
      // Assignee by id → show the name in the picker.
      final a = values['assignee_id'];
      if (a != null && a is! Map) values['assignee_id'] = {'id': '$a', 'label': users['$a'] ?? '$a'};
      if (!context.mounted) return null;
      final saved = await Navigator.of(context, rootNavigator: true).push<Map<String, dynamic>>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => WorkspaceItemFormScreen(board: board!, statuses: statuses, epics: epics, kind: kind, users: users, initial: values),
        ),
      );
      final id = '${saved?['id'] ?? ''}';
      if (saved == null || id.isEmpty || id == 'null') return null;
      final v = {...values, ...saved};
      final aid = '${saved['assignee_id'] ?? ''}';
      if (aid.isNotEmpty && users[aid] != null) v['assignee_id'] = {'id': aid, 'label': users[aid]};
      return AiCreated(
        module: 'workspace_item',
        kind: kind,
        id: id,
        title: aiRecordTitle('workspace_item', v),
        values: v,
        link: aiRecordLink('workspace_item', id, boardId: boardId, kind: kind),
      );
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _pickBoard(BuildContext context, ApiClient api) async {
    List<Map<String, dynamic>> boards;
    try {
      boards = await api.getBoards(writable: true);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      return null;
    }
    if (!context.mounted) return null;
    if (boards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ยังไม่มีบอร์ดที่คุณเพิ่มงานได้'))));
      return null;
    }
    if (boards.length == 1) return boards.first;
    return showAppBottomSheet<Map<String, dynamic>>(
      context: context,
      title: 'เลือกบอร์ด',
      child: Column(
        key: const ValueKey('ai-board-picker'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final b in boards)
            ListTile(
              key: ValueKey('ai-board-${b['id']}'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(NxI.kanban),
              title: Text('${b['name'] ?? b['title'] ?? b['id']}'),
              onTap: () => Navigator.pop(context, b),
            ),
        ],
      ),
    );
  }
}

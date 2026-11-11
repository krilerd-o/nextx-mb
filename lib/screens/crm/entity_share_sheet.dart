import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_icons.dart';

const _perms = ['read_only', 'edit', 'full'];

String sharePermLabel(String p) => tr(switch (p) {
  'edit' => 'แก้ไขได้',
  'full' => 'สิทธิ์เต็ม (รวมลบ)',
  _ => 'ดูอย่างเดียว',
});

/// Share a record with users or roles (same as the web's share window):
/// list who has access, change permission, remove, add — then save all.
Future<void> showEntityShareSheet(BuildContext context, {required String module, required String id, String? title}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SizedBox(height: MediaQuery.of(context).size.height * 0.85, child: _ShareSheet(module: module, id: id, title: title)),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.module, required this.id, this.title});
  final String module;
  final String id;
  final String? title;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  List<Map<String, dynamic>> _draft = [];
  String _original = '';
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _roles = [];
  bool _loading = true;
  bool _saving = false;
  Object? _error;
  String _addType = 'user';
  String _q = '';

  ApiClient get _api => context.read<AppConfig>().apiClient;

  String _key(Map r) => '${r['share_to_type']}:${r['share_to_id']}';
  String _sig(List<Map<String, dynamic>> l) => ([for (final r in l) '${_key(r)}=${r['permission']}']..sort()).join('|');
  bool get _dirty => _sig(_draft) != _original;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final shares = await _api.getEntityShares(widget.module, widget.id);
      final users = await _api.getUsersCached().catchError((_) => <Map<String, dynamic>>[]);
      final roles = await _api.getRoles().catchError((_) => <Map<String, dynamic>>[]);
      final own = [
        for (final s in shares)
          if ('${s['entity_id'] ?? widget.id}' == widget.id)
            {'share_to_type': '${s['share_to_type']}', 'share_to_id': s['share_to_id'], 'permission': _perms.contains(s['permission']) ? s['permission'] : 'read_only'},
      ];
      if (!mounted) return;
      setState(() {
        _draft = own;
        _original = _sig(own);
        _users = users;
        _roles = roles;
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

  String _name(Map r) {
    final id = '${r['share_to_id']}';
    if (r['share_to_type'] == 'role') return '${_roles.where((x) => '${x['id']}' == id).firstOrNull?['name'] ?? 'Role #$id'}';
    final u = _users.where((x) => strId(x['id'] ?? x['user_id']) == id).firstOrNull;
    return u == null ? '#$id' : userDisplayName(u);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _api.saveEntityShares(widget.module, widget.id, [
        for (final r in _draft) {'share_to_type': r['share_to_type'], 'share_to_id': int.tryParse('${r['share_to_id']}') ?? r['share_to_id'], 'permission': r['permission']},
      ]);
      HapticFeedback.mediumImpact();
      setState(() => _original = _sig(_draft));
      messenger.showSnackBar(SnackBar(content: Text(tr('บันทึกการแชร์แล้ว'))));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final taken = {for (final r in _draft) _key(r)};
    final candidates = _addType == 'role'
        ? [for (final r in _roles) if (!taken.contains('role:${r['id']}') && '${r['name'] ?? ''}'.toLowerCase().contains(_q.toLowerCase())) (id: '${r['id']}', name: '${r['name'] ?? ''}')]
        : [
            for (final u in _users)
              if (!taken.contains('user:${strId(u['id'] ?? u['user_id'])}') && userDisplayName(u).toLowerCase().contains(_q.toLowerCase()))
                (id: strId(u['id'] ?? u['user_id']), name: userDisplayName(u)),
          ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('แชร์ให้ผู้ใช้ / Role'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            if (widget.title != null) Text(widget.title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)))
        else if (_error != null)
          Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(tr(formatApiError(_error!)), textAlign: TextAlign.center))))
        else
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              Text(tr('ผู้ที่เข้าถึงได้'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              if (_draft.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(tr('ยังไม่ได้แชร์ให้ใคร'), style: TextStyle(color: cs.onSurfaceVariant))),
              for (final r in _draft)
                Card(
                  key: ValueKey('share-row-${_key(r)}'),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                    child: Row(children: [
                      Icon(r['share_to_type'] == 'role' ? NxI.users : NxI.user, size: 20, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_name(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                      DropdownButton<String>(
                        value: '${r['permission']}',
                        underline: const SizedBox.shrink(),
                        items: [for (final p in _perms) DropdownMenuItem(value: p, child: Text(sharePermLabel(p), style: const TextStyle(fontSize: 13)))],
                        onChanged: (v) => setState(() => r['permission'] = v ?? 'read_only'),
                      ),
                      IconButton(tooltip: tr('เอาออก'), onPressed: () => setState(() => _draft.remove(r)), icon: Icon(NxI.x, size: 18, color: cs.error)),
                    ]),
                  ),
                ),
              const SizedBox(height: 14),
              Text(tr('เพิ่ม'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'user', icon: const Icon(NxI.user, size: 16), label: Text(tr('ผู้ใช้'))),
                  const ButtonSegment(value: 'role', icon: Icon(NxI.users, size: 16), label: Text('Role')),
                ],
                selected: {_addType},
                onSelectionChanged: (s) => setState(() => _addType = s.first),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('share-search'),
                decoration: InputDecoration(prefixIcon: const Icon(NxI.magnifyingGlass, size: 18), hintText: tr('ค้นหาชื่อ')),
                onChanged: (v) => setState(() => _q = v),
              ),
              for (final c in candidates.take(30))
                ListTile(
                  key: ValueKey('share-add-$_addType-${c.id}'),
                  dense: true,
                  leading: Icon(_addType == 'role' ? NxI.users : NxI.user, size: 18),
                  title: Text(c.name),
                  trailing: const Icon(NxI.plus, size: 18),
                  onTap: () => setState(() => _draft.add({'share_to_type': _addType, 'share_to_id': c.id, 'permission': 'read_only'})),
                ),
              const SizedBox(height: 16),
            ]),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              key: const ValueKey('share-save'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _dirty && !_saving ? _save : null,
              child: Text(_saving ? tr('กำลังบันทึก…') : tr('บันทึกการแชร์')),
            ),
          ),
        ),
      ]),
    );
  }
}

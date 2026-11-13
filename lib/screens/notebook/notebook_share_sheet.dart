import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/i18n.dart';
import '../../core/notebook/notebook_models.dart';
import '../../services/api_client.dart';
import '../../services/notebook/notebook_controller.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_sliding_segmented.dart';
import '../ai/web_session_screen.dart';
import 'notebook_widgets.dart';

/// Share a notebook: read-only public link, or inside the business to users /
/// roles / everyone; existing shares can be revoked.
Future<void> showNotebookShareSheet(BuildContext context, {required Notebook notebook}) {
  return showNxSnapSheet<void>(
    context: context,
    title: 'แชร์สมุดโน้ต',
    snaps: const [0.72, 0.94],
    builder: (ctx, scroll) => NotebookShareSheet(notebook: notebook, scroll: scroll),
  );
}

class NotebookShareSheet extends StatefulWidget {
  const NotebookShareSheet({super.key, required this.notebook, this.scroll});
  final Notebook notebook;
  final ScrollController? scroll;

  @override
  State<NotebookShareSheet> createState() => _NotebookShareSheetState();
}

class _NotebookShareSheetState extends State<NotebookShareSheet> {
  late final ApiClient _api = context.read<AppConfig>().apiClient;
  List<NotebookShare> _shares = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _link;

  /// users | roles | business
  String _mode = 'users';
  List<Map<String, dynamic>>? _users;
  List<Map<String, dynamic>>? _roles;
  final Set<String> _picked = {};
  final _q = TextEditingController();

  String get _origin => WebSessionScreen.webOrigin(context.read<AppConfig>().apiBaseUrl);

  @override
  void initState() {
    super.initState();
    _load();
    _loadTargets();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _api.getNotebookShares(widget.notebook.id);
      if (!mounted) return;
      setState(() {
        _shares = [for (final r in rows) NotebookShare.fromJson(r)];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = notebookError(e).text;
        });
      }
    }
  }

  Future<void> _loadTargets() async {
    if (_mode == 'users' && _users == null) {
      try {
        final u = await _api.getUsersCached();
        if (mounted) setState(() => _users = u);
      } catch (_) {
        if (mounted) setState(() => _users = const []);
      }
    } else if (_mode == 'roles' && _roles == null) {
      try {
        final r = await _api.getRoles();
        if (mounted) setState(() => _roles = r);
      } catch (_) {
        if (mounted) setState(() => _roles = const []);
      }
    }
  }

  String _url(String path) => '$_origin$path';

  Future<void> _createLink() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api.createNotebookShare(widget.notebook.id, mode: 'read_only');
      final item = r['item'] is Map ? NotebookShare.fromJson(Map<String, dynamic>.from(r['item'] as Map)) : null;
      final path = '${r['public_path'] ?? r['path'] ?? item?.path(widget.notebook.id) ?? ''}';
      final url = _url(path);
      await Clipboard.setData(ClipboardData(text: url));
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _link = url);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('คัดลอกลิงก์แล้ว'))));
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = notebookError(e).text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareInApp() async {
    if (_mode != 'business' && _picked.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.createNotebookShare(
        widget.notebook.id,
        mode: _mode,
        targets: [for (final id in _picked) (type: _mode == 'users' ? 'user' : 'role', id: id)],
      );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _picked.clear());
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('แชร์สมุดแล้ว'))));
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = notebookError(e).text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(NotebookShare s) async {
    final before = _shares;
    setState(() => _shares = _shares.where((x) => x.id != s.id).toList());
    try {
      await _api.revokeNotebookShare(widget.notebook.id, s.id);
      HapticFeedback.selectionClick();
    } catch (e) {
      if (mounted) {
        setState(() {
          _shares = before;
          _error = notebookError(e).text;
        });
      }
    }
  }

  String _targetLabel(({String type, String id}) t) {
    if (t.type == 'user') {
      final u = (_users ?? const []).where((x) => '${x['id']}' == t.id).firstOrNull;
      return u == null ? '#${t.id}' : userDisplayName(u);
    }
    final r = (_roles ?? const []).where((x) => '${x['id']}' == t.id).firstOrNull;
    return r == null ? tr('บทบาท #${t.id}') : '${r['name'] ?? r['code'] ?? t.id}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListView(
      controller: widget.scroll,
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        // Public link
        NotebookCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const NotebookIconBadge(icon: LucideIcons300.link, color: kNotebookAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('ลิงก์อ่านอย่างเดียว'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text(tr('ใครมีลิงก์ก็เปิดอ่านแหล่งข้อมูลและโน้ตได้ แก้ไขไม่ได้'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
            ]),
            if (_link != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const ValueKey('notebook-share-link'),
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Expanded(child: Text(_link!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)),
                  IconButton(
                    tooltip: tr('คัดลอก'),
                    icon: const Icon(NxI.copySimple, size: 18),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _link!));
                      if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('คัดลอกลิงก์แล้ว'))));
                    },
                  ),
                  IconButton(
                    tooltip: tr('แชร์'),
                    icon: const Icon(NxI.shareNetwork, size: 18),
                    onPressed: () => Share.share('${widget.notebook.title}\n$_link'),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const ValueKey('notebook-share-create-link'),
              onPressed: _busy ? null : _createLink,
              icon: const Icon(LucideIcons300.link2, size: 18),
              label: Text(tr(_link == null ? 'สร้างและคัดลอกลิงก์' : 'สร้างลิงก์ใหม่')),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        // In the business
        NotebookCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('แชร์ในธุรกิจ'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            NxSlidingSegmented<String>(
              value: _mode,
              options: const [('users', 'ผู้ใช้', NxI.user), ('roles', 'บทบาท', NxI.users), ('business', 'ทั้งธุรกิจ', LucideIcons300.building2)],
              onChanged: (v) {
                setState(() {
                  _mode = v;
                  _picked.clear();
                });
                _loadTargets();
              },
            ),
            const SizedBox(height: 10),
            if (_mode == 'business')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(tr('ทุกคนในธุรกิจนี้จะเห็นสมุดนี้ในคลัง "ทั้งธุรกิจ"'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              )
            else
              _targets(context),
            const SizedBox(height: 10),
            FilledButton(
              key: const ValueKey('notebook-share-in-app'),
              onPressed: _busy || (_mode != 'business' && _picked.isEmpty) ? null : _shareInApp,
              child: Text(_mode == 'business' ? tr('แชร์ให้ทั้งธุรกิจ') : tr('แชร์ให้ ${_picked.length} รายการ')),
            ),
          ]),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(tr(_error!), style: TextStyle(color: cs.error)),
          ),
        const NotebookSectionLabel('การแชร์ที่ใช้อยู่'),
        if (_loading)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        else if (_shares.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(tr('ยังไม่ได้แชร์สมุดนี้'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          )
        else
          for (final s in _shares)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NotebookCard(
                key: ValueKey('notebook-share-${s.id}'),
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(children: [
                  Icon(switch (s.mode) { 'users' => NxI.user, 'roles' => NxI.users, 'business' => LucideIcons300.building2, _ => LucideIcons300.link }, size: 20, color: kNotebookAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr(s.modeLabel), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                      if (s.targets.isNotEmpty)
                        Text(s.targets.map(_targetLabel).join(', '), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      if (s.mode == 'read_only')
                        Text(_url(s.path(widget.notebook.id)), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  if (s.mode == 'read_only')
                    IconButton(
                      tooltip: tr('คัดลอก'),
                      icon: const Icon(NxI.copySimple, size: 18),
                      onPressed: () => Clipboard.setData(ClipboardData(text: _url(s.path(widget.notebook.id)))),
                    ),
                  TextButton(
                    key: ValueKey('notebook-share-revoke-${s.id}'),
                    onPressed: () => _revoke(s),
                    style: TextButton.styleFrom(foregroundColor: cs.error),
                    child: Text(tr('เพิกถอน')),
                  ),
                ]),
              ),
            ),
      ],
    );
  }

  Widget _targets(BuildContext context) {
    final rows = _mode == 'users' ? _users : _roles;
    if (rows == null) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    final q = _q.text.trim().toLowerCase();
    String label(Map<String, dynamic> r) => _mode == 'users' ? userDisplayName(r) : '${r['name'] ?? r['code'] ?? r['id']}';
    final me = context.read<AppConfig>().session.userId;
    final list = [
      for (final r in rows)
        if ((_mode != 'users' || '${r['id']}' != me) && (q.isEmpty || label(r).toLowerCase().contains(q))) r,
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_mode == 'users')
        TextField(
          controller: _q,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(isDense: true, prefixIcon: const Icon(NxI.magnifyingGlass, size: 18), hintText: tr('ค้นหาผู้ใช้')),
        ),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: list.isEmpty
            ? Padding(padding: const EdgeInsets.all(12), child: Text(tr('ไม่พบรายการ'), textAlign: TextAlign.center))
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final r in list)
                    CheckboxListTile(
                      key: ValueKey('notebook-share-target-${r['id']}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _picked.contains('${r['id']}'),
                      title: Text(label(r), maxLines: 1, overflow: TextOverflow.ellipsis),
                      onChanged: (v) => setState(() => v == true ? _picked.add('${r['id']}') : _picked.remove('${r['id']}')),
                    ),
                ],
              ),
      ),
    ]);
  }
}

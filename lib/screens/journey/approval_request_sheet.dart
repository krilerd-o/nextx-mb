import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/entity_display.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_icons.dart';
import 'status_followups.dart' show journeyErrorText;

/// One approval level of the quotation settings (`approval.levels[]`).
class ApprovalLevel {
  const ApprovalLevel({required this.level, this.label, this.mode = 'any', this.candidates = const []});

  factory ApprovalLevel.fromMap(Map<String, dynamic> m) => ApprovalLevel(
        level: (m['level'] as num?)?.toInt() ?? int.tryParse('${m['level']}') ?? 1,
        label: '${m['label'] ?? ''}'.trim().isEmpty ? null : '${m['label']}'.trim(),
        mode: '${m['mode'] ?? 'any'}',
        candidates: [for (final c in (m['candidates'] as List? ?? const [])) if ('$c'.isNotEmpty) '$c'],
      );

  final int level;
  final String? label;

  /// 'any' (one of them) | 'all' (everyone).
  final String mode;

  /// User ids allowed at this level (empty = any business user). The
  /// settings hold ids only; names come from the user directory.
  final List<String> candidates;
}

/// Approver of a level as shown: the user row, or null when the directory
/// has no such user (shown as "ผู้ใช้ #id").
typedef ApproverEntry = ({String id, Map<String, dynamic>? user});

/// Name shown for an approver ("ผู้ใช้ #id" only when the user is unknown).
String approverName(ApproverEntry e) => e.user == null ? '${tr('ผู้ใช้')} #${e.id}' : userFullName(e.user!, thai: !L10n.isEn);

/// "ส่งขออนุมัติ": choose approvers per level (earlier levels may be skipped,
/// the last one is required — like the web's approval tab), then send.
///
/// The approver candidates in the settings are user ids; they are resolved to
/// names with one cached `/api/users` call ([loadUsers]) for all levels. Until
/// it answers the rows are placeholders, never raw ids.
///
/// [onSubmit] gets the server body (`[{level, user_ids:[int]}]`); the sheet
/// stays open with the error when it fails, and closes with the levels when
/// it succeeds. Without [onSubmit] the sheet just returns the levels.
class ApprovalRequestSheet extends StatefulWidget {
  const ApprovalRequestSheet({
    super.key,
    required this.levels,
    required this.loadUsers,
    this.preselected = const {},
    this.onSubmit,
    this.photoOf,
  });

  final List<ApprovalLevel> levels;
  final Future<List<Map<String, dynamic>>> Function() loadUsers;

  /// level → user ids already chosen (the previous chain, when resubmitting).
  final Map<int, Set<String>> preselected;
  final Future<void> Function(List<Map<String, dynamic>> levels)? onSubmit;

  /// Profile photo URL of a user id, if known.
  final String? Function(String id)? photoOf;

  @override
  State<ApprovalRequestSheet> createState() => _ApprovalRequestSheetState();
}

class _ApprovalRequestSheetState extends State<ApprovalRequestSheet> {
  late final Map<int, Set<String>> _picked = {
    for (final l in widget.levels) l.level: {...?widget.preselected[l.level]},
  };
  Map<String, Map<String, dynamic>>? _byId;
  List<Map<String, dynamic>> _all = const [];
  Object? _loadError;
  bool _sending = false;
  String? _sendError;
  String _q = '';

  int get _lastLevel => widget.levels.isEmpty ? 1 : widget.levels.last.level;
  bool get _loading => _byId == null && _loadError == null;
  bool get _ready => _picked[_lastLevel]?.isNotEmpty == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _byId = null;
      _loadError = null;
    });
    try {
      final users = await widget.loadUsers();
      if (!mounted) return;
      setState(() {
        _all = users;
        _byId = {for (final u in users) if (strId(u['id'] ?? u['user_id']).isNotEmpty) strId(u['id'] ?? u['user_id']): u};
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  /// People offered at [l]: its candidates (resolved), or every business
  /// user when it has none; plus anyone already picked there.
  List<ApproverEntry> _pool(ApprovalLevel l) {
    final byId = _byId ?? const <String, Map<String, dynamic>>{};
    final ids = <String>[
      ...(l.candidates.isNotEmpty ? l.candidates : [for (final u in _all) strId(u['id'] ?? u['user_id'])]),
    ];
    for (final p in _picked[l.level] ?? const <String>{}) {
      if (!ids.contains(p)) ids.add(p);
    }
    final seen = <String>{};
    return [
      for (final id in ids)
        if (id.isNotEmpty && seen.add(id)) (id: id, user: byId[id]),
    ];
  }

  bool _matches(ApproverEntry e) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return true;
    final u = e.user;
    final hay = [
      approverName(e),
      if (u != null) ...[userDisplayName(u), u['email1'], u['email'], u['user_name'], u['title'], u['department']],
    ].where((v) => v != null).join(' ').toLowerCase();
    return hay.contains(q);
  }

  void _toggle(int level, String id) {
    HapticFeedback.selectionClick();
    setState(() {
      final s = _picked[level]!;
      if (!s.remove(id)) s.add(id);
      _sendError = null;
    });
  }

  List<Map<String, dynamic>> get _body => [
        for (final l in widget.levels)
          if (_picked[l.level]?.isNotEmpty == true) {'level': l.level, 'user_ids': [for (final s in _picked[l.level]!) int.tryParse(s) ?? s]},
      ];

  Future<void> _send() async {
    final body = _body;
    final fn = widget.onSubmit;
    if (fn == null) {
      Navigator.pop(context, body);
      return;
    }
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await fn(body);
      if (mounted) Navigator.pop(context, body);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendError = journeyErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pools = {for (final l in widget.levels) l.level: _pool(l)};
    final searchable = !_loading && pools.values.any((p) => p.length > 8);
    final canSend = _ready && !_loading && !_sending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tr('เลือกผู้อนุมัติแต่ละระดับ — ข้ามระดับต้นได้ แต่ต้องเลือกระดับสุดท้าย อนุมัติเรียงตามระดับ'),
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (_loadError != null) ...[
          _Banner(
            key: const ValueKey('approval-users-error'),
            icon: NxI.warningCircle,
            color: cs.error,
            text: tr('โหลดชื่อผู้อนุมัติไม่สำเร็จ'),
            action: TextButton(key: const ValueKey('approval-users-retry'), onPressed: _load, child: Text(tr('ลองใหม่'))),
          ),
          const SizedBox(height: 12),
        ],
        if (searchable) ...[
          TextField(
            key: const ValueKey('approval-search'),
            decoration: InputDecoration(prefixIcon: const Icon(NxI.magnifyingGlass, size: 18), hintText: tr('ค้นหาชื่อ'), isDense: true),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 12),
        ],
        for (final l in widget.levels) ...[
          _levelCard(theme, l, pools[l.level]!),
          const SizedBox(height: 12),
        ],
        if (_sendError != null) ...[
          _Banner(key: const ValueKey('approval-send-error'), icon: NxI.warningCircle, color: cs.error, text: tr(_sendError!)),
          const SizedBox(height: 10),
        ] else if (!_ready && !_loading) ...[
          Text(
            tr('เลือกผู้อนุมัติระดับสุดท้ายก่อนส่ง'),
            key: const ValueKey('approval-need-last'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFB45309), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            key: const ValueKey('approval-submit'),
            onPressed: canSend ? _send : null,
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : const Icon(NxI.paperPlaneTilt, size: 18),
            label: Text(tr('ส่งขออนุมัติ')),
          ),
        ),
      ],
    );
  }

  Widget _levelCard(ThemeData theme, ApprovalLevel l, List<ApproverEntry> pool) {
    final cs = theme.colorScheme;
    final last = l.level == _lastLevel;
    final picked = _picked[l.level]!;
    final title = last
        ? '${tr(widget.levels.length == 1 ? 'ผู้อนุมัติ' : 'ระดับสุดท้าย')} · ${tr('ต้องเลือก')}'
        : '${tr('ระดับ')} ${l.level}';
    final sub = [
      if (l.label != null) l.label!,
      tr(l.mode == 'all' ? 'ครบทุกคน' : 'คนใดคนหนึ่ง'),
      if (picked.isNotEmpty) '${tr('เลือกแล้ว')} ${picked.length}',
    ].join(' · ');
    final shown = [for (final e in pool) if (_matches(e) || picked.contains(e.id)) e];
    return Container(
      key: ValueKey('approval-level-${l.level}'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: last && picked.isEmpty && !_loading ? const Color(0xFFF59E0B).withValues(alpha: 0.7) : cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Text('${l.level}', style: theme.textTheme.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text(sub, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          if (!last)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(99)),
              child: Text(tr('ข้ามได้'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
        ]),
        const SizedBox(height: 8),
        if (_loading)
          for (var i = 0; i < (l.candidates.isEmpty ? 3 : l.candidates.length.clamp(1, 4)); i++) _SkeletonRow(key: ValueKey('approver-skeleton-${l.level}-$i'))
        else if (pool.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(tr('ไม่มีรายชื่อผู้อนุมัติสำหรับระดับนี้'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          )
        else if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(tr('ไม่พบชื่อที่ค้นหา'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          )
        else
          for (final e in shown)
            _ApproverRow(
              key: ValueKey('approver-${l.level}-${e.id}'),
              entry: e,
              selected: picked.contains(e.id),
              photo: e.user == null ? null : widget.photoOf?.call(e.id),
              onTap: _sending ? null : () => _toggle(l.level, e.id),
            ),
      ]),
    );
  }
}

class _ApproverRow extends StatelessWidget {
  const _ApproverRow({super.key, required this.entry, required this.selected, this.photo, this.onTap});
  final ApproverEntry entry;
  final bool selected;
  final String? photo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final name = approverName(entry);
    final u = entry.user;
    final sub = u == null ? tr('ไม่พบผู้ใช้นี้ในรายชื่อ') : userSubtitle(u, thai: !L10n.isEn);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? cs.primary.withValues(alpha: 0.08) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? cs.primary.withValues(alpha: 0.55) : cs.outlineVariant.withValues(alpha: 0.45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Semantics(
            selected: selected,
            button: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                u == null
                    ? CircleAvatar(radius: 18, backgroundColor: cs.surfaceContainerHighest, child: Icon(NxI.user, size: 18, color: cs.onSurfaceVariant))
                    : NxAvatar(label: name, size: 36, imageUrl: photo),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (sub != null)
                      Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: selected
                      ? Icon(NxI.checkCircleFill, key: const ValueKey('on'), size: 24, color: cs.primary)
                      : Icon(NxI.circle, key: const ValueKey('off'), size: 24, color: cs.outline),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder row while the names load (no ids on screen).
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
    Widget bar(double w, double h) => Container(width: w, height: h, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            bar(140, 12),
            const SizedBox(height: 6),
            bar(90, 10),
          ]),
        ),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.icon, required this.color, required this.text, this.action});
  final IconData icon;
  final Color color;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600))),
        ?action,
      ]),
    );
  }
}

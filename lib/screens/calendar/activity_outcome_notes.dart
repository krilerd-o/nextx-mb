import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart' show ApiClient;
import '../../services/api_exceptions.dart' show formatApiError;
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_surface_card.dart';

/// One optional write-up of an activity (stored on `aicrm_activity`, same
/// columns the NEXTX web shows: `outcome_summary`, `next_step`, `remark`).
class ActivityOutcomeSection {
  const ActivityOutcomeSection(this.field, this.label, this.hint, this.icon, this.color);
  final String field;
  final String label;
  final String hint;
  final IconData icon;
  final Color color;
}

const kActivityOutcomeSections = [
  ActivityOutcomeSection('outcome_summary', 'สรุปผล', 'ลูกค้าสนใจอะไร ตกลงอะไรกันบ้าง', NxI.clipboardText, Color(0xFF16A34A)),
  ActivityOutcomeSection('next_step', 'ขั้นตอนถัดไป', 'จะทำอะไรต่อ เมื่อไร ใครรับผิดชอบ', NxI.arrowRight, Color(0xFF2563EB)),
  ActivityOutcomeSection('remark', 'หมายเหตุ', 'เรื่องที่ควรรู้เพิ่มเติม เช่น ข้อควรระวัง', NxI.note, Color(0xFFD97706)),
];

/// Seed of the "สร้างนัดหมายต่อ" form: same customer / place / guests,
/// subject = first line of the next step.
Map<String, dynamic> activityFollowUpSeed(Map<String, dynamic> row, String nextStep) {
  final text = nextStep.trim();
  final first = text.split('\n').first.trim();
  final subject = first.length > 120 ? '${first.substring(0, 120)}…' : first;
  final from = '${row['subject'] ?? ''}'.trim();
  return {
    for (final k in const [
      'activitytype',
      'related_module',
      'related_id',
      'customer_name',
      'customer_mobile',
      'customer_email',
      'account_name',
      'location',
      'location_lat',
      'location_lng',
      'event_locationmap',
      'landmark',
      'label_id',
      'attendees',
    ])
      if (row[k] != null && '${row[k]}'.isNotEmpty) k: row[k],
    'subject': subject,
    'description': [if (text != first) text, if (from.isNotEmpty) 'ต่อจากนัด: $from'].join('\n\n'),
  };
}

enum _SaveState { idle, pending, saving, saved, error }

/// Overview of an activity, under the description: สรุปผล / ขั้นตอนถัดไป /
/// หมายเหตุ. Empty sections sit as small "＋" chips; a chip opens an input card
/// that saves itself once typing stops; a filled section is a card (tap to edit).
class ActivityOutcomeNotes extends StatefulWidget {
  const ActivityOutcomeNotes({super.key, required this.activityId, required this.row, this.onSaved, this.onFollowUp, this.debounce = const Duration(milliseconds: 800)});

  final String activityId;
  final Map<String, dynamic> row;

  /// After a section was saved (field, new value or null).
  final void Function(String field, String? value)? onSaved;

  /// "สร้างนัดหมายต่อ" on the next-step card (gets the next-step text).
  final void Function(String nextStep)? onFollowUp;
  final Duration debounce;

  @override
  State<ActivityOutcomeNotes> createState() => _ActivityOutcomeNotesState();
}

class _ActivityOutcomeNotesState extends State<ActivityOutcomeNotes> {
  final Map<String, String> _values = {};
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, FocusNode> _focus = {};
  final Map<String, Timer> _timers = {};
  final Map<String, _SaveState> _state = {};
  final Set<String> _open = {};

  static String _clean(dynamic v) {
    final s = '${v ?? ''}'.trim();
    return s == 'null' ? '' : s;
  }

  // Read once: a save still pending when the widget goes away (tab switch,
  // back) runs from dispose, where the context can no longer be used.
  late final ApiClient _api;
  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void initState() {
    super.initState();
    _api = context.read<AppConfig>().apiClient;
    for (final s in kActivityOutcomeSections) {
      _values[s.field] = _clean(widget.row[s.field]);
    }
  }

  @override
  void didUpdateWidget(ActivityOutcomeNotes old) {
    super.didUpdateWidget(old);
    // A reload brings the server values; sections being typed in keep theirs.
    for (final s in kActivityOutcomeSections) {
      if (_open.contains(s.field) || _timers[s.field]?.isActive == true) continue;
      if (widget.row.containsKey(s.field)) _values[s.field] = _clean(widget.row[s.field]);
    }
  }

  @override
  void dispose() {
    for (final e in _timers.entries) {
      if (e.value.isActive) {
        e.value.cancel();
        _save(e.key, fromDispose: true);
      }
    }
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String field) => _ctrls.putIfAbsent(field, () => TextEditingController(text: _values[field] ?? ''));
  FocusNode _node(String field) => _focus.putIfAbsent(field, FocusNode.new);

  void _openSection(String field) {
    HapticFeedback.selectionClick();
    _ctrl(field).text = _values[field] ?? '';
    setState(() {
      _open.add(field);
      _state[field] = _SaveState.idle;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _node(field).requestFocus();
    });
  }

  void _close(String field) {
    final t = _timers[field];
    if (t != null && t.isActive) {
      t.cancel();
      _save(field);
    }
    _node(field).unfocus();
    setState(() => _open.remove(field));
  }

  void _changed(String field) {
    _timers[field]?.cancel();
    setState(() => _state[field] = _SaveState.pending);
    _timers[field] = Timer(widget.debounce, () => _save(field));
  }

  Future<void> _save(String field, {bool fromDispose = false}) async {
    final text = _ctrl(field).text.trim();
    if (text == (_values[field] ?? '')) {
      if (!fromDispose && mounted) setState(() => _state[field] = _SaveState.idle);
      return;
    }
    if (!fromDispose && mounted) setState(() => _state[field] = _SaveState.saving);
    final messenger = _messenger;
    try {
      await _api.putEntity('activity', widget.activityId, {field: text.isEmpty ? null : text});
      _values[field] = text;
      widget.onSaved?.call(field, text.isEmpty ? null : text);
      if (!fromDispose && mounted) setState(() => _state[field] = _SaveState.saved);
    } catch (e) {
      if (fromDispose || !mounted) return;
      setState(() => _state[field] = _SaveState.error);
      messenger?.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filled = [
      for (final s in kActivityOutcomeSections)
        if (_open.contains(s.field) || (_values[s.field] ?? '').isNotEmpty) s,
    ];
    final empty = [
      for (final s in kActivityOutcomeSections)
        if (!filled.contains(s)) s,
    ];
    return Column(
      key: const ValueKey('activity-outcome-notes'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in filled) ...[_open.contains(s.field) ? _editor(context, s) : _card(context, s), const SizedBox(height: 10)],
        if (empty.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: [for (final s in empty) _chip(context, s)]),
      ],
    );
  }

  Widget _chip(BuildContext context, ActivityOutcomeSection s) {
    final cs = Theme.of(context).colorScheme;
    return ActionChip(
      key: ValueKey('outcome-chip-${s.field}'),
      avatar: Icon(NxI.plus, size: 16, color: s.color),
      label: Text(tr(s.label)),
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: s.color.withValues(alpha: 0.35)),
      backgroundColor: s.color.withValues(alpha: 0.06),
      shape: const StadiumBorder(),
      onPressed: () => _openSection(s.field),
    );
  }

  Widget _badge(ActivityOutcomeSection s) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(color: s.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(9)),
    child: Icon(s.icon, size: 16, color: s.color),
  );

  Widget _card(BuildContext context, ActivityOutcomeSection s) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final value = _values[s.field] ?? '';
    return NxSurfaceCard(
      key: ValueKey('outcome-card-${s.field}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: () => _openSection(s.field),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _badge(s),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr(s.label),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: s.color),
                ),
              ),
              Icon(NxI.pencilSimple, size: 16, color: cs.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: theme.textTheme.bodyMedium),
          if (s.field == 'next_step' && widget.onFollowUp != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('outcome-followup'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8), foregroundColor: s.color),
                onPressed: () => widget.onFollowUp!(value),
                icon: const Icon(NxI.calendarPlus, size: 18),
                label: Text(tr('สร้างนัดหมายต่อ')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _editor(BuildContext context, ActivityOutcomeSection s) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final st = _state[s.field] ?? _SaveState.idle;
    final status = switch (st) {
      _SaveState.pending || _SaveState.saving => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: cs.onSurfaceVariant)),
          const SizedBox(width: 6),
          Text(tr('กำลังบันทึก…'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
      _SaveState.saved => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(NxI.checkCircle, size: 14, color: Color(0xFF16A34A)),
          const SizedBox(width: 4),
          Text(
            tr('บันทึกแล้ว'),
            style: theme.textTheme.labelSmall?.copyWith(color: const Color(0xFF16A34A), fontWeight: FontWeight.w600),
          ),
        ],
      ),
      _SaveState.error => Text(tr('บันทึกไม่สำเร็จ'), style: theme.textTheme.labelSmall?.copyWith(color: cs.error)),
      _SaveState.idle => const SizedBox.shrink(),
    };
    return NxSurfaceCard(
      key: ValueKey('outcome-editor-${s.field}'),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _badge(s),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr(s.label),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: s.color),
                ),
              ),
              KeyedSubtree(key: ValueKey('outcome-status-${s.field}'), child: status),
              TextButton(
                key: ValueKey('outcome-done-${s.field}'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => _close(s.field),
                child: Text(tr('เสร็จ')),
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(top: 8, right: 6),
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: s.color.withValues(alpha: 0.5), width: 3)),
            ),
            child: TextField(
              key: ValueKey('outcome-field-${s.field}'),
              controller: _ctrl(s.field),
              focusNode: _node(s.field),
              minLines: 2,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => _changed(s.field),
              decoration: InputDecoration(
                hintText: tr(s.hint),
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

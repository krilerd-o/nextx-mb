import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../core/lead_register/lead_form.dart';
import '../../widgets/fields/field_ui_type.dart';
import '../../widgets/fields/nx_form_field.dart';
import '../../widgets/fields/nx_pick_option.dart';
import '../../widgets/nx_icons.dart';

Color leadAccent(Map<String, dynamic> theme) {
  final hex = (theme['accent']?.toString() ?? '#6366F1').replaceAll('#', '');
  final v = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return v == null ? const Color(0xFF6366F1) : Color(v);
}

const _numericTypes = {'Number', 'Currency', 'Percent', 'Counter', 'Progress', 'Duration'};

/// One question, drawn natively. Choice / scale / rating / grid / consent are
/// built here (big touch targets, "Other" text); every other UI type uses the
/// app's [NxFormField] so all 52 NEXTX types render the same as CRM forms.
class LeadQuestionField extends StatelessWidget {
  const LeadQuestionField({
    super.key,
    required this.q,
    required this.answers,
    required this.onChanged,
    required this.accent,
    this.host,
    this.error,
    this.big = false,
    this.number,
    this.aiFilled = false,
  });

  final LeadQuestion q;
  final LeadAnswers answers;
  final void Function(String key, dynamic value) onChanged;
  final Color accent;
  final NxFieldHost? host;
  final String? error;
  final bool big;
  final int? number;
  final bool aiFilled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (q.uitype == 'FormTitle') {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(q.label, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          if (q.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(q.description, style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor))),
        ]),
      );
    }
    if (q.uitype == 'FormMedia') {
      if (q.mediaUrl.isEmpty) return const SizedBox.shrink();
      return ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(q.mediaUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()));
    }
    final control = _control(context);
    final usesFieldChrome = control is NxFormField;
    return Column(
      key: ValueKey('lr-q-${q.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!usesFieldChrome || q.description.isNotEmpty || aiFilled)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!usesFieldChrome)
                Text.rich(
                  TextSpan(children: [
                    if (number != null) TextSpan(text: '$number. ', style: TextStyle(color: theme.hintColor)),
                    TextSpan(text: q.label),
                    if (q.required) const TextSpan(text: ' *', style: TextStyle(color: Color(0xFFE11D48))),
                  ]),
                  style: (big ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)?.copyWith(fontWeight: FontWeight.w600),
                ),
              if (q.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(q.description, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor))),
              if (aiFilled)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Icon(NxI.sparkle, size: 14, color: Colors.deepPurple.shade400),
                    const SizedBox(width: 4),
                    Text(tr('ไอแซคเติมจากนามบัตร — ตรวจสอบก่อนส่ง'), style: theme.textTheme.labelSmall?.copyWith(color: Colors.deepPurple.shade400)),
                  ]),
                ),
            ]),
          ),
        control,
        if (error != null && !usesFieldChrome)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr(error!), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))),
      ],
    );
  }

  Widget _control(BuildContext context) {
    final t = q.uitype;
    final v = answers[q.id];
    if (t == 'FormConsent') {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (q.consentText.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
            child: Text(q.consentText, style: Theme.of(context).textTheme.bodySmall),
          ),
        _ChoiceTile(label: tr('ฉันยอมรับ'), selected: v == true, multi: true, accent: accent, big: big, onTap: () => onChanged(q.id, v == true ? false : true)),
      ]);
    }
    final snapshot = kLeadSnapshotSelect.contains(t) && q.options.isNotEmpty;
    if (t == 'RadioGroup' || (t == 'MultiSelect' && q.display != 'dropdown') || snapshot || ((t == 'Picklist' || t == 'Enum') && (big || q.options.length <= 6))) {
      return _ChoiceList(q: q, answers: answers, onChanged: onChanged, accent: accent, big: big, multi: t == 'MultiSelect');
    }
    if (t == 'Tag') return _TagInput(q: q, value: v, onChanged: (x) => onChanged(q.id, x), accent: accent);
    if (t == 'YesNo') {
      return Row(children: [
        for (final (val, label) in [(true, 'ใช่'), (false, 'ไม่ใช่')]) ...[
          Expanded(child: _ChoiceTile(label: tr(label), selected: v == val, accent: accent, big: big, onTap: () => onChanged(q.id, v == val ? null : val))),
          if (val) const SizedBox(width: 8),
        ],
      ]);
    }
    if (t == 'FormLinearScale') return _Scale(q: q, value: v, onChanged: (x) => onChanged(q.id, x), accent: accent, big: big);
    if (t == 'FormRating') return _Rating(max: (q.scale['max'] as num?)?.toInt() ?? 5, value: (v as num?)?.toInt() ?? 0, onChanged: (x) => onChanged(q.id, x), big: big);
    if (t == 'FormChoiceGrid' || t == 'FormCheckboxGrid') return _Grid(q: q, value: v, onChanged: (x) => onChanged(q.id, x), accent: accent);

    // Every other UI type → the app's shared field widget.
    final ui = fieldUiTypeFromName(t) ?? FieldUiType.text;
    final isFile = kLeadFileTypes.contains(t);
    dynamic fieldValue = v;
    if (isFile) fieldValue = (v is List && v.isNotEmpty && v.first is Map) ? (v.first as Map)['url']?.toString() : null;
    if (v is bool) fieldValue = v ? '1' : '0';
    if (v is Map) fieldValue = jsonEncode(v);
    return NxFormField(
      name: q.id,
      uiType: ui,
      label: number != null ? '$number. ${q.label}' : q.label,
      required: q.required,
      value: fieldValue,
      hint: q.placeholder.isEmpty ? null : q.placeholder,
      errorText: error,
      host: host,
      options: [for (final o in q.options) NxPickOption(value: o['value'].toString(), label: o['label']?.toString() ?? o['value'].toString())],
      onChanged: (x) {
        if (isFile) {
          final raw = x?.toString() ?? '';
          if (raw.isEmpty) return onChanged(q.id, null);
          var url = raw;
          if (raw.startsWith('{')) {
            try {
              url = (jsonDecode(raw) as Map)['url']?.toString() ?? raw;
            } catch (_) {}
          }
          onChanged(q.id, [
            {'url': url, 'name': Uri.tryParse(url)?.pathSegments.lastOrNull ?? 'file'},
          ]);
          return;
        }
        if (_numericTypes.contains(t)) {
          final n = num.tryParse('${x ?? ''}'.replaceAll(',', ''));
          return onChanged(q.id, n);
        }
        onChanged(q.id, x);
      },
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({required this.label, required this.selected, required this.accent, required this.onTap, this.multi = false, this.big = false});
  final String label;
  final bool selected;
  final bool multi;
  final bool big;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? accent.withValues(alpha: 0.08) : cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? accent : cs.outlineVariant, width: selected ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: big ? 60 : 50),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: big ? 14 : 10),
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: big ? 26 : 22,
                  height: big ? 26 : 22,
                  decoration: BoxDecoration(
                    color: selected ? accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(multi ? 6 : 99),
                    border: Border.all(color: selected ? accent : cs.outline, width: 1.4),
                  ),
                  child: selected ? Icon(multi ? NxI.check : NxI.circle, size: multi ? 15 : 8, color: Colors.white) : null,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: (big ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.bodyLarge))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceList extends StatelessWidget {
  const _ChoiceList({required this.q, required this.answers, required this.onChanged, required this.accent, required this.big, required this.multi});
  final LeadQuestion q;
  final LeadAnswers answers;
  final void Function(String, dynamic) onChanged;
  final Color accent;
  final bool big;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    final v = answers[q.id];
    final arr = multi ? (v is List ? v.map((e) => '$e').toList() : <String>[]) : (v == null || '$v'.isEmpty ? <String>[] : ['$v']);
    void toggle(String value) {
      if (multi) {
        final next = [...arr];
        next.contains(value) ? next.remove(value) : next.add(value);
        onChanged(q.id, next);
      } else {
        onChanged(q.id, arr.isNotEmpty && arr.first == value && !q.required ? null : value);
      }
    }

    String? lastGroup;
    final children = <Widget>[];
    for (final o in q.options) {
      final value = o['value'].toString();
      final group = o['group']?.toString();
      if (group != null && group.isNotEmpty && group != lastGroup) {
        lastGroup = group;
        children.add(Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 6, bottom: 2),
          child: Text(group.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 0.6, color: Theme.of(context).hintColor, fontWeight: FontWeight.w700)),
        ));
      }
      children.add(_ChoiceTile(label: o['label']?.toString() ?? value, selected: arr.contains(value), multi: multi, accent: accent, big: big, onTap: () => toggle(value)));
    }
    final otherOn = arr.contains('__other__');
    if (q.allowOther) {
      children.add(_ChoiceTile(label: tr('อื่นๆ (โปรดระบุ)'), selected: otherOn, multi: multi, accent: accent, big: big, onTap: () => toggle('__other__')));
      if (otherOn) {
        children.add(_OtherField(
          key: ValueKey('${q.id}__other'),
          initial: answers['${q.id}__other']?.toString() ?? '',
          onChanged: (s) => onChanged('${q.id}__other', s),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 8), child: c)]);
  }
}

class _OtherField extends StatefulWidget {
  const _OtherField({super.key, required this.initial, required this.onChanged});
  final String initial;
  final ValueChanged<String> onChanged;
  @override
  State<_OtherField> createState() => _OtherFieldState();
}

class _OtherFieldState extends State<_OtherField> {
  late final _c = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        autofocus: widget.initial.isEmpty,
        onChanged: widget.onChanged,
        decoration: InputDecoration(hintText: tr('ระบุ…'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
      );
}

class _TagInput extends StatefulWidget {
  const _TagInput({required this.q, required this.value, required this.onChanged, required this.accent});
  final LeadQuestion q;
  final dynamic value;
  final ValueChanged<List<String>> onChanged;
  final Color accent;
  @override
  State<_TagInput> createState() => _TagInputState();
}

class _TagInputState extends State<_TagInput> {
  final _c = TextEditingController();
  List<String> get _tags => widget.value is List ? (widget.value as List).map((e) => '$e').toList() : <String>[];

  void _add(String s) {
    final t = s.trim();
    if (t.isEmpty || _tags.contains(t)) return;
    widget.onChanged([..._tags, t]);
    _c.clear();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final t in _tags) InputChip(label: Text(t), onDeleted: () => widget.onChanged(_tags.where((x) => x != t).toList())),
        for (final o in widget.q.options.where((o) => !_tags.contains(o['value'].toString())))
          ActionChip(label: Text('+ ${o['label'] ?? o['value']}'), onPressed: () => _add(o['value'].toString())),
      ]),
      const SizedBox(height: 8),
      TextField(
        controller: _c,
        textInputAction: TextInputAction.done,
        onSubmitted: _add,
        decoration: InputDecoration(hintText: tr('พิมพ์แล้วกด Enter'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
      ),
    ]);
  }
}

class _Scale extends StatelessWidget {
  const _Scale({required this.q, required this.value, required this.onChanged, required this.accent, required this.big});
  final LeadQuestion q;
  final dynamic value;
  final ValueChanged<int> onChanged;
  final Color accent;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final min = (q.scale['min'] as num?)?.toInt() ?? 1;
    final max = (q.scale['max'] as num?)?.toInt() ?? 5;
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var n = min; n <= max; n++)
          SizedBox(
            width: big ? 58 : 44,
            height: big ? 58 : 44,
            child: Material(
              color: value == n ? accent : cs.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: value == n ? accent : cs.outlineVariant)),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(n);
                },
                child: Center(child: Text('$n', style: TextStyle(fontWeight: FontWeight.w700, fontSize: big ? 20 : 15, color: value == n ? Colors.white : cs.onSurface))),
              ),
            ),
          ),
      ]),
      if ((q.scale['min_label'] ?? '').toString().isNotEmpty || (q.scale['max_label'] ?? '').toString().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${q.scale['min_label'] ?? ''}', style: Theme.of(context).textTheme.bodySmall),
            Text('${q.scale['max_label'] ?? ''}', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
    ]);
  }
}

class _Rating extends StatelessWidget {
  const _Rating({required this.max, required this.value, required this.onChanged, required this.big});
  final int max;
  final int value;
  final ValueChanged<int> onChanged;
  final bool big;

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 1; i <= max; i++)
          IconButton(
            iconSize: big ? 44 : 34,
            onPressed: () {
              HapticFeedback.selectionClick();
              onChanged(i);
            },
            icon: Icon(i <= value ? NxI.starFill : NxI.star, color: i <= value ? const Color(0xFFF5B700) : Theme.of(context).colorScheme.outline),
          ),
      ]);
}

class _Grid extends StatelessWidget {
  const _Grid({required this.q, required this.value, required this.onChanged, required this.accent});
  final LeadQuestion q;
  final dynamic value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final multi = q.uitype == 'FormCheckboxGrid';
    final v = value is Map ? Map<String, dynamic>.from(value as Map) : <String, dynamic>{};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final r in q.rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in q.columns)
                ChoiceChip(
                  label: Text(c),
                  selected: multi ? ((v[r] as List?)?.contains(c) ?? false) : v[r] == c,
                  selectedColor: accent.withValues(alpha: 0.15),
                  onSelected: (_) {
                    final next = Map<String, dynamic>.from(v);
                    if (multi) {
                      final cur = [...((v[r] as List?)?.map((e) => '$e') ?? const <String>[])];
                      cur.contains(c) ? cur.remove(c) : cur.add(c);
                      next[r] = cur;
                    } else {
                      next[r] = c;
                    }
                    onChanged(next);
                  },
                ),
            ]),
          ]),
        ),
    ]);
  }
}

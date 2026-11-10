import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n.dart';
import '../../../core/nx_page_route.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../../widgets/isaac_sticker.dart';
import '../../../widgets/nx_icons.dart';
import '../../deep_link_loaders.dart';
import 'card_scan_models.dart';

/// Review what the card scan read: keep / drop each value, change its target
/// field, see duplicates. Nothing is saved here — "ใช้ข้อมูลนี้" only fills
/// the form; the user saves it.
class CardScanReviewScreen extends StatefulWidget {
  const CardScanReviewScreen({
    super.key,
    required this.module,
    required this.result,
    required this.images,
    required this.formFields,
    this.currentValues = const {},
  });

  final String module;
  final CardScanResult result;
  final CardImages images;

  /// Fields of the open form (name → label) — possible targets.
  final Map<String, String> formFields;

  /// Values already in the form (edit / duplicate): not overwritten unless ticked.
  final Map<String, dynamic> currentValues;

  @override
  State<CardScanReviewScreen> createState() => _CardScanReviewScreenState();
}

class _Row {
  _Row({required this.field, required this.target, required this.keep, this.extra = false});
  final CardField field;
  String target;
  bool keep;
  final bool extra;
}

class _CardScanReviewScreenState extends State<CardScanReviewScreen> {
  late final List<_Row> _rows;
  late final List<CardExtra> _extras;
  final Set<CardExtra> _noteExtras = {};
  bool _attach = true;
  bool _linkAccount = false;
  bool _showBack = false;

  static String _current(dynamic v) {
    if (v == null) return '';
    if (v is Map) return '${v['label'] ?? v['name'] ?? v['id'] ?? ''}';
    return '$v'.trim();
  }

  @override
  void initState() {
    super.initState();
    _rows = [
      for (final f in widget.result.fields)
        if (widget.formFields.containsKey(f.name))
          _Row(
            field: f,
            target: f.name,
            // Unsure values and values that would replace what the form already has start unticked.
            keep: f.confidence != 'low' && _current(widget.currentValues[f.name]).isEmpty,
          ),
    ];
    _extras = [
      ...widget.result.extras,
      // Fields the server mapped that this form doesn't show.
      for (final f in widget.result.fields)
        if (!widget.formFields.containsKey(f.name)) CardExtra(kind: f.kind ?? f.name, value: f.value, label: f.label),
    ];
    _linkAccount = widget.result.accountSuggestion != null && widget.formFields.containsKey('account_id') && _current(widget.currentValues['account_id']).isEmpty;
  }

  int get _keptCount => _rows.where((r) => r.keep).length + (_linkAccount ? 1 : 0) + (_noteExtras.isNotEmpty ? 1 : 0);

  Future<String?> _pickTarget(String current) {
    final used = {for (final r in _rows) if (r.keep) r.target};
    return showAppBottomSheet<String>(
      context: context,
      title: tr('ใส่ในช่อง'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in widget.formFields.entries)
            ListTile(
              dense: true,
              title: Text(tr(e.value)),
              subtitle: _current(widget.currentValues[e.key]).isEmpty ? null : Text(tr('มีค่าเดิม: ${_current(widget.currentValues[e.key])}'), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: e.key == current
                  ? const Icon(NxI.check)
                  : used.contains(e.key)
                      ? Text(tr('ใช้แล้ว'), style: Theme.of(context).textTheme.labelSmall)
                      : null,
              onTap: () => Navigator.pop(context, e.key),
            ),
        ],
      ),
    );
  }

  void _apply() {
    final values = <String, dynamic>{};
    for (final r in _rows) {
      if (!r.keep || r.field.value.trim().isEmpty) continue;
      values[r.target] = r.field.value.trim();
    }
    final acc = widget.result.accountSuggestion;
    if (_linkAccount && acc != null) values['account_id'] = {'id': acc.id, 'label': acc.name};
    final note = _noteExtras.isEmpty ? null : _noteExtras.map((e) => '${tr(e.label)}: ${e.value}').join('\n');
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(CardScanApply(values: values, attach: _attach, images: widget.images, note: note));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final r = widget.result;
    final back = widget.images.back;
    return Scaffold(
      appBar: AppBar(title: Text(tr('ตรวจข้อมูลจากนามบัตร'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // Card photo (tap: other side).
          GestureDetector(
            onTap: back == null ? null : () => setState(() => _showBack = !_showBack),
            child: AspectRatio(
              aspectRatio: 1.636,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(_showBack && back != null ? back : widget.images.front, fit: BoxFit.cover),
                    if (back != null)
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                          child: Text(tr(_showBack ? 'ด้านหลัง · แตะดูด้านหน้า' : 'ด้านหน้า · แตะดูด้านหลัง'), style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          IsaacSummary(result: r),
          if (r.duplicates.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('card-duplicates'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(NxI.warning, size: 18, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(tr('อาจมีอยู่แล้วในระบบ'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                  ]),
                  for (final d in r.duplicates)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(d.name.isEmpty ? '#${d.id}' : d.name),
                      subtitle: Text(tr('${_moduleLabel(d.module)} · ตรงกันที่${d.reason}')),
                      trailing: TextButton(
                        onPressed: () => nxPush<void>(context, EntityByIdLoader(module: d.module, id: d.id), root: true),
                        child: Text(tr('เปิดรายการเดิม')),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(tr('ข้อมูลที่อ่านได้'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          if (_rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(tr('ไม่พบข้อมูลที่ใส่ในฟอร์มนี้ได้'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
          for (final (i, row) in _rows.indexed) _Stagger(index: i, child: _fieldRow(theme, row)),
          if (widget.result.accountSuggestion != null && widget.formFields.containsKey('account_id'))
            CheckboxListTile(
              key: const ValueKey('card-link-account'),
              contentPadding: EdgeInsets.zero,
              value: _linkAccount,
              onChanged: (v) => setState(() => _linkAccount = v ?? false),
              secondary: const Icon(NxI.buildings),
              title: Text(tr('ผูกกับบัญชีลูกค้า ${widget.result.accountSuggestion!.name}')),
              subtitle: Text(tr('พบบัญชีชื่อเดียวกับบริษัทบนนามบัตร')),
            ),
          if (_extras.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(tr('อ่านได้แต่ไม่มีช่องตรง'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(tr('แตะเพื่อเพิ่มไว้ในรายละเอียด หรือกดค้างเพื่อเลือกช่องเอง'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _extras)
                  GestureDetector(
                    onLongPress: () async {
                      final t = await _pickTarget('');
                      if (t == null) return;
                      setState(() {
                        _rows.add(_Row(field: CardField(name: t, value: e.value, label: widget.formFields[t] ?? t, confidence: 'medium', kind: e.kind), target: t, keep: true, extra: true));
                        _extras.remove(e);
                        _noteExtras.remove(e);
                      });
                    },
                    child: FilterChip(
                      key: ValueKey('card-extra-${e.kind}'),
                      selected: _noteExtras.contains(e),
                      label: Text('${tr(e.label)}: ${e.value}'),
                      onSelected: (v) => setState(() => v ? _noteExtras.add(e) : _noteExtras.remove(e)),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            key: const ValueKey('card-attach'),
            contentPadding: EdgeInsets.zero,
            value: _attach,
            onChanged: (v) => setState(() => _attach = v),
            secondary: const Icon(NxI.paperclip),
            title: Text(tr('แนบรูปนามบัตรกับรายการ')),
            subtitle: Text(tr('แนบให้หลังจากกดบันทึก')),
          ),
          if (r.rawText.trim().isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(tr('ข้อความทั้งหมดบนนามบัตร'), style: theme.textTheme.bodyMedium),
              children: [SelectableText(r.rawText, style: theme.textTheme.bodySmall)],
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              key: const ValueKey('card-apply'),
              icon: const Icon(NxI.check),
              label: Text(tr('ใช้ข้อมูลนี้ ($_keptCount ช่อง)')),
              onPressed: _keptCount == 0 ? null : _apply,
            ),
          ),
        ),
      ),
    );
  }

  static String _moduleLabel(String m) => switch (m) {
        'lead' => 'ผู้มุ่งหวัง',
        'contact' => 'ผู้ติดต่อ',
        'account' => 'บัญชีลูกค้า',
        _ => m,
      };

  Widget _fieldRow(ThemeData theme, _Row row) {
    final cs = theme.colorScheme;
    final sure = row.field.confidence == 'high';
    final color = sure ? const Color(0xFF16A34A) : const Color(0xFFF59E0B);
    final old = _current(widget.currentValues[row.target]);
    return Container(
      key: ValueKey('card-row-${row.field.name}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(4, 6, 10, 8),
      decoration: BoxDecoration(
        color: row.keep ? cs.primary.withValues(alpha: 0.05) : cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: row.keep ? cs.primary.withValues(alpha: 0.35) : Colors.transparent),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            key: ValueKey('card-keep-${row.field.name}'),
            value: row.keep,
            onChanged: (v) => setState(() => row.keep = v ?? false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: InkWell(
                        key: ValueKey('card-target-${row.field.name}'),
                        onTap: () async {
                          final t = await _pickTarget(row.target);
                          if (t != null) setState(() => row.target = t);
                        },
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(
                            child: Text(
                              tr(widget.formFields[row.target] ?? row.target),
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                            ),
                          ),
                          Icon(NxI.caretDown, size: 14, color: cs.primary),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                      child: Text(tr(sure ? 'ชัดเจน' : 'ตรวจสอบ'), style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                TextFormField(
                  key: ValueKey('card-value-${row.field.name}'),
                  initialValue: row.field.value,
                  onChanged: (v) => row.field.value = v,
                  style: theme.textTheme.bodyLarge,
                  decoration: const InputDecoration(isDense: true, border: InputBorder.none, filled: false, contentPadding: EdgeInsets.symmetric(vertical: 6)),
                ),
                if (old.isNotEmpty)
                  Text(
                    tr('ค่าเดิมในฟอร์ม: $old'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rows slide up and fade in one after another.
class _Stagger extends StatelessWidget {
  const _Stagger({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = (index * 45).clamp(0, 450);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 280 + delay),
      curve: Interval(delay / (280 + delay), 1, curve: Curves.easeOutCubic),
      builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: c)),
      child: child,
    );
  }
}

/// Isaac's speech bubble: what he read, how fast, and his notes
/// (duplicates, personal email, unsure fields…) — all from checked data.
class IsaacSummary extends StatelessWidget {
  const IsaacSummary({super.key, required this.result});
  final CardScanResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final r = result;
    final warn = r.insights.any((i) => i.level == 'warn') || r.offline;
    final secs = r.isaacMs != null ? (r.isaacMs! / 1000).toStringAsFixed(1) : null;
    final headline = r.offline
        ? 'อ่านด้วยเครื่อง (เฉพาะภาษาอังกฤษ) ได้ ${r.fields.length} ช่อง — ช่วยตรวจอีกนิดนะครับ'
        : secs != null
            ? 'Isaac อ่านได้ ${r.fields.length} ช่องใน $secs วินาที'
            : 'Isaac อ่านได้ ${r.fields.length} ช่อง';
    Color levelColor(String l) => switch (l) {
          'ok' => const Color(0xFF16A34A),
          'warn' => const Color(0xFFF59E0B),
          _ => cs.primary,
        };
    IconData levelIcon(String l) => switch (l) {
          'ok' => NxI.checkCircle,
          'warn' => NxI.warning,
          _ => NxI.info,
        };
    return Row(
      key: const ValueKey('card-isaac'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 500),
          curve: Curves.elasticOut,
          builder: (_, v, c) => Transform.scale(scale: v, child: c),
          child: IsaacSticker(state: warn ? 'curious' : 'answer_ready', size: 56),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
                topLeft: Radius.circular(6),
              ),
              border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(headline), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                if (r.model != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(r.model!, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                for (final (i, ins) in r.insights.indexed)
                  _Stagger(
                    index: i + 1,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(levelIcon(ins.level), size: 16, color: levelColor(ins.level)),
                          ),
                          const SizedBox(width: 6),
                          Expanded(child: Text(tr(ins.text), style: theme.textTheme.bodySmall)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

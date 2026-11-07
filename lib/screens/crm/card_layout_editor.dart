import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/card_layout.dart';
import '../../core/i18n.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_entity_card.dart';
import '../../widgets/nx_icons.dart';

/// "ปรับแต่งการ์ด" — choose the field for each spot on the list card, with a
/// live preview on a real record. Returns the saved [CardLayout], or `null`
/// after "ค่าเริ่มต้น" (reset to the shared default).
class CardLayoutEditorScreen extends StatefulWidget {
  const CardLayoutEditorScreen({
    super.key,
    required this.module,
    required this.initial,
    required this.defaults,
    required this.fields,
    this.sample,
  });

  final String module;
  final CardLayout initial;
  final CardLayout defaults;
  final CardFieldContext fields;
  final Map<String, dynamic>? sample;

  @override
  State<CardLayoutEditorScreen> createState() => _CardLayoutEditorScreenState();
}

class _SlotInfo {
  const _SlotInfo(this.key, this.title, this.hint, this.icon);
  final String key;
  final String title;
  final String hint;
  final IconData icon;
}

const _slots = [
  _SlotInfo('top', 'บรรทัดบน (เลขที่/ป้ายย่อย)', 'ป้ายบนสุด: เลขที่ รหัส วันที่สั้นๆ', NxI.hash),
  _SlotInfo('title', 'หัวข้อหลัก', 'ชื่อลูกค้า ชื่อรายการ หัวเรื่อง', NxI.textT),
  _SlotInfo('subtitle', 'บรรทัดรอง (ใต้หัวข้อ)', 'รายละเอียดเสริม โครงการ หมายเหตุ', NxI.textAlignLeft),
  _SlotInfo('badge', 'สถานะ (ป้ายมุมขวาบน)', 'แสดงเป็นป้ายสี เหมาะกับฟิลด์สถานะ', NxI.tag),
  _SlotInfo('date', 'แถวล่าง — วันที่', 'วันที่ในเอกสาร ครบกำหนด วันที่สร้าง/แก้ไข', NxI.calendarBlank),
  _SlotInfo('person', 'แถวล่าง — คน', 'เจ้าของ ผู้รับผิดชอบ ผู้ติดต่อ (มีรูปย่อ)', NxI.user),
  _SlotInfo('amount', 'ยอดเงิน (มุมขวาล่าง)', 'ยอดรวม มูลค่า — แสดงเป็นเงินตัวใหญ่', NxI.currencyCircleDollar),
];

class _CardLayoutEditorScreenState extends State<CardLayoutEditorScreen> {
  late CardLayout _l = widget.initial;

  List<String> get _fieldNames {
    final names = widget.fields.fields.keys.where((k) => k.isNotEmpty).toList();
    for (final m in CardFieldContext.metaLabels.keys) {
      if (!names.contains(m)) names.add(m);
    }
    return names;
  }

  Future<void> _pick(_SlotInfo slot) async {
    final picked = await showNxSnapSheet<String>(
      context: context,
      title: slot.title,
      snaps: const [0.7, 0.92],
      builder: (ctx, controller) => _FieldPicker(
        names: _fieldNames,
        fields: widget.fields,
        current: _l.slot(slot.key),
        controller: controller,
        preferNumbers: slot.key == 'amount',
        preferDates: slot.key == 'date',
        preferUsers: slot.key == 'person',
      ),
    );
    if (picked == null) return;
    HapticFeedback.selectionClick();
    setState(() => _l = _l.withSlot(slot.key, picked.isEmpty ? null : picked));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sample = widget.sample ?? cardSampleRow(_l, widget.fields);
    return Scaffold(
      appBar: NxAppHeader(title: 'ปรับแต่งการ์ด', subtitle: 'เลือกฟิลด์แต่ละตำแหน่งบนการ์ด'),
      body: Column(
        children: [
          // Preview stays put while the slot list scrolls.
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('ตัวอย่าง'), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: NxEntityCard(
                    key: ValueKey(_l.toJson().toString()),
                    row: sample,
                    layout: _l,
                    fields: widget.fields,
                    module: widget.module,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                for (final s in _slots)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _pick(s),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(s.icon, size: 18, color: cs.primary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(tr(s.title), style: theme.textTheme.titleSmall),
                                    Text(
                                      tr(s.hint),
                                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _l.slot(s.key) == null ? tr('ไม่แสดง') : widget.fields.label(_l.slot(s.key)!),
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: _l.slot(s.key) == null ? cs.onSurfaceVariant : cs.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(NxI.caretRight, size: 18, color: cs.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('แสดงบรรทัดรอง'), style: theme.textTheme.titleSmall),
                      RadioGroup<String>(
                        groupValue: _l.subtitleMode,
                        onChanged: (v) => setState(() => _l = _l.withSubtitleMode(v ?? 'diff')),
                        child: Column(
                          children: [
                            for (final m in const [
                              ('diff', 'แสดงเมื่อต่างจากหัวข้อหลัก'),
                              ('always', 'แสดงเสมอ (ถ้ามีข้อมูล)'),
                              ('never', 'ไม่แสดง'),
                            ])
                              RadioListTile<String>(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                value: m.$1,
                                title: Text(tr(m.$2)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _l = widget.defaults),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
                      child: Text(tr('ค่าเริ่มต้น')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _l),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
                      child: Text(tr('บันทึก')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldPicker extends StatefulWidget {
  const _FieldPicker({
    required this.names,
    required this.fields,
    required this.current,
    required this.controller,
    this.preferNumbers = false,
    this.preferDates = false,
    this.preferUsers = false,
  });
  final List<String> names;
  final CardFieldContext fields;
  final String? current;
  final ScrollController controller;
  final bool preferNumbers;
  final bool preferDates;
  final bool preferUsers;

  @override
  State<_FieldPicker> createState() => _FieldPickerState();
}

class _FieldPickerState extends State<_FieldPicker> {
  String _q = '';

  bool _preferred(String n) =>
      (widget.preferNumbers && widget.fields.isNumber(n)) ||
      (widget.preferDates && widget.fields.isDate(n)) ||
      (widget.preferUsers && widget.fields.isUser(n));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _q.toLowerCase();
    final names = widget.names
        .where((n) => q.isEmpty || widget.fields.label(n).toLowerCase().contains(q) || n.toLowerCase().contains(q))
        .toList()
      // Suggested types first (numbers for the amount, dates for the date row…).
      ..sort((a, b) => (_preferred(a) ? 0 : 1).compareTo(_preferred(b) ? 0 : 1));
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        TextField(
          autofocus: false,
          onChanged: (v) => setState(() => _q = v.trim()),
          decoration: InputDecoration(
            hintText: tr('ค้นหาฟิลด์…'),
            prefixIcon: const Icon(NxI.magnifyingGlass, size: 18),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: Icon(NxI.eyeSlash, color: cs.onSurfaceVariant),
          title: Text(tr('ไม่แสดง')),
          trailing: widget.current == null ? Icon(NxI.check, color: cs.primary) : null,
          onTap: () => Navigator.pop(context, ''),
        ),
        for (final n in names)
          ListTile(
            title: Text(widget.fields.label(n)),
            subtitle: Text(n, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            leading: _preferred(n) ? Icon(NxI.sparkle, size: 18, color: cs.primary) : const SizedBox(width: 18),
            trailing: widget.current == n ? Icon(NxI.check, color: cs.primary) : null,
            onTap: () => Navigator.pop(context, n),
          ),
      ],
    );
  }
}

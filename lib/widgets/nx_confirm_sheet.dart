import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import 'app_bottom_sheet.dart';
import 'fields/nx_field_chrome.dart';
import 'nx_icons.dart';

/// Shared confirm sheets: status changes (every module) and swipe actions
/// on list cards (call / delete). One visual language — rounded sheet,
/// status chips in their real colours, cancel / confirm buttons.

const kNxDangerRed = Color(0xFFE11D48);
const _green = Color(0xFF16A34A);
const _blue = Color(0xFF2563EB);
const _amber = Color(0xFFF59E0B);

/// Tap-to-pick reasons for "ไม่อนุมัติ" (approvals).
const kNxRejectReasons = ['ข้อมูลไม่ครบ', 'เงื่อนไขไม่เหมาะสม', 'ต้องแก้ไขก่อน', 'ไม่อยู่ในงบประมาณ'];

/// Tap-to-pick reasons for cancelling.
const kNxCancelReasons = ['ลูกค้ายกเลิก', 'ซ้ำกับรายการอื่น', 'ข้อมูลไม่ถูกต้อง'];

/// Colour of a status from its picklist hex, else from the word.
Color nxStatusTone(ColorScheme cs, String value, [String? hex]) {
  final s = (hex ?? '').replaceAll('#', '');
  if (s.length == 6) {
    final v = int.tryParse(s, radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  final w = value.toLowerCase();
  if (RegExp(r'won|approved|accept|done|complete|qualified|paid|active|อนุมัติ|สำเร็จ|เสร็จ|ใช้งาน$|ชนะ').hasMatch(w) &&
      !RegExp(r'ไม่อนุมัติ|ไม่ใช้งาน|inactive|unqualified').hasMatch(w)) {
    return _green;
  }
  if (RegExp(r'lost|reject|cancel|expired|unqualified|inactive|discontinued|ยกเลิก|ไม่อนุมัติ|ไม่ใช้งาน|เลิก|แพ้').hasMatch(w)) {
    return cs.error;
  }
  if (RegExp(r'draft|new|ร่าง|ใหม่').hasMatch(w)) return cs.onSurfaceVariant;
  if (RegExp(r'progress|ดำเนินการ').hasMatch(w)) return _blue;
  return _amber;
}

/// Closing / cancelling / losing / deleting: the confirm button turns red.
bool nxIsDestructiveStatus(String value) {
  final w = value.toLowerCase();
  if (RegExp(r'won|ชนะ').hasMatch(w)) return false;
  return RegExp(r'lost|cancel|reject|delete|closed|void|inactive|discontinued|ยกเลิก|แพ้|ไม่อนุมัติ|ลบ|ปิดเคส|ไม่ใช้งาน').hasMatch(w);
}

/// One status as a pill: tinted fill, coloured dot and label.
class NxStatusChip extends StatelessWidget {
  const NxStatusChip({super.key, required this.label, required this.color, this.strong = false});

  final String label;
  final Color color;

  /// The new status: a little bolder.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final fg = dark ? Color.lerp(color, Colors.white, 0.35)! : Color.lerp(color, Colors.black, 0.18)!;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: strong ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: strong ? 0.7 : 0.3), width: strong ? 1.5 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              tr(label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(color: fg, fontWeight: strong ? FontWeight.w800 : FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Current → new status with an arrow that slides in once.
class NxStatusTransition extends StatelessWidget {
  const NxStatusTransition({super.key, this.from, required this.to, this.fromColor, this.toColor});

  /// Null / empty: unknown current status — only the new one is shown
  /// (bulk callers pass 'หลายสถานะ' when the picked rows differ).
  final String? from;
  final String to;
  final Color? fromColor;
  final Color? toColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final arrow = TweenAnimationBuilder<double>(
      tween: Tween(begin: reduced ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(-10 * (1 - t), 0), child: child),
      ),
      child: Icon(NxI.arrowRight, size: 20, color: toColor ?? cs.primary),
    );
    return Wrap(
      key: const ValueKey('status-transition'),
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        if ((from ?? '').trim().isNotEmpty)
          NxStatusChip(key: const ValueKey('status-from'), label: from!.trim(), color: fromColor ?? cs.onSurfaceVariant),
        arrow,
        NxStatusChip(key: const ValueKey('status-to'), label: to, color: toColor ?? cs.primary, strong: true),
      ],
    );
  }
}

/// What the user typed / picked in [showStatusChangeConfirm].
class NxStatusConfirm {
  const NxStatusConfirm({this.note = ''});

  /// Reason or note ('' when none).
  final String note;
}

/// Ask before a status change. Returns null when cancelled (the caller
/// leaves its UI as it was).
///
/// [allowNote]: show an optional note (only where the server takes one).
/// [requireReason]: a reason must be given (lost / cancelled / rejected),
/// [reasons] are tap-to-pick chips that fill it in.
Future<NxStatusConfirm?> showStatusChangeConfirm(
  BuildContext context, {
  String? recordTitle,
  String? from,
  required String to,
  Color? fromColor,
  Color? toColor,
  String? impact,
  bool allowNote = false,
  bool requireReason = false,
  List<String> reasons = const [],
  String? noteLabel,
  String initialNote = '',
  bool? destructive,
  String? title,
  String confirmLabel = 'ยืนยัน',
  Widget? extra,
  Key confirmKey = const ValueKey('status-confirm-ok'),
  Key noteKey = const ValueKey('status-confirm-note'),
}) {
  HapticFeedback.selectionClick();
  return showAppBottomSheet<NxStatusConfirm>(
    context: context,
    title: title ?? 'เปลี่ยนสถานะ?',
    child: _StatusConfirmBody(
      recordTitle: recordTitle,
      from: from,
      to: to,
      fromColor: fromColor,
      toColor: toColor,
      impact: impact,
      allowNote: allowNote || requireReason,
      requireReason: requireReason,
      reasons: reasons,
      noteLabel: noteLabel,
      initialNote: initialNote,
      destructive: destructive ?? nxIsDestructiveStatus(to),
      confirmLabel: confirmLabel,
      extra: extra,
      confirmKey: confirmKey,
      noteKey: noteKey,
    ),
  );
}

class _StatusConfirmBody extends StatefulWidget {
  const _StatusConfirmBody({
    required this.recordTitle,
    required this.from,
    required this.to,
    required this.fromColor,
    required this.toColor,
    required this.impact,
    required this.allowNote,
    required this.requireReason,
    required this.reasons,
    required this.noteLabel,
    required this.initialNote,
    required this.destructive,
    required this.confirmLabel,
    required this.extra,
    required this.confirmKey,
    required this.noteKey,
  });

  final String? recordTitle;
  final String? from;
  final String to;
  final Color? fromColor;
  final Color? toColor;
  final String? impact;
  final bool allowNote;
  final bool requireReason;
  final List<String> reasons;
  final String? noteLabel;
  final String initialNote;
  final bool destructive;
  final String confirmLabel;
  final Widget? extra;
  final Key confirmKey;
  final Key noteKey;

  @override
  State<_StatusConfirmBody> createState() => _StatusConfirmBodyState();
}

class _StatusConfirmBodyState extends State<_StatusConfirmBody> {
  late final _note = TextEditingController(text: widget.initialNote);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final toColor = widget.toColor ?? cs.primary;
    final accent = widget.destructive ? kNxDangerRed : toColor;
    final canGo = !widget.requireReason || _note.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if ((widget.recordTitle ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              widget.recordTitle!.trim(),
              key: const ValueKey('status-confirm-record'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
          ),
          child: NxStatusTransition(from: widget.from, to: widget.to, fromColor: widget.fromColor, toColor: toColor),
        ),
        if ((widget.impact ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('status-confirm-impact'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(widget.destructive ? NxI.warning : NxI.info, size: 18, color: accent),
                const SizedBox(width: 8),
                Expanded(child: Text(tr(widget.impact!), style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
        ],
        if (widget.extra != null) ...[const SizedBox(height: 10), widget.extra!],
        if (widget.reasons.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('${tr('เหตุผล')}${widget.requireReason ? ' *' : ''}', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, r) in widget.reasons.indexed)
                ChoiceChip(
                  key: ValueKey('status-reason-$i'),
                  label: Text(tr(r)),
                  selected: _note.text.trim() == tr(r),
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _note.text = tr(r));
                  },
                ),
            ],
          ),
        ],
        if (widget.allowNote) ...[
          const SizedBox(height: 12),
          TextField(
            key: widget.noteKey,
            controller: _note,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
            decoration: NxFieldStyle.input(
              context,
              label: widget.noteLabel ?? (widget.requireReason ? 'เหตุผล' : 'หมายเหตุ (ไม่บังคับ)'),
              required: widget.requireReason,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: 18),
        NxConfirmButtons(
          confirmKey: widget.confirmKey,
          confirmLabel: widget.confirmLabel,
          color: accent,
          onConfirm: canGo
              ? () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context, NxStatusConfirm(note: _note.text.trim()));
                }
              : null,
        ),
      ],
    );
  }
}

/// ยกเลิก / confirm pair shared by every confirm sheet.
class NxConfirmButtons extends StatelessWidget {
  const NxConfirmButtons({super.key, required this.confirmKey, required this.confirmLabel, required this.color, required this.onConfirm, this.icon});

  final Key confirmKey;
  final String confirmLabel;
  final Color color;
  final VoidCallback? onConfirm;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 50,
            child: OutlinedButton(
              key: const ValueKey('status-confirm-cancel'),
              style: OutlinedButton.styleFrom(shape: shape),
              onPressed: () => Navigator.pop(context),
              child: Text(tr('ยกเลิก'), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 50,
            child: FilledButton(
              key: confirmKey,
              style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: fg, shape: shape),
              onPressed: onConfirm,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 6)],
                  Flexible(
                    child: Text(tr(confirmLabel), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// After a confirmed change: light haptic + "เปลี่ยนสถานะแล้ว" (+ the new
/// label), with "เลิกทำ" for ~5 s when [undo] is given.
void showNxStatusChangedSnack(
  ScaffoldMessengerState? messenger, {
  String? label,
  String text = 'เปลี่ยนสถานะแล้ว',
  Future<void> Function()? undo,
}) {
  HapticFeedback.lightImpact();
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 5),
    persist: false,
    content: Text(label == null || label.isEmpty ? tr(text) : '${tr(text)} · ${tr(label)}'),
    action: undo == null ? null : SnackBarAction(label: tr('เลิกทำ'), onPressed: () => undo()),
  ));
}

// ───────────────────────────── swipe: call / delete

/// One phone number of a record.
typedef NxPhone = ({String label, String number});

const _phoneFields = <(String, String)>[
  ('mobile_1st', 'มือถือ'),
  ('mobile', 'มือถือ'),
  ('mobile_2nd', 'มือถือ 2'),
  ('phone', 'เบอร์โทรศัพท์'),
  ('phone_1st', 'เบอร์โทรศัพท์'),
  ('phone_2nd', 'เบอร์โทรศัพท์ 2'),
  ('office_phone', 'เบอร์ที่ทำงาน'),
  ('home_phone', 'เบอร์บ้าน'),
  ('tel', 'เบอร์โทรศัพท์'),
  ('contact_mobile', 'มือถือผู้ติดต่อ'),
  ('contact_phone', 'โทรศัพท์ผู้ติดต่อ'),
  ('account_mobile', 'มือถือลูกค้า'),
  ('account_phone', 'โทรศัพท์ลูกค้า'),
];

/// Every distinct phone number on a row, in field order.
List<NxPhone> nxRowPhones(Map<String, dynamic> row) {
  final out = <NxPhone>[];
  final seen = <String>{};
  for (final (k, label) in _phoneFields) {
    final v = row[k]?.toString().trim() ?? '';
    if (v.isEmpty || v == 'null') continue;
    final digits = v.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.length < 3 || !seen.add(digits)) continue;
    out.add((label: label, number: v));
  }
  return out;
}

/// "โทรหา {name}?" — shows the number; with several numbers the user picks
/// one. Returns the number to dial, or null when cancelled.
Future<String?> showCallConfirm(BuildContext context, {required String name, required List<NxPhone> phones}) {
  if (phones.isEmpty) return Future.value();
  HapticFeedback.selectionClick();
  return showAppBottomSheet<String>(
    context: context,
    title: tr('โทรหา $name?'),
    child: _CallBody(phones: phones),
  );
}

class _CallBody extends StatefulWidget {
  const _CallBody({required this.phones});
  final List<NxPhone> phones;

  @override
  State<_CallBody> createState() => _CallBodyState();
}

class _CallBodyState extends State<_CallBody> {
  var _i = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final many = widget.phones.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (many)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(tr('เลือกเบอร์ที่จะโทร'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
        for (final (i, p) in widget.phones.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: i == _i ? cs.primary.withValues(alpha: 0.10) : cs.surfaceContainerHighest.withValues(alpha: 0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: i == _i ? cs.primary : Colors.transparent, width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('call-number-$i'),
                onTap: many
                    ? () {
                        HapticFeedback.selectionClick();
                        setState(() => _i = i);
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: cs.primary.withValues(alpha: 0.14),
                        child: Icon(NxI.phoneCall, size: 20, color: cs.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.number, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                            Text(tr(p.label), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      if (many) Icon(i == _i ? NxI.checkCircle : NxI.circle, color: i == _i ? cs.primary : cs.outlineVariant),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        NxConfirmButtons(
          confirmKey: const ValueKey('call-confirm'),
          confirmLabel: 'โทร',
          icon: NxI.phoneCall,
          color: cs.primary,
          onConfirm: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context, widget.phones[_i].number);
          },
        ),
      ],
    );
  }
}

/// Red destructive sheet "ลบ {name}?" listing what will be lost.
/// Returns true only when confirmed.
Future<bool> showDeleteConfirm(
  BuildContext context, {
  required String name,
  List<String> loses = const ['ข้อมูลทั้งหมดของรายการนี้', 'คอมเม้นท์และไฟล์แนบ', 'ประวัติการเปลี่ยนแปลง'],
  String? note = 'กด "เลิกทำ" ได้ภายใน 5 วินาทีหลังลบ',
  String? title,
  String confirmLabel = 'ลบ',
}) async {
  HapticFeedback.mediumImpact();
  final ok = await showAppBottomSheet<bool>(
    context: context,
    title: title ?? tr('ลบ $name?'),
    child: Builder(builder: (ctx) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            key: const ValueKey('delete-confirm-loses'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kNxDangerRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kNxDangerRed.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(NxI.trash, size: 20, color: kNxDangerRed),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tr('สิ่งที่จะหายไป'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: kNxDangerRed)),
                  ),
                ]),
                const SizedBox(height: 8),
                for (final l in loses)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 7, right: 8),
                        child: Container(width: 5, height: 5, decoration: const BoxDecoration(color: kNxDangerRed, shape: BoxShape.circle)),
                      ),
                      Expanded(child: Text(tr(l), style: theme.textTheme.bodyMedium)),
                    ]),
                  ),
              ],
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 10),
            Text(tr(note), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
          const SizedBox(height: 18),
          NxConfirmButtons(
            confirmKey: const ValueKey('delete-confirm'),
            confirmLabel: confirmLabel,
            icon: NxI.trash,
            color: kNxDangerRed,
            onConfirm: () {
              HapticFeedback.heavyImpact();
              Navigator.pop(ctx, true);
            },
          ),
        ],
      );
    }),
  );
  return ok == true;
}

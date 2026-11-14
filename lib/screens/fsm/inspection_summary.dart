import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/nx_skeleton.dart';
import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_icons.dart';
import '../docs/document_preview.dart';
import 'inspection_lines.dart';

/// Counts of an inspection checklist.
class InspCounts {
  const InspCounts({this.pass = 0, this.fail = 0, this.na = 0, this.none = 0});
  final int pass, fail, na, none;
  int get total => pass + fail + na + none;
  int get checked => pass + fail + na;
  double get progress => total == 0 ? 0 : checked / total;

  static InspCounts of(List<Map<String, dynamic>> lines) {
    var p = 0, f = 0, n = 0, o = 0;
    for (final l in lines) {
      switch (inspResultOf(l)) {
        case InspResult.pass:
          p++;
        case InspResult.fail:
          f++;
        case InspResult.na:
          n++;
        case InspResult.none:
          o++;
      }
    }
    return InspCounts(pass: p, fail: f, na: n, none: o);
  }
}

/// Overall verdict from the checklist.
enum InspVerdict { empty, inProgress, passed, failed }

InspVerdict inspVerdict(InspCounts c) {
  if (c.total == 0) return InspVerdict.empty;
  if (c.none > 0) return InspVerdict.inProgress;
  return c.fail > 0 ? InspVerdict.failed : InspVerdict.passed;
}

/// "สรุป" tab of an inspection: progress ring + verdict, counts, the next
/// step, items that failed, linked job / customer, signatures and the
/// document — everything a technician needs on one screen.
class InspectionSummary extends StatefulWidget {
  const InspectionSummary({
    super.key,
    required this.row,
    required this.canEdit,
    required this.onGoTab,
    required this.onOpen,
    this.onChangeStatus,
    this.statusLabel,
  });

  /// Display label of the status (picklist label), when known.
  final String? statusLabel;

  final Map<String, dynamic> row;
  final bool canEdit;
  final void Function(String tab) onGoTab;
  final void Function(String module, String id) onOpen;
  final VoidCallback? onChangeStatus;

  @override
  State<InspectionSummary> createState() => _InspectionSummaryState();
}

class _InspectionSummaryState extends State<InspectionSummary> {
  List<Map<String, dynamic>>? _lines;
  Object? _error;
  String? _jobTitle;
  bool _techSigned = false;
  bool _signing = false;

  /// Technician signature from my profile (same as the web button).
  Future<void> _useMySignature() async {
    final api = context.read<AppConfig>().apiClient;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _signing = true);
    try {
      final sig = await api.getMySignatures();
      final path = [sig['upload_signature_th'], sig['upload_signature_en'], sig['signature_image']].firstWhere((x) => x != null && '$x'.isNotEmpty, orElse: () => null);
      if (path == null) {
        messenger.showSnackBar(SnackBar(content: Text(tr('ยังไม่มีลายเซ็นในโปรไฟล์ — ไปที่โปรไฟล์ › ลายเซ็นของฉัน'))));
        return;
      }
      await api.putEntity('inspection', _id, {'technician_signature': path, 'technician_signed_at': DateTime.now().toUtc().toIso8601String()});
      if (mounted) setState(() => _techSigned = true);
      messenger.showSnackBar(SnackBar(content: Text(tr('เติมลายเซ็นช่างแล้ว'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    } finally {
      if (mounted) setState(() => _signing = false);
    }
  }

  String get _id => strId(widget.row['id']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final jobId = strId(widget.row['related_job_id']);
    if (jobId.isNotEmpty && _linked('related_job_id').isEmpty) {
      // Job number + name (the inspection only stores the id).
      context.read<AppConfig>().apiClient.getEntity('job', jobId).then((j) {
        final t = [j['job_no'], j['job_name']].where((x) => x != null && '$x'.trim().isNotEmpty).join(' · ');
        if (mounted && t.isNotEmpty) setState(() => _jobTitle = t);
      }).catchError((_) {});
    }
    try {
      final l = await context.read<AppConfig>().apiClient.getInspectionLines(_id);
      if (mounted) setState(() => _lines = l);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _dt(String k) => formatThaiField(widget.row[k], k, module: 'inspection', year: uiYear);

  String _s(String k) => '${widget.row[k] ?? ''}'.trim();

  /// Display name of a linked record (`x_name` / `x_label` from the server).
  String _linked(String key) {
    for (final k in ['${key}_name', '${key}_label', '${key}_display']) {
      final v = _s(k);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final lines = _lines;
    if (lines == null && _error == null) {
      // Counter tiles, then the result card and line rows.
      return const NxSkeleton(
        key: ValueKey('insp-summary-skeleton'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          NxSkeletonGrid(cols: 3, count: 3, tileHeight: 84, gap: 8),
          SizedBox(height: 12),
          NxSkeletonKeyValueCard(rows: 3, total: false),
          NxSkeletonRow(leading: NxSkelLeading.icon, leadingSize: 32, trailing: NxSkelTrailing.pill),
          NxSkeletonRow(leading: NxSkelLeading.icon, leadingSize: 32, trailing: NxSkelTrailing.pill, wide: false),
        ]),
      );
    }
    final c = InspCounts.of(lines ?? const []);
    final verdict = inspVerdict(c);
    final (vColor, vIcon, vText) = switch (verdict) {
      InspVerdict.empty => (cs.outline, NxI.clipboardText, tr('ยังไม่มีรายการตรวจ')),
      InspVerdict.inProgress => (const Color(0xFFD97706), NxI.timer, tr('กำลังตรวจ')),
      InspVerdict.passed => (const Color(0xFF16A34A), NxI.check, tr('ผ่านทุกรายการ')),
      InspVerdict.failed => (cs.error, NxI.warning, '${tr('ไม่ผ่าน')} ${c.fail} ${tr('รายการ')}'),
    };
    final failed = [for (final l in lines ?? const <Map<String, dynamic>>[]) if (inspResultOf(l) == InspResult.fail) l];

    Widget card({required Widget child, Key? key, EdgeInsets padding = const EdgeInsets.all(16)}) => Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: child,
    );

    Widget title(IconData icon, String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(tr(text), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
        ?trailing,
      ]),
    );

    // Next step.
    final (String nextLabel, IconData nextIcon, VoidCallback? nextTap) = switch (verdict) {
      InspVerdict.empty => (tr('เพิ่มรายการตรวจ'), NxI.plus, () => widget.onGoTab('checklist')),
      InspVerdict.inProgress => ('${tr('ตรวจต่อ')} · ${tr('เหลือ')} ${c.none}', NxI.listChecks, () => widget.onGoTab('checklist')),
      _ => widget.canEdit && widget.onChangeStatus != null
          ? (tr('ตรวจครบแล้ว — บันทึกสถานะใบตรวจรับ'), NxI.flag, widget.onChangeStatus)
          : (tr('ดูรายการตรวจ'), NxI.listChecks, () => widget.onGoTab('checklist')),
    };

    final jobId = strId(widget.row['related_job_id']);
    final accId = strId(widget.row['related_account_id']);
    final assetId = strId(widget.row['related_asset_id']);
    final locId = strId(widget.row['related_location_id']);
    final customer = _linked('related_account_id').isNotEmpty ? _linked('related_account_id') : _s('customer_name');

    return Column(
      key: const ValueKey('insp-sum-root'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero: ring + verdict.
        Container(
          key: const ValueKey('insp-sum-hero'),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [vColor.withValues(alpha: 0.16), cs.primary.withValues(alpha: 0.06)],
            ),
          ),
          child: Row(children: [
            SizedBox(
              width: 104,
              height: 104,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: c.progress),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => CustomPaint(
                  painter: _RingPainter(value: v, color: vColor, track: cs.onSurface.withValues(alpha: 0.08), fail: c.total == 0 ? 0 : c.fail / c.total, failColor: cs.error),
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('${(v * 100).round()}%', key: const ValueKey('insp-sum-pct'), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                      Text('${c.checked}/${c.total}', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(_s('inspection_no').isEmpty ? '#$_id' : _s('inspection_no'), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(_s('inspection_name').isEmpty ? tr('ใบตรวจรับ') : _s('inspection_name'), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.3)),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _Pill(key: const ValueKey('insp-sum-verdict'), icon: vIcon, text: vText, color: vColor, solid: true),
                  if (_s('inspection_status').isNotEmpty) _Pill(icon: NxI.flag, text: widget.statusLabel ?? _s('inspection_status'), color: cs.primary),
                ]),
              ]),
            ),
          ]),
        ),
        if (_error != null)
          card(child: Text(tr(formatApiError(_error!)), style: TextStyle(color: cs.error))),

        // Counts.
        Row(children: [
          for (final (key, label, n, color) in [
            ('pass', 'ผ่าน', c.pass, const Color(0xFF16A34A)),
            ('fail', 'ไม่ผ่าน', c.fail, cs.error),
            ('na', 'N/A', c.na, cs.outline),
            ('none', 'ยังไม่ตรวจ', c.none, const Color(0xFFD97706)),
          ])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Material(
                  color: color.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    key: ValueKey('insp-sum-count-$key'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => widget.onGoTab('checklist'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(children: [
                        Text('$n', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: color)),
                        Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),

        // Next step.
        FilledButton.icon(
          key: const ValueKey('insp-sum-next'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          onPressed: nextTap,
          icon: Icon(nextIcon, size: 20),
          label: Text(nextLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 14),

        if (failed.isNotEmpty)
          card(
            key: const ValueKey('insp-sum-failed'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              title(NxI.warning, 'รายการที่ไม่ผ่าน', trailing: Text('${failed.length}', style: TextStyle(color: cs.error, fontWeight: FontWeight.w800))),
              for (final l in failed.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(padding: const EdgeInsets.only(top: 3), child: Icon(NxI.x, size: 16, color: cs.error)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${l['item_label'] ?? ''}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                        if ('${l['remark'] ?? ''}'.trim().isNotEmpty) Text('${l['remark']}', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ]),
                    ),
                  ]),
                ),
              if (failed.length > 6) TextButton(onPressed: () => widget.onGoTab('checklist'), child: Text('${tr('ดูทั้งหมด')} (${failed.length})')),
            ]),
          ),

        // Linked records.
        if (jobId.isNotEmpty || customer.isNotEmpty || assetId.isNotEmpty || locId.isNotEmpty)
          card(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              title(NxI.link, 'เชื่อมโยง'),
              if (jobId.isNotEmpty) _linkRow(theme, 'insp-sum-job', NxI.wrench, tr('ใบสั่งงาน'), _linked('related_job_id').isNotEmpty ? _linked('related_job_id') : (_jobTitle ?? '#$jobId'), () => widget.onOpen('job', jobId)),
              if (customer.isNotEmpty) _linkRow(theme, 'insp-sum-account', NxI.buildings, tr('ลูกค้า'), customer, accId.isEmpty ? null : () => widget.onOpen('account', accId)),
              if (assetId.isNotEmpty) _linkRow(theme, 'insp-sum-asset', NxI.package, tr('สินทรัพย์'), _linked('related_asset_id').isEmpty ? '#$assetId' : _linked('related_asset_id'), () => widget.onOpen('asset', assetId)),
              if (locId.isNotEmpty) _linkRow(theme, 'insp-sum-location', NxI.mapPin, tr('สถานที่'), _linked('related_location_id').isEmpty ? '#$locId' : _linked('related_location_id'), () => widget.onOpen('service_location', locId)),
            ]),
          ),

        // Signatures.
        card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            title(NxI.penLine, 'ลายเซ็น'),
            _signRow(theme, tr('ช่างผู้ตรวจ'), _techSigned || _s('technician_signature').isNotEmpty, _s('technician_signed_at')),
            if (widget.canEdit && !_techSigned && _s('technician_signature').isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('insp-use-my-signature'),
                  onPressed: _signing ? null : _useMySignature,
                  icon: const Icon(NxI.penLine, size: 16),
                  label: Text(tr('ใช้ลายเซ็นของฉัน (จากโปรไฟล์)')),
                ),
              ),
            const SizedBox(height: 8),
            _signRow(theme, tr('ลูกค้า'), _s('customer_signature').isNotEmpty || _s('signed_at').isNotEmpty, _s('signed_at'), name: _s('signed_by_name')),
          ]),
        ),

        // Dates.
        if (_s('plan_time').isNotEmpty || _s('act_time').isNotEmpty || _s('createdtime').isNotEmpty)
          card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              title(NxI.calendarCheck, 'เวลา'),
              if (_s('plan_time').isNotEmpty) _kv(theme, tr('นัดตรวจ'), _dt('plan_time')),
              if (_s('act_time').isNotEmpty) _kv(theme, tr('ตรวจจริง'), _dt('act_time')),
              if (_s('createdtime').isNotEmpty) _kv(theme, tr('สร้างเมื่อ'), _dt('createdtime')),
            ]),
          ),

        DocumentCard(source: () => inspectionDocumentSource(_id, no: _s('inspection_no').isEmpty ? null : _s('inspection_no'))),
      ],
    );
  }

  Widget _linkRow(ThemeData theme, String key, IconData icon, String label, String value, VoidCallback? onTap) => InkWell(
    key: ValueKey(key),
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
        if (onTap != null) Icon(NxI.caretRight, size: 16, color: theme.colorScheme.outline),
        const SizedBox(width: 6),
      ]),
    ),
  );

  Widget _signRow(ThemeData theme, String who, bool signed, String at, {String name = ''}) {
    final c = signed ? const Color(0xFF16A34A) : theme.colorScheme.outline;
    return Row(children: [
      Icon(signed ? NxI.check : NxI.penLine, size: 18, color: c),
      const SizedBox(width: 10),
      Expanded(child: Text(who, style: theme.textTheme.bodyMedium)),
      Text(
        signed ? [tr('เซ็นแล้ว'), if (name.isNotEmpty) name, if (at.isNotEmpty) formatThaiField(at, 'signed_at', module: 'inspection', year: uiYear)].join(' · ') : tr('ยังไม่เซ็น'),
        style: theme.textTheme.labelMedium?.copyWith(color: c, fontWeight: FontWeight.w700),
      ),
    ]);
  }

  Widget _kv(ThemeData theme, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(width: 96, child: Text(k, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
      Expanded(child: Text(v, style: theme.textTheme.bodyMedium)),
    ]),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.icon, required this.text, required this.color, this.solid = false});
  final IconData icon;
  final String text;
  final Color color;
  final bool solid;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: solid ? color : color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: solid ? Colors.white : color),
      const SizedBox(width: 5),
      Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: solid ? Colors.white : color))),
    ]),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color, required this.track, required this.fail, required this.failColor});
  final double value, fail;
  final Color color, track, failColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, 0, math.pi * 2, false, base..color = track);
    if (value <= 0) return;
    const start = -math.pi / 2;
    canvas.drawArc(arc, start, math.pi * 2 * value, false, base..color = color);
    // Failed share drawn at the end of the arc.
    final f = math.min(fail, value);
    if (f > 0) canvas.drawArc(arc, start + math.pi * 2 * (value - f), math.pi * 2 * f, false, base..color = failColor);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.fail != fail;
}

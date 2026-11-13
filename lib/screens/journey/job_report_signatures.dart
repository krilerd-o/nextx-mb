import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/journey_rules.dart';
import '../../core/thai_time.dart';
import '../../services/api_exceptions.dart' show ApiEnvelopeException, formatApiError;
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_surface_card.dart';

/// The app's own orientation outside the signing page: the app does not lock
/// it (empty list = whatever the platform / Info.plist allows).
const List<DeviceOrientation> kAppOrientations = <DeviceOrientation>[];

/// The signing page may turn: portrait or landscape (more room to sign).
const kSignOrientations = [DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];

/// Exported signature size: the report's signature box is about 8 : 3.
const kSignExportSize = Size(720, 270);

/// One report signer: (title TH, title EN on the report, short label).
({String th, String en}) jobSignerTitle(String role) => role == 'technician' ? (th: 'ผู้ให้บริการ', en: 'Serviced by') : (th: 'ลูกค้า', en: 'Customer accepted by');

String _clean(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s == 'null' ? '' : s;
}

/// Default signer name: technician = the name already on the job, else the
/// engineer, else me; customer = the name on the job, else the job contact.
String jobSignerDefaultName(Map<String, dynamic> row, String role, {String? me}) {
  final on = _clean(row['${role}_signed_by_name']);
  if (on.isNotEmpty) return on;
  if (role == 'technician') {
    final eng = _clean(row['engineer_name']);
    return eng.isNotEmpty ? eng : (me ?? '').trim();
  }
  final contact = _clean(row['customer_contact_name']);
  return contact.isNotEmpty ? contact : _clean(row['customer_name']);
}

/// `2026-11-13 03:00:00` (UTC digits) — what the web job form stores in
/// `{role}_signed_at` (`new Date().toISOString().slice(0, 19)`).
String jobSignedAtNow([DateTime? now]) {
  final u = (now ?? DateTime.now()).toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
}

/// Sign one report box: full-screen page → upload the PNG
/// (`POST /api/uploads/signature`, same as the web) → `PUT /api/entity/job/:id`
/// with `{role}_signature` (path), `{role}_signed_by_name`, `{role}_signed_at`.
Future<bool> signJobReport(BuildContext context, {required String jobId, required Map<String, dynamic> row, required String role}) async {
  final config = context.read<AppConfig>();
  final api = config.apiClient;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final t = jobSignerTitle(role);
  final result = await Navigator.of(context, rootNavigator: true).push<JobSignResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => JobSignPage(
        title: tr('ลายเซ็น${t.th}'),
        subtitle: t.en,
        initialName: jobSignerDefaultName(row, role, me: config.session.displayName),
        nameLabel: role == 'technician' ? 'ชื่อผู้ให้บริการ' : 'ชื่อลูกค้า',
      ),
    ),
  );
  if (result == null) return false;
  try {
    final path = await api.uploadSignatureImage(result.png, 'job-$jobId-$role.png');
    await api.putEntity('job', jobId, {'${role}_signature': path, '${role}_signed_by_name': result.name.isEmpty ? null : result.name, '${role}_signed_at': jobSignedAtNow()});
    HapticFeedback.mediumImpact();
    messenger?.showSnackBar(SnackBar(content: Text(tr('บันทึกลายเซ็น${t.th}แล้ว'))));
    return true;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    return false;
  }
}

/// 409 `JOB_SIGNATURES_REQUIRED` (server setting `close.require_both_signatures`)
/// → the report signers still missing (`technician` / `customer`); null for any
/// other error.
List<String>? jobSignaturesRequiredMissing(Object e) {
  if (e is! ApiEnvelopeException || e.errorCode != 'JOB_SIGNATURES_REQUIRED') return null;
  final m = jobSignatureRolesFromServer(e.details?['missing']);
  return m.isEmpty ? List<String>.of(kJobReportSigners) : m;
}

/// Friendly text for a close blocked by missing signatures (same wording as the web).
String jobSignaturesRequiredText(List<String> missing) {
  final th = [for (final r in missing) r == 'technician' ? 'ลายเซ็นช่าง/ผู้ให้บริการ' : 'ลายเซ็นลูกค้า'];
  final en = [for (final r in missing) r == 'technician' ? 'technician signature' : 'customer signature'];
  return L10n.isEn
      ? 'Cannot close yet: both the technician and the customer must sign — missing ${en.join(' and ')}'
      : 'ปิดงานไม่ได้: ต้องมีลายเซ็นทั้งช่างและลูกค้า — ยังขาด${th.join(' และ ')}';
}

const _kOpenSection = '__section';

/// Close needs both report signatures (business setting
/// `close.require_both_signatures`, default on; a signed staff / customer slot
/// counts). Shows what is missing with a "เซ็นตอนนี้" shortcut per signer and,
/// with [openSignatures], a button that scrolls to / opens the signature
/// section. [missing] defaults to the row's report boxes; [message] replaces
/// the explanation (e.g. after a 409 from the server). true = signed everything
/// from here (the caller may go on closing after a reload).
Future<bool> showJobSignaturesRequired(
  BuildContext context, {
  required String jobId,
  required Map<String, dynamic> row,
  List<String>? missing,
  String? message,
  VoidCallback? openSignatures,
}) async {
  final need = missing ?? jobReportMissing(row);
  if (need.isEmpty) return true;
  final role = await showAppBottomSheet<String>(
    context: context,
    title: tr('ต้องมีลายเซ็นก่อนปิดงาน'),
    child: Builder(
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        return Column(
          key: const ValueKey('job-close-needs-signatures'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              message ?? tr('ทุกใบงานต้องมีลายเซ็น 2 รายการ — ผู้ให้บริการ และลูกค้า'),
              key: const ValueKey('job-close-needs-signatures-text'),
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final r in kJobReportSigners)
              ListTile(
                key: ValueKey('job-close-sig-$r'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(need.contains(r) ? NxI.warningCircle : NxI.checkCircle, color: need.contains(r) ? const Color(0xFFD97706) : const Color(0xFF16A34A)),
                title: Text(tr(jobSignerTitle(r).th)),
                subtitle: Text(tr(need.contains(r) ? 'ยังไม่ได้เซ็น' : 'เซ็นแล้ว')),
                trailing: need.contains(r)
                    ? FilledButton.tonalIcon(key: ValueKey('job-close-sign-$r'), onPressed: () => Navigator.pop(ctx, r), icon: const Icon(NxI.penLine, size: 16), label: Text(tr('เซ็นตอนนี้')))
                    : null,
              ),
            if (openSignatures != null) ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                key: const ValueKey('job-close-open-signatures'),
                onPressed: () => Navigator.pop(ctx, _kOpenSection),
                icon: const Icon(NxI.penLine, size: 18),
                label: Text(tr('ไปที่ส่วนลายเซ็น')),
              ),
            ],
          ],
        );
      },
    ),
  );
  if (role == null || !context.mounted) return false;
  if (role == _kOpenSection) {
    openSignatures?.call();
    return false;
  }
  final ok = await signJobReport(context, jobId: jobId, row: row, role: role);
  return ok && need.length == 1;
}

/// A close failed with 409 `JOB_SIGNATURES_REQUIRED`: explain and offer
/// "เซ็นตอนนี้" (see [showJobSignaturesRequired]). false = not that error.
Future<bool> handleJobCloseSignatureError(
  BuildContext context,
  Object e, {
  required String jobId,
  required Map<String, dynamic> row,
  VoidCallback? openSignatures,
}) async {
  final missing = jobSignaturesRequiredMissing(e);
  if (missing == null || !context.mounted) return false;
  await showJobSignaturesRequired(context, jobId: jobId, row: row, missing: missing, message: jobSignaturesRequiredText(missing), openSignatures: openSignatures);
  return true;
}

/// The two report signature boxes on the job summary: "ผู้ให้บริการ"
/// (Serviced by) and "ลูกค้า" (Customer accepted by), side by side, equal size.
class JobReportSignatures extends StatelessWidget {
  const JobReportSignatures({super.key, required this.jobId, required this.row, required this.canEdit, required this.onChanged});

  final String jobId;
  final Map<String, dynamic> row;
  final bool canEdit;
  final VoidCallback onChanged;

  bool get _locked {
    final st = canonicalJobStatus(row['job_status']);
    return st == 'Completed' || st == 'Cancelled';
  }

  Future<void> _clear(BuildContext context, String role) async {
    final ok = await showAppBottomSheet<bool>(
      context: context,
      title: tr('ล้างลายเซ็น${jobSignerTitle(role).th}?'),
      child: Builder(
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('job-sig-clear-confirm'),
                  style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(tr('ล้าง')),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await context.read<AppConfig>().apiClient.putEntity('job', jobId, {'${role}_signature': null, '${role}_signed_by_name': null, '${role}_signed_at': null});
      onChanged();
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final editable = canEdit && !_locked;
    return LayoutBuilder(
      builder: (context, c) {
        final boxes = [
          for (final role in kJobReportSigners)
            _SignBox(
              key: ValueKey('job-sig-box-$role'),
              role: role,
              row: row,
              onTap: editable
                  ? () async {
                      final ok = await signJobReport(context, jobId: jobId, row: row, role: role);
                      if (ok) onChanged();
                    }
                  : null,
              onClear: editable && jobReportSigned(row, role) ? () => _clear(context, role) : null,
            ),
        ];
        // Very narrow / huge text: stack them.
        if (c.maxWidth < 300) {
          return Column(children: [boxes[0], const SizedBox(height: 10), boxes[1]]);
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: boxes[0]),
              const SizedBox(width: 10),
              Expanded(child: boxes[1]),
            ],
          ),
        );
      },
    );
  }
}

class _SignBox extends StatelessWidget {
  const _SignBox({super.key, required this.role, required this.row, this.onTap, this.onClear});
  final String role;
  final Map<String, dynamic> row;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final api = context.read<AppConfig>().apiClient;
    final t = jobSignerTitle(role);
    final signed = jobReportSigned(row, role);
    final path = _clean(row['${role}_signature']);
    final name = _clean(row['${role}_signed_by_name']).isNotEmpty ? _clean(row['${role}_signed_by_name']) : (role == 'technician' ? _clean(row['engineer_name']) : '');
    final at = parseThai(row['${role}_signed_at']);
    String two(int n) => n.toString().padLeft(2, '0');
    final when = at == null ? '' : '${at.day}/${at.month}/${uiYear(at.year)} ${two(at.hour)}:${two(at.minute)}';
    Widget image;
    if (path.startsWith('data:')) {
      final b64 = path.substring(path.indexOf(',') + 1);
      Uint8List? bytes;
      try {
        bytes = base64Decode(b64);
      } catch (_) {}
      image = bytes == null ? Icon(NxI.checkCircle, color: cs.primary) : Image.memory(bytes, fit: BoxFit.contain);
    } else {
      final url = path.startsWith('http') || path.startsWith('/') ? path : '/uploads/$path';
      image = Image.network(
        api.absoluteUrl(url),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Center(child: Icon(NxI.checkCircle, color: cs.primary)),
      );
    }
    final accent = signed ? const Color(0xFF16A34A) : (onTap != null ? cs.primary : cs.onSurfaceVariant);
    return NxSurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(signed ? NxI.checkCircle : NxI.penLine, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(t.th),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      t.en,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (onClear != null)
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    key: ValueKey('job-sig-clear-$role'),
                    padding: EdgeInsets.zero,
                    tooltip: tr('ล้าง'),
                    onPressed: onClear,
                    icon: Icon(NxI.trash, size: 16, color: cs.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 84,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: signed ? cs.outlineVariant : accent.withValues(alpha: 0.45), width: signed ? 1 : 1.4),
            ),
            padding: const EdgeInsets.all(6),
            alignment: Alignment.center,
            child: signed
                ? KeyedSubtree(key: ValueKey('job-sig-image-$role'), child: image)
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      key: ValueKey('job-sig-empty-$role'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(NxI.penLine, size: 20, color: onTap != null ? cs.primary : Colors.black38),
                        const SizedBox(height: 4),
                        Text(
                          tr(onTap != null ? 'แตะเพื่อเซ็น' : 'ยังไม่ได้เซ็น'),
                          style: theme.textTheme.labelMedium?.copyWith(color: onTap != null ? cs.primary : Colors.black54, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            name.isEmpty ? '( ${tr('ชื่อผู้เซ็น')} )' : '( $name )',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: name.isEmpty ? cs.onSurfaceVariant : null),
          ),
          Text(
            '${tr('วันที่')} ${when.isEmpty ? '—' : when}',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// What the signing page returns.
class JobSignResult {
  const JobSignResult(this.png, this.name);
  final Uint8List png;
  final String name;
}

/// Full-screen signing page. The phone may turn to landscape here (more room);
/// the app's orientation is restored on leave. A guide frame with a baseline
/// ("เซ็นในกรอบนี้") places the signature; on save the strokes are trimmed and
/// scaled to fill the report box ([kSignExportSize], transparent PNG — the
/// same kind of file the web's signature pad uploads).
class JobSignPage extends StatefulWidget {
  const JobSignPage({super.key, required this.title, this.subtitle, this.initialName = '', this.nameLabel = 'ชื่อผู้เซ็น'});
  final String title;
  final String? subtitle;
  final String initialName;
  final String nameLabel;

  @override
  State<JobSignPage> createState() => _JobSignPageState();
}

class _JobSignPageState extends State<JobSignPage> {
  final _strokes = <List<Offset>>[];
  late final TextEditingController _name = TextEditingController(text: widget.initialName);
  Size _padSize = Size.zero;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(kSignOrientations);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(kAppOrientations);
    _name.dispose();
    super.dispose();
  }

  bool get _hasInk => _strokes.any((s) => s.isNotEmpty);

  Future<void> _save() async {
    if (!_hasInk || _saving) return;
    setState(() => _saving = true);
    final png = await exportSignaturePng(_strokes, strokeWidth: 3.2, size: kSignExportSize);
    if (!mounted) return;
    if (png == null) {
      setState(() => _saving = false);
      return;
    }
    Navigator.of(context).pop(JobSignResult(png, _name.text.trim()));
  }

  void _down(Offset p) => setState(() => _strokes.add([p]));
  void _move(Offset p) {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.last.add(p));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final pad = Container(
      key: const ValueKey('job-sign-pad'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, c) {
          _padSize = c.biggest;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _down(e.localPosition),
            onPointerMove: (e) => _move(e.localPosition),
            child: CustomPaint(
              painter: _SignGuidePainter(label: tr('เซ็นในกรอบนี้'), hide: _hasInk, textStyle: theme.textTheme.labelLarge),
              foregroundPainter: _InkPainter(_strokes),
              size: Size.infinite,
            ),
          );
        },
      ),
    );
    final name = TextField(
      key: const ValueKey('job-sign-name'),
      controller: _name,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(labelText: tr(widget.nameLabel), prefixIcon: const Icon(NxI.user, size: 18), isDense: true),
    );
    final save = SizedBox(
      height: 50,
      child: FilledButton.icon(
        key: const ValueKey('job-sign-save'),
        onPressed: _hasInk && !_saving ? _save : null,
        icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(NxI.check, size: 20),
        label: Text(tr('บันทึกลายเซ็น'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
    return Scaffold(
      key: const ValueKey('job-sign-page'),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title),
            if (widget.subtitle != null) Text(widget.subtitle!, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('job-sign-undo'),
            tooltip: tr('ย้อนกลับ'),
            onPressed: _strokes.isEmpty || _saving ? null : () => setState(_strokes.removeLast),
            icon: const Icon(NxI.arrowCounterClockwise),
          ),
          TextButton(key: const ValueKey('job-sign-clear'), onPressed: _strokes.isEmpty || _saving ? null : () => setState(_strokes.clear), child: Text(tr('ล้าง'))),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: landscape
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: pad),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 240,
                      child: SingleChildScrollView(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [name, const SizedBox(height: 12), save]),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    name,
                    const SizedBox(height: 12),
                    Expanded(child: pad),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(NxI.deviceMobile, size: 16, color: cs.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(tr('หมุนเครื่องเป็นแนวนอนเพื่อเซ็นได้กว้างขึ้น'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    save,
                  ],
                ),
        ),
      ),
    );
  }

  /// Visible for tests: pad size the last layout gave.
  Size get padSize => _padSize;
}

/// Strokes → PNG of [size]: trimmed to their bounds, scaled to fill the box
/// (keeping the aspect, 6% margin), centred; transparent background.
Future<Uint8List?> exportSignaturePng(List<List<Offset>> strokes, {double strokeWidth = 3, Size size = kSignExportSize}) async {
  final pts = [for (final s in strokes) ...s];
  if (pts.isEmpty) return null;
  var minX = pts.first.dx, maxX = pts.first.dx, minY = pts.first.dy, maxY = pts.first.dy;
  for (final p in pts) {
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  final bw = math.max(maxX - minX, 1.0);
  final bh = math.max(maxY - minY, 1.0);
  // Pen width on the PNG (2.5–7 px), whatever the scale.
  const penMin = 2.5, penMax = 7.0;
  final mx = size.width * 0.05 + penMax / 2, my = size.height * 0.08 + penMax / 2;
  final scale = math.min((size.width - mx * 2) / bw, (size.height - my * 2) / bh);
  final dx = (size.width - bw * scale) / 2 - minX * scale;
  final dy = (size.height - bh * scale) / 2 - minY * scale;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.translate(dx, dy);
  canvas.scale(scale);
  final w = (strokeWidth * scale).clamp(penMin, penMax) / scale;
  _InkPainter.paintStrokes(canvas, strokes, w);
  final pic = rec.endRecording();
  final img = await pic.toImage(size.width.round(), size.height.round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  pic.dispose();
  return data?.buffer.asUint8List();
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.strokes);
  final List<List<Offset>> strokes;

  static void paintStrokes(Canvas canvas, List<List<Offset>> strokes, double width) {
    final p = Paint()
      ..color = const Color(0xFF111827)
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (final s in strokes) {
      if (s.isEmpty) continue;
      if (s.length == 1) {
        canvas.drawCircle(s.first, width / 2, Paint()..color = p.color);
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (var i = 1; i < s.length - 1; i++) {
        final mid = Offset((s[i].dx + s[i + 1].dx) / 2, (s[i].dy + s[i + 1].dy) / 2);
        path.quadraticBezierTo(s[i].dx, s[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(s.last.dx, s.last.dy);
      canvas.drawPath(path, p);
    }
  }

  @override
  void paint(Canvas canvas, Size size) => paintStrokes(canvas, strokes, 3.2);

  @override
  bool shouldRepaint(covariant _InkPainter old) => true;
}

/// Guide frame (dashed, 8 : 3 like the report box), baseline with an "×" and
/// the "เซ็นในกรอบนี้" hint (hidden once there is ink).
class _SignGuidePainter extends CustomPainter {
  _SignGuidePainter({required this.label, required this.hide, this.textStyle});
  final String label;
  final bool hide;
  final TextStyle? textStyle;

  static Rect frameFor(Size size) {
    final maxW = size.width * 0.9, maxH = size.height * 0.82;
    var w = maxW, h = maxW * 3 / 8;
    if (h > maxH) {
      h = maxH;
      w = h * 8 / 3;
    }
    return Rect.fromCenter(center: size.center(Offset.zero), width: w, height: h);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = frameFor(size);
    const guide = Color(0xFF94A3B8);
    final dash = Paint()
      ..color = guide.withValues(alpha: 0.7)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(14));
    final path = Path()..addRRect(rr);
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 12) {
        canvas.drawPath(m.extractPath(d, math.min(d + 7, m.length)), dash);
      }
    }
    final baseY = r.top + r.height * 0.72;
    canvas.drawLine(
      Offset(r.left + 28, baseY),
      Offset(r.right - 18, baseY),
      Paint()
        ..color = guide
        ..strokeWidth = 1.4,
    );
    final x = Paint()
      ..color = guide
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(r.left + 10, baseY - 14), Offset(r.left + 20, baseY - 4), x);
    canvas.drawLine(Offset(r.left + 20, baseY - 14), Offset(r.left + 10, baseY - 4), x);
    if (!hide) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: (textStyle ?? const TextStyle()).copyWith(color: guide, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r.width);
      tp.paint(canvas, Offset(r.center.dx - tp.width / 2, r.top + (baseY - r.top - tp.height) / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _SignGuidePainter old) => old.hide != hide || old.label != label;
}

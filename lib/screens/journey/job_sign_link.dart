import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_icons.dart';
import 'journey_widgets.dart';
import 'status_followups.dart';

/// "ลิงก์สำหรับลงนาม" of a job: the customer page `/public/job/<token>`
/// (no login) where the customer reads the job, acknowledges it and signs.
///
/// `POST /api/field-service/jobs/:id/public-link` makes a NEW token every
/// time (the old link stops working), so an existing `public_token` of the
/// job row is reused and a new one is made only on an explicit, confirmed
/// "สร้างลิงก์ใหม่".

/// Test seams for the platform share sheet / browser.
class PublicLinkHooks {
  PublicLinkHooks._();
  static Future<void> Function(String text)? share;
  static Future<void> Function(Uri uri)? open;

  static void reset() {
    share = null;
    open = null;
  }
}

Future<void> sharePublicLink(String text) async {
  final fn = PublicLinkHooks.share;
  if (fn != null) return fn(text);
  await Share.share(text);
}

Future<void> openPublicLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final fn = PublicLinkHooks.open;
  if (fn != null) return fn(uri);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) messenger?.showSnackBar(SnackBar(content: Text(tr('เปิดลิงก์ไม่ได้'))));
  } catch (_) {
    messenger?.showSnackBar(SnackBar(content: Text(tr('เปิดลิงก์ไม่ได้'))));
  }
}

void _copy(BuildContext context, String text, {String message = 'คัดลอกลิงก์แล้ว'}) {
  Clipboard.setData(ClipboardData(text: text));
  HapticFeedback.selectionClick();
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr(message))));
}

/// Customer status of the signing link — same rule as the web's
/// `JobDocumentsCard`: `Signed` (or a customer signature time) → signed,
/// `Accepted` → acknowledged, a token → link sent, else none. The server
/// stores `Accepted` / `Signed`; older rows may be lower case.
String jobSignLinkStatus(Map<String, dynamic> row, Map<String, dynamic> overview, {String? token}) {
  final ack = '${overview['customer_ack_status'] ?? row['customer_ack_status'] ?? ''}'.trim().toLowerCase();
  final signedAt = '${overview['customer_signed_at'] ?? row['customer_signed_at'] ?? ''}'.trim();
  if (ack == 'signed' || signedAt.isNotEmpty) return 'signed';
  if (ack == 'accepted') return 'accepted';
  final t = token ?? '${row['public_token'] ?? overview['public_token'] ?? ''}'.trim();
  if (t.isNotEmpty || ack == 'link_sent' || ack == 'sent') return 'sent';
  return 'none';
}

String jobSignLinkStatusLabel(String status) => tr(switch (status) {
      'signed' => 'ลูกค้าลงนามแล้ว',
      'accepted' => 'ลูกค้ารับทราบแล้ว',
      'sent' => 'ส่งลิงก์แล้ว · รอลงนาม',
      _ => 'ยังไม่ได้สร้างลิงก์',
    });

Color jobSignLinkStatusColor(String status, ColorScheme cs) => switch (status) {
      'signed' => const Color(0xFF16A34A),
      'accepted' => const Color(0xFF2563EB),
      'sent' => const Color(0xFFD97706),
      _ => cs.onSurfaceVariant,
    };

/// `nextx.app/…/1a2b3c4d…` — host and the start of the token, enough to
/// tell links apart on a phone-width chip.
String shortPublicLink(String url) {
  final u = Uri.tryParse(url);
  if (u == null) return url;
  final segs = u.pathSegments.where((e) => e.isNotEmpty).toList();
  if (segs.isEmpty) return u.host.isEmpty ? url : u.host;
  final last = segs.last.length > 10 ? '${segs.last.substring(0, 8)}…' : segs.last;
  final path = segs.length > 1 ? '…/$last' : last;
  return u.host.isEmpty ? '/$path' : '${u.host}/$path';
}

/// QR code drawn from the `qr` package (already in the build through
/// `printing` → `pdf`), dark modules on a white quiet zone.
class NxQrCode extends StatelessWidget {
  const NxQrCode({super.key, required this.data, this.size = 180});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    QrImage? img;
    try {
      img = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M));
    } catch (_) {
      img = null;
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: SizedBox.square(
        dimension: size,
        child: img == null ? const Center(child: Icon(NxI.qrCode, color: Colors.black54)) : CustomPaint(painter: _QrPainter(img)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.qr);
  final QrImage qr;

  @override
  void paint(Canvas canvas, Size size) {
    final n = qr.moduleCount;
    final cell = size.width / n;
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..isAntiAlias = false;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (qr.isDark(r, c)) canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell + 0.4, cell + 0.4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.qr != qr;
}

/// Link + QR + copy / share / open for a customer page (job or quotation).
Future<void> showPublicLinkSheet(BuildContext context, String url, {String? pdf, String title = 'ลิงก์สำหรับลงนาม', String? shareText}) {
  return showAppBottomSheet<void>(
    context: context,
    title: tr(title),
    child: Builder(builder: (ctx) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr('ลูกค้าเปิดได้ทันที ไม่ต้องล็อกอิน — ส่งทางแชต หรือให้สแกน QR ที่หน้างาน'),
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 14),
          Center(child: NxQrCode(key: const ValueKey('public-link-qr'), data: url, size: 176)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(children: [
              Icon(NxI.link, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(child: SelectableText(url, key: const ValueKey('public-link-url'), style: theme.textTheme.bodySmall)),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _linkButton(const ValueKey('public-link-copy'), NxI.copySimple, 'คัดลอก', () {
                _copy(ctx, url);
                Navigator.pop(ctx);
              }, primary: true, height: 48),
            ),
            const SizedBox(width: 8),
            Expanded(child: _linkButton(const ValueKey('public-link-share'), NxI.shareNetwork, 'แชร์', () => sharePublicLink(shareText ?? url), height: 48)),
            const SizedBox(width: 8),
            Expanded(child: _linkButton(const ValueKey('public-link-open'), NxI.arrowSquareOut, 'เปิด', () => openPublicLink(ctx, url), height: 48)),
          ]),
          if (pdf != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              key: const ValueKey('public-link-pdf'),
              onPressed: () {
                _copy(ctx, pdf, message: 'คัดลอกลิงก์ PDF แล้ว');
                Navigator.pop(ctx);
              },
              icon: const Icon(NxI.filePdf, size: 18),
              label: Text(tr('คัดลอกลิงก์ PDF')),
            ),
          ],
        ],
      );
    }),
  );
}

/// Equal-width link action: icon + label scaled down to fit (no wrapping).
Widget _linkButton(Key key, IconData icon, String label, VoidCallback onTap, {bool primary = false, double height = 40}) {
  final size = Size(0, height);
  const pad = EdgeInsets.symmetric(horizontal: 6);
  final child = FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16), const SizedBox(width: 5), Text(tr(label))]),
  );
  return primary
      ? FilledButton(key: key, style: FilledButton.styleFrom(minimumSize: size, padding: pad, visualDensity: VisualDensity.compact), onPressed: onTap, child: child)
      : OutlinedButton(key: key, style: OutlinedButton.styleFrom(minimumSize: size, padding: pad, visualDensity: VisualDensity.compact), onPressed: onTap, child: child);
}

/// Confirm before replacing the link: the old one stops working at once.
Future<bool> confirmRegeneratePublicLink(BuildContext context) async {
  HapticFeedback.mediumImpact();
  final ok = await showAppBottomSheet<bool>(
    context: context,
    title: tr('สร้างลิงก์ใหม่?'),
    child: Builder(builder: (ctx) {
      final theme = Theme.of(ctx);
      const amber = Color(0xFFD97706);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            key: const ValueKey('regen-link-warning'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: amber.withValues(alpha: 0.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(NxI.warning, size: 20, color: amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr('ลิงก์เดิมจะใช้ไม่ได้ทันที ต้องส่งลิงก์ใหม่ให้ลูกค้าอีกครั้ง'), style: theme.textTheme.bodyMedium),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          NxConfirmButtons(
            confirmKey: const ValueKey('regen-link-confirm'),
            confirmLabel: 'สร้างลิงก์ใหม่',
            icon: NxI.arrowsClockwise,
            color: amber,
            onConfirm: () => Navigator.pop(ctx, true),
          ),
        ],
      );
    }),
  );
  return ok == true;
}

/// The signing-link card of the job summary: status, the link itself
/// (short chip), copy / share / open / QR, and a confirmed regenerate.
/// [embedded]: a block inside the ลายเซ็น section; otherwise its own card.
class JobSignLinkCard extends StatefulWidget {
  const JobSignLinkCard({
    super.key,
    required this.jobId,
    required this.row,
    required this.overview,
    this.canEdit = true,
    this.onChanged,
    this.embedded = true,
  });

  final String jobId;
  final Map<String, dynamic> row;
  final Map<String, dynamic> overview;
  final bool canEdit;
  final VoidCallback? onChanged;
  final bool embedded;

  @override
  State<JobSignLinkCard> createState() => _JobSignLinkCardState();
}

class _JobSignLinkCardState extends State<JobSignLinkCard> {
  /// Token made in this session (shown until the reloaded row carries it).
  String? _token;
  String? _pdfPath;
  bool _busy = false;

  String get _rowToken => '${widget.row['public_token'] ?? widget.overview['public_token'] ?? ''}'.trim();
  String get _tokenNow => (_token ?? '').isNotEmpty ? _token! : _rowToken;

  @override
  void didUpdateWidget(JobSignLinkCard old) {
    super.didUpdateWidget(old);
    // The reloaded job row has caught up with the token made here.
    if (_token != null && _rowToken == _token) _token = null;
    if (old.jobId != widget.jobId) {
      _token = null;
      _pdfPath = null;
    }
  }

  String _url(String token) {
    final api = context.read<AppConfig>().apiClient;
    return api.absoluteUrl('/public/job/$token');
  }

  String _pdf(String token) {
    final api = context.read<AppConfig>().apiClient;
    return api.absoluteUrl(_pdfPath ?? '/api/public/field-service/jobs/public/$token/birt-pdf');
  }

  String get _shareText {
    final no = '${widget.row['job_no'] ?? ''}'.trim();
    final head = [if (no.isNotEmpty) '${tr('ใบสั่งงาน')} $no', tr('ลิงก์สำหรับลงนาม')].join(' · ');
    return '$head\n${_url(_tokenNow)}';
  }

  Future<void> _create({bool regenerate = false}) async {
    if (_busy) return;
    if (regenerate && !await confirmRegeneratePublicLink(context)) return;
    if (!mounted) return;
    final api = context.read<AppConfig>().apiClient;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      final r = await api.jobPublicLink(widget.jobId);
      var token = '${r['token'] ?? ''}'.trim();
      if (token.isEmpty) {
        // Older servers: only the path.
        final m = RegExp(r'/public/job/([A-Za-z0-9]+)').firstMatch('${r['path'] ?? ''}');
        token = m?.group(1) ?? '';
      }
      if (token.isEmpty) throw StateError('no token');
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _token = token;
        _pdfPath = r['pdf_path']?.toString();
      });
      messenger?.showSnackBar(SnackBar(content: Text(tr(regenerate ? 'สร้างลิงก์ใหม่แล้ว — ลิงก์เดิมใช้ไม่ได้แล้ว' : 'สร้างลิงก์แล้ว'))));
      widget.onChanged?.call();
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e is StateError ? tr('สร้างลิงก์ไม่สำเร็จ') : tr(journeyErrorText(e)))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final token = _tokenNow;
    final status = jobSignLinkStatus(widget.row, widget.overview, token: token);
    final color = jobSignLinkStatusColor(status, cs);
    final pill = Container(
      key: const ValueKey('job-link-status'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(99)),
      child: Text(jobSignLinkStatusLabel(status), style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (token.isEmpty) ...[
          Text(tr('ลูกค้าเปิดดูใบงาน รับทราบ และลงนามเองได้ ไม่ต้องล็อกอิน'),
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const ValueKey('job-public-link'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            onPressed: _busy ? null : () => _create(),
            icon: _busy
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(NxI.link, size: 18),
            label: Text(tr('สร้างลิงก์')),
          ),
        ] else ...[
          _linkChip(context, token),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _linkButton(const ValueKey('job-link-copy'), NxI.copySimple, 'คัดลอก', () => _copy(context, _url(token)), primary: true)),
            const SizedBox(width: 6),
            Expanded(child: _linkButton(const ValueKey('job-link-share'), NxI.shareNetwork, 'แชร์', () => sharePublicLink(_shareText))),
            const SizedBox(width: 6),
            Expanded(child: _linkButton(const ValueKey('job-link-open'), NxI.arrowSquareOut, 'เปิด', () => openPublicLink(context, _url(token)))),
            const SizedBox(width: 6),
            Tooltip(
              message: tr('QR สำหรับสแกน'),
              child: OutlinedButton(
                key: const ValueKey('job-link-qr'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(46, 40), padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                onPressed: () => showPublicLinkSheet(context, _url(token), pdf: _pdf(token), shareText: _shareText),
                child: const Icon(NxI.qrCode, size: 18),
              ),
            ),
          ]),
          if (widget.canEdit && status != 'signed')
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('job-link-regenerate'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: cs.onSurfaceVariant, padding: const EdgeInsets.symmetric(horizontal: 4)),
                onPressed: _busy ? null : () => _create(regenerate: true),
                icon: const Icon(NxI.arrowsClockwise, size: 15),
                label: Text(tr('สร้างลิงก์ใหม่'), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ),
        ],
      ],
    );
    if (!widget.embedded) {
      return JourneySection(key: const ValueKey('job-sign-link'), title: tr('ลิงก์สำหรับลงนาม'), icon: NxI.link, trailing: pill, child: body);
    }
    return Container(
      key: const ValueKey('job-sign-link'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: theme.brightness == Brightness.dark ? 0.35 : 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(NxI.link, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(tr('ลิงก์สำหรับลงนาม'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800))),
            Flexible(child: pill),
          ]),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }

  Widget _linkChip(BuildContext context, String token) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final url = _url(token);
    return Material(
      color: cs.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const ValueKey('job-link-url'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _copy(context, url),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(children: [
            Icon(NxI.link, size: 15, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                shortPublicLink(url),
                key: const ValueKey('job-link-short'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
              ),
            ),
            Icon(NxI.copySimple, size: 14, color: cs.primary.withValues(alpha: 0.7)),
          ]),
        ),
      ),
    );
  }

}

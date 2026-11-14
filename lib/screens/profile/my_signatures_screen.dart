import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/settings_tiles.dart';
import '../journey/job_report_signatures.dart' show JobSignPage, JobSignResult;
import 'profile_ui.dart';

/// Opens the full-screen, rotatable signing page (the same one Job detail's
/// summary uses) and returns the PNG, or null when cancelled.
typedef SignaturePadLauncher = Future<List<int>?> Function(BuildContext context, String title);

Future<List<int>?> _openJobSignPage(BuildContext context, String title) async {
  final r = await Navigator.of(context, rootNavigator: true).push<JobSignResult>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => JobSignPage(title: title, subtitle: tr('ลายเซ็นของฉัน'), showName: false)),
  );
  return r?.png;
}

/// "จัดการลายเซ็น" — my TH / EN signature shown on quotations and documents
/// (web and app read the same `/api/me/signatures`). "เซ็นใหม่" opens the
/// Job signing page; the PNG goes to `POST /api/uploads/signature` and its
/// path to `PUT /api/me/signatures`. Clear / replace ask first.
class MySignaturesScreen extends StatefulWidget {
  const MySignaturesScreen({super.key, this.padLauncher});

  /// Tests replace the signing page.
  final SignaturePadLauncher? padLauncher;

  @override
  State<MySignaturesScreen> createState() => _MySignaturesScreenState();
}

class _MySignaturesScreenState extends State<MySignaturesScreen> {
  Map<String, dynamic>? _data;
  Object? _error;
  String? _busySlot;

  ApiClient get _api => context.read<AppConfig>().apiClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _api.getMySignatures();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _path(String slot) {
    final v = '${_data?['upload_signature_$slot'] ?? ''}'.trim();
    return v == 'null' ? '' : v;
  }

  String? _url(String slot) {
    if (_path(slot).isEmpty) return null;
    final u = _data?[slot == 'th' ? 'signatureUrlTh' : 'signatureUrlEn']?.toString();
    return u == null || u.isEmpty ? null : _api.absoluteUrl(u);
  }

  String _slotName(String slot) => slot == 'th' ? 'ภาษาไทย' : 'ภาษาอังกฤษ';

  Future<void> _save(String slot, List<int> bytes, String filename) async {
    setState(() => _busySlot = slot);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await _api.uploadSignatureImage(bytes, filename);
      await _api.saveMySignatures(th: slot == 'th' ? path : null, en: slot == 'en' ? path : null);
      await _load();
      HapticFeedback.mediumImpact();
      messenger.showSnackBar(SnackBar(content: Text(tr('บันทึกลายเซ็นแล้ว'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    } finally {
      if (mounted) setState(() => _busySlot = null);
    }
  }

  Future<bool> _confirmReplace(String slot) async {
    if (_path(slot).isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('sig-replace-dialog'),
        title: Text(tr('แทนที่ลายเซ็นเดิม?')),
        content: Text(tr('ลายเซ็น${_slotName(slot)}ที่บันทึกไว้จะถูกแทนที่ เอกสารใหม่จะใช้ลายเซ็นใหม่')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(key: const ValueKey('sig-replace-ok'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('แทนที่'))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _draw(String slot) async {
    if (!await _confirmReplace(slot) || !mounted) return;
    final launch = widget.padLauncher ?? _openJobSignPage;
    final png = await launch(context, tr('ลายเซ็น${_slotName(slot)}'));
    if (png != null && png.isNotEmpty && mounted) await _save(slot, png, 'signature_$slot.png');
  }

  Future<void> _pick(String slot) async {
    if (!await _confirmReplace(slot) || !mounted) return;
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 90);
    if (x == null || !mounted) return;
    await _save(slot, await x.readAsBytes(), x.name);
  }

  Future<void> _clear(String slot) async {
    final ok = await showDeleteConfirm(
      context,
      name: tr('ลายเซ็น${_slotName(slot)}'),
      loses: const ['ลายเซ็นนี้บนเอกสารที่ออกใหม่ (เอกสารเดิมไม่เปลี่ยน)'],
      note: null,
    );
    if (!ok || !mounted) return;
    setState(() => _busySlot = slot);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _api.saveMySignatures(clearTh: slot == 'th', clearEn: slot == 'en');
      await _load();
      messenger.showSnackBar(SnackBar(content: Text(tr('ลบลายเซ็นแล้ว'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    } finally {
      if (mounted) setState(() => _busySlot = null);
    }
  }

  /// Use the other language's signature for this slot too.
  Future<void> _copyFrom(String slot, String from) async {
    setState(() => _busySlot = slot);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final p = _path(from);
      await _api.saveMySignatures(th: slot == 'th' ? p : null, en: slot == 'en' ? p : null);
      await _load();
      messenger.showSnackBar(SnackBar(content: Text(tr('บันทึกลายเซ็นแล้ว'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    } finally {
      if (mounted) setState(() => _busySlot = null);
    }
  }

  Widget _slot(String slot, String title, String subtitle) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final url = _url(slot);
    final busy = _busySlot == slot;
    final other = slot == 'th' ? 'en' : 'th';
    final canCopy = url == null && _path(other).isNotEmpty;
    const green = Color(0xFF16A34A);
    return Container(
      key: ValueKey('sig-card-$slot'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(tr(subtitle), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            if (busy)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: (url == null ? cs.onSurfaceVariant : green).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  tr(url == null ? 'ยังไม่มี' : 'บันทึกแล้ว'),
                  key: ValueKey('sig-status-$slot'),
                  style: theme.textTheme.labelSmall?.copyWith(color: url == null ? cs.onSurfaceVariant : green, fontWeight: FontWeight.w800),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          // The paper: white in both themes, like the printed document.
          AspectRatio(
            aspectRatio: 8 / 3,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('sig-preview-$slot'),
                onTap: _busySlot != null ? null : () => _draw(slot),
                child: Stack(children: [
                  Positioned.fill(
                    child: url == null
                        ? Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(NxI.signature, color: Color(0xFF94A3B8), size: 30),
                              const SizedBox(height: 4),
                              Text(tr('แตะเพื่อเซ็น'), style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B))),
                            ]),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(10),
                            child: Image.network(url, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Center(child: Icon(NxI.image, color: Color(0xFF94A3B8)))),
                          ),
                  ),
                  const Positioned(left: 22, right: 22, bottom: 18, child: Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0))),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                key: ValueKey('sig-draw-$slot'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: _busySlot != null ? null : () => _draw(slot),
                icon: const Icon(NxI.penLine, size: 18),
                label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('เซ็นใหม่'), maxLines: 1)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: ValueKey('sig-pick-$slot'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: _busySlot != null ? null : () => _pick(slot),
                icon: const Icon(NxI.image, size: 18),
                label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('เลือกรูป'), maxLines: 1)),
              ),
            ),
            if (url != null) ...[
              const SizedBox(width: 4),
              IconButton(
                key: ValueKey('sig-clear-$slot'),
                tooltip: tr('ลบลายเซ็น'),
                onPressed: _busySlot != null ? null : () => _clear(slot),
                icon: Icon(NxI.trash, color: kNxDangerRed.withValues(alpha: 0.9)),
              ),
            ],
          ]),
          if (canCopy)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey('sig-copy-$slot'),
                onPressed: _busySlot != null ? null : () => _copyFrom(slot, other),
                icon: const Icon(NxI.copySimple, size: 16),
                label: Text(tr('ใช้ลายเซ็น${_slotName(other)}')),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final List<Widget> children;
    if (_data == null) {
      children = [
        if (_error == null)
          const NxSkeletonSettings(key: ValueKey('signatures-skeleton'), groups: [2], trailing: NxSkelTrailing.chevron, padded: false)
        else
          NxSoftNote(
            icon: NxI.warningCircle,
            color: cs.error,
            text: formatApiError(_error!),
            action: TextButton(onPressed: _load, child: Text(tr('ลองใหม่'))),
          ),
      ];
    } else {
      children = [
        Text(tr('ใช้บนใบเสนอราคาและเอกสารที่ออกจากระบบ ทั้งในแอปและบนเว็บ'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 14),
        SettingsAppear(index: 0, child: _slot('th', 'ลายเซ็น (ภาษาไทย)', 'เอกสารภาษาไทย')),
        const SizedBox(height: 12),
        SettingsAppear(index: 1, child: _slot('en', 'Signature (English)', 'เอกสารภาษาอังกฤษ')),
        const SizedBox(height: 14),
        const NxSoftNote(
          icon: NxI.deviceMobile,
          text: 'หน้าเซ็นหมุนเป็นแนวนอนได้ เพื่อให้มีพื้นที่เซ็นกว้างขึ้น',
        ),
      ];
    }
    return ProfileSubPage(title: 'จัดการลายเซ็น', maxWidth: 640, onRefresh: _load, children: children);
  }
}

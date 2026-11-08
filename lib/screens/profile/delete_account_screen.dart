import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'otp_proof.dart';

/// "ลบบัญชี" — required by App Store and Google Play.
///
/// 1) explain what is removed and what stays with the business,
/// 2) prove it is me with an OTP (same as change password),
/// 3) type the confirm word → `POST /api/me/delete-account` with the OTP
///    token → forget the account on this device and sign this Space out.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  /// Typed to confirm (Thai, or English for the English UI).
  static const confirmWords = {'ลบบัญชี', 'DELETE'};

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _otp = GlobalKey<OtpProofSectionState>();
  final _typed = TextEditingController();
  bool _understood = false;
  bool _sent = false;
  bool _busy = false;
  String? _error;
  bool _webOnly = false;

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _ready =>
      _understood && _sent && DeleteAccountScreen.confirmWords.contains(_typed.text.trim()) && !_busy;

  String get _webPage => '${context.read<AppConfig>().apiBaseUrl.replaceAll(RegExp(r'/+$'), '')}/account-deletion';

  Future<void> _delete() async {
    final config = context.read<AppConfig>();
    final api = config.apiClient;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _webOnly = false;
    });
    try {
      final token = await _otp.currentState!.proveToken();
      final done = await api.deleteMyAccount(token);
      if (!done) {
        setState(() {
          _webOnly = true;
          _error = 'เซิร์ฟเวอร์นี้ยังไม่รองรับการลบบัญชีในแอป ขอลบได้จากหน้าเว็บ';
        });
        return;
      }
      HapticFeedback.heavyImpact();
      messenger.showSnackBar(SnackBar(content: Text(tr('ลบบัญชีแล้ว'))));
      nav.popUntil((r) => r.isFirst);
      await config.signOutDeletedAccount();
    } catch (e) {
      if (mounted) setState(() => _error = e is OtpRefused ? e.message : formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget point(IconData icon, Color color, String title, String body) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(tr(body), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
        );

    return NxScrollScaffold(
      header: const NxAppHeader(title: 'ลบบัญชี'),
      body: ListView(
        padding: NxBreakpoint.of(context).scrollPadding(context),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(NxI.warningCircle, color: cs.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('ลบบัญชีแล้วกู้คืนเองไม่ได้'),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.error)),
                ),
              ]),
              point(NxI.trash, cs.error, 'สิ่งที่ถูกลบ', 'บัญชีผู้ใช้และการเข้าสู่ระบบทุกเครื่อง ข้อมูลส่วนตัวในโปรไฟล์ และการรับแจ้งเตือน'),
              point(NxI.shieldCheck, cs.primary, 'สิ่งที่ยังอยู่กับธุรกิจ',
                  'ข้อมูลงานที่บันทึกไว้ (ลูกค้า ใบเสนอราคา กิจกรรม ไฟล์) เป็นของธุรกิจ และประวัติการใช้งานเพื่อความปลอดภัย'),
              point(NxI.signOut, cs.onSurfaceVariant, 'ทุก Space ของบัญชีนี้', 'ถ้าใช้บัญชีเดียวกันหลายธุรกิจ จะเข้าไม่ได้ทั้งหมด'),
            ]),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const ValueKey('del-understand'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _understood,
            onChanged: _busy ? null : (v) => setState(() => _understood = v ?? false),
            title: Text(tr('ฉันเข้าใจและต้องการลบบัญชีนี้')),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: !_understood
                ? const SizedBox(width: double.infinity)
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SizedBox(height: 8),
                    OtpProofSection(
                      key: _otp,
                      keyPrefix: 'del',
                      codeTitle: '2. ใส่รหัส OTP',
                      enabled: !_busy,
                      onSent: () => setState(() => _sent = true),
                      onError: (m) => setState(() => _error = m),
                    ),
                    if (_sent) ...[
                      const SizedBox(height: 18),
                      Text(tr('3. พิมพ์ "ลบบัญชี" เพื่อยืนยัน'),
                          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('del-type'),
                        controller: _typed,
                        enabled: !_busy,
                        decoration: InputDecoration(
                          hintText: L10n.isEn ? 'DELETE' : 'ลบบัญชี',
                          filled: true,
                          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        key: const ValueKey('del-submit'),
                        onPressed: _ready ? _delete : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: cs.error,
                          foregroundColor: cs.onError,
                        ),
                        icon: _busy
                            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onError))
                            : const Icon(NxI.trash, size: 18),
                        label: Text(tr('ลบบัญชีถาวร')),
                      ),
                    ],
                  ]),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(tr(_error!), key: const ValueKey('del-error'), style: TextStyle(color: cs.error)),
            ),
          if (_webOnly)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('del-web'),
                onPressed: () => launchUrl(Uri.parse(_webPage), mode: LaunchMode.externalApplication),
                icon: const Icon(NxI.arrowSquareOut, size: 18),
                label: Text(tr('เปิดหน้าขอลบบัญชี')),
              ),
            ),
        ],
      ),
    );
  }
}

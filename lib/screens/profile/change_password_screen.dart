import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'otp_proof.dart';

/// "เปลี่ยนรหัสผ่าน" by one-time code instead of the old password:
/// 1) pick email or SMS (the account's own address / mobile),
/// 2) enter the code and the new password.
///
/// Uses NEXTX's existing OTP sign-in endpoints to prove it is the same user
/// ([OtpProofSection]), then `PUT /api/me/password` with that proof.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _otp = GlobalKey<OtpProofSectionState>();
  bool _sent = false;
  bool _busy = false;
  String? _error;
  bool _show = false;
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  String? _check() {
    if (!(_otp.currentState?.codeLooksValid ?? false)) return 'กรอกรหัส OTP ให้ครบ';
    if (_pw.text.length < 6) return 'รหัสผ่านใหม่อย่างน้อย 6 ตัวอักษร';
    if (_pw.text != _pw2.text) return 'รหัสไม่ตรงกัน';
    return null;
  }

  Future<void> _submit() async {
    final bad = _check();
    if (bad != null) {
      HapticFeedback.heavyImpact();
      return setState(() => _error = bad);
    }
    final api = context.read<AppConfig>().apiClient;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await _otp.currentState!.proveToken();
      await api.changePasswordWithOtpToken(token, _pw.text);
      HapticFeedback.mediumImpact();
      messenger.showSnackBar(SnackBar(content: Text(tr('เปลี่ยนรหัสผ่านแล้ว'))));
      nav.pop(true);
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

    InputDecoration deco(String label, IconData icon, {Widget? suffix}) => InputDecoration(
          labelText: tr(label),
          prefixIcon: Icon(icon, size: 20),
          suffixIcon: suffix,
          filled: true,
          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        );

    return NxScrollScaffold(
      header: const NxAppHeader(title: 'เปลี่ยนรหัสผ่าน'),
      body: ListView(
        padding: NxBreakpoint.of(context).scrollPadding(context),
        children: [
          Text(
            tr('ยืนยันตัวตนด้วยรหัส OTP แทนรหัสผ่านเดิม'),
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          OtpProofSection(
            key: _otp,
            keyPrefix: 'pw',
            codeTitle: '2. ใส่รหัสและรหัสผ่านใหม่',
            enabled: !_busy,
            onSent: () => setState(() => _sent = true),
            onError: (m) => setState(() => _error = m),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: !_sent
                ? const SizedBox(width: double.infinity)
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SizedBox(height: 10),
                    TextField(
                      key: const ValueKey('pw-new'),
                      controller: _pw,
                      obscureText: !_show,
                      decoration: deco(
                        'รหัสผ่านใหม่',
                        NxI.password,
                        suffix: IconButton(
                          icon: Icon(_show ? NxI.eyeSlash : NxI.eye, size: 20),
                          onPressed: () => setState(() => _show = !_show),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const ValueKey('pw-confirm'),
                      controller: _pw2,
                      obscureText: !_show,
                      decoration: deco('ยืนยันรหัสผ่านใหม่', NxI.password),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const ValueKey('pw-submit'),
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(tr('เปลี่ยนรหัสผ่าน')),
                    ),
                  ]),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(tr(_error!), key: const ValueKey('pw-error'), style: TextStyle(color: cs.error)),
            ),
        ],
      ),
    );
  }
}

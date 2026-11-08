import 'dart:async';

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

/// "เปลี่ยนรหัสผ่าน" by one-time code instead of the old password:
/// 1) pick email or SMS (the account's own address / mobile),
/// 2) enter the code and the new password.
///
/// Uses NEXTX's existing OTP sign-in endpoints to prove it is the same user,
/// then `PUT /api/me/password` with that proof (no backend change).
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

enum _Channel { email, sms }

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  _Channel _channel = _Channel.email;
  String? _phone;
  bool _sent = false;
  bool _busy = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;
  bool _show = false;
  final _code = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();

  String get _email => context.read<AppConfig>().session.email ?? '';

  @override
  void initState() {
    super.initState();
    context.read<AppConfig>().apiClient.getMyProfile().then((p) {
      final phone = (p['phone_mobile'] ?? '').toString().trim();
      if (mounted && phone.isNotEmpty) setState(() => _phone = phone);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  static String maskEmail(String e) {
    final at = e.indexOf('@');
    if (at <= 1) return e;
    final name = e.substring(0, at);
    return '${name.substring(0, name.length < 3 ? 1 : 2)}${'•' * (name.length - (name.length < 3 ? 1 : 2)).clamp(1, 6)}${e.substring(at)}';
  }

  static String maskPhone(String p) {
    final d = p.replaceAll(RegExp(r'\D'), '');
    if (d.length < 7) return p;
    return '${d.substring(0, 3)}-•••-${d.substring(d.length - 4)}';
  }

  String get _target => _channel == _Channel.email ? maskEmail(_email) : maskPhone(_phone ?? '');

  Future<void> _send() async {
    final api = context.read<AppConfig>().apiClient;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_channel == _Channel.email) {
        await api.requestEmailOtp(_email);
      } else {
        await api.requestSmsOtp(_phone!);
      }
      HapticFeedback.lightImpact();
      _timer?.cancel();
      setState(() {
        _sent = true;
        _cooldown = 60;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _cooldown <= 1) {
          t.cancel();
          if (mounted) setState(() => _cooldown = 0);
          return;
        }
        setState(() => _cooldown--);
      });
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _check() {
    if (!RegExp(r'^\d{4,8}$').hasMatch(_code.text.trim())) return 'กรอกรหัส OTP ให้ครบ';
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
    final config = context.read<AppConfig>();
    final api = config.apiClient;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = _code.text.trim();
      var proof = _channel == _Channel.email
          ? await api.verifyEmailOtp(email: _email, code: code)
          : await api.verifySmsOtp(phone: _phone!, code: code);
      // First OTP use on this account: NEXTX asks to link the method (it is
      // the user's own email / mobile, proven by the code) → confirm it.
      if (proof['needLinkConfirm'] == true && (proof['intentToken']?.toString() ?? '').isNotEmpty) {
        proof = await api.linkConfirm(proof['intentToken'].toString());
      }
      final token = proof['token']?.toString() ?? '';
      final user = proof['user'];
      final uid = user is Map ? user['id']?.toString() : null;
      if (proof['needLinkConfirm'] == true || token.isEmpty) {
        throw const _Refused('ยืนยันรหัสไม่สำเร็จ ลองขอรหัสใหม่');
      }
      if (uid != null && uid != config.session.userId) {
        throw const _Refused('รหัสนี้เป็นของบัญชีอื่น');
      }
      await api.changePasswordWithOtpToken(token, _pw.text);
      HapticFeedback.mediumImpact();
      messenger.showSnackBar(SnackBar(content: Text(tr('เปลี่ยนรหัสผ่านแล้ว'))));
      nav.pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e is _Refused ? e.message : formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasPhone = (_phone ?? '').isNotEmpty;

    Widget channel(_Channel c, IconData icon, String title, String sub, {bool enabled = true}) {
      final sel = _channel == c;
      return Expanded(
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: InkWell(
            key: ValueKey('pw-channel-${c.name}'),
            borderRadius: BorderRadius.circular(18),
            onTap: !enabled || _busy
                ? null
                : () => setState(() {
                      _channel = c;
                      _sent = false;
                      _error = null;
                      _code.clear();
                    }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: sel ? cs.primary.withValues(alpha: 0.10) : cs.surfaceContainerHighest.withValues(alpha: 0.6),
                border: Border.all(color: sel ? cs.primary : Colors.transparent, width: 1.5),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(icon, size: 20, color: sel ? cs.primary : cs.onSurfaceVariant),
                  const Spacer(),
                  if (sel) Icon(NxI.checkCircle, size: 18, color: cs.primary),
                ]),
                const SizedBox(height: 8),
                Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
        ),
      );
    }

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
          Text(tr('1. รับรหัสทาง'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(children: [
            channel(_Channel.email, NxI.envelope, 'อีเมล', maskEmail(_email), enabled: _email.isNotEmpty),
            const SizedBox(width: 10),
            channel(_Channel.sms, NxI.phone, 'SMS', hasPhone ? maskPhone(_phone!) : tr('ยังไม่มีเบอร์มือถือ'), enabled: hasPhone),
          ]),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            key: const ValueKey('pw-send'),
            onPressed: _busy || _cooldown > 0 ? null : _send,
            icon: const Icon(NxI.send, size: 18),
            label: Text(_cooldown > 0
                ? tr('ส่งอีกครั้งใน $_cooldown วินาที')
                : (_sent ? tr('ส่งรหัสอีกครั้ง') : tr('ส่งรหัส OTP'))),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: !_sent
                ? const SizedBox(width: double.infinity)
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SizedBox(height: 18),
                    Text(tr('2. ใส่รหัสและรหัสผ่านใหม่'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(tr('ส่งรหัสไปที่ $_target แล้ว'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    TextField(
                      key: const ValueKey('pw-code'),
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 6, fontWeight: FontWeight.w800),
                      decoration: deco('รหัส OTP', NxI.shieldCheck).copyWith(counterText: ''),
                    ),
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

class _Refused implements Exception {
  const _Refused(this.message);
  final String message;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_icons.dart';

/// "Prove it is me" with a one-time code to the account's own email or mobile.
///
/// Shared by change password and delete account. Uses NEXTX's existing OTP
/// sign-in endpoints: verify the code (linking the method on first use),
/// and check that the session it returns is the signed-in user. The parent
/// reads the result with [OtpProofSectionState.proveToken].
enum OtpChannel { email, sms }

class OtpRefused implements Exception {
  const OtpRefused(this.message);
  final String message;
  @override
  String toString() => message;
}

String maskEmail(String e) {
  final at = e.indexOf('@');
  if (at <= 1) return e;
  final name = e.substring(0, at);
  final keep = name.length < 3 ? 1 : 2;
  return '${name.substring(0, keep)}${'•' * (name.length - keep).clamp(1, 6)}${e.substring(at)}';
}

String maskPhone(String p) {
  final d = p.replaceAll(RegExp(r'\D'), '');
  if (d.length < 7) return p;
  return '${d.substring(0, 3)}-•••-${d.substring(d.length - 4)}';
}

class OtpProofSection extends StatefulWidget {
  const OtpProofSection({
    super.key,
    required this.keyPrefix,
    required this.codeTitle,
    this.onSent,
    this.onError,
    this.enabled = true,
  });

  /// Widget keys are `<prefix>-channel-email`, `<prefix>-send`, `<prefix>-code`.
  final String keyPrefix;

  /// Heading shown above the code field once a code was sent.
  final String codeTitle;
  final VoidCallback? onSent;
  final ValueChanged<String?>? onError;
  final bool enabled;

  @override
  State<OtpProofSection> createState() => OtpProofSectionState();
}

class OtpProofSectionState extends State<OtpProofSection> {
  OtpChannel _channel = OtpChannel.email;
  String? _phone;
  bool _sent = false;
  bool _busy = false;
  int _cooldown = 0;
  Timer? _timer;
  final _code = TextEditingController();

  bool get sent => _sent;
  String get code => _code.text.trim();
  bool get codeLooksValid => RegExp(r'^\d{4,8}$').hasMatch(code);

  String get _email => context.read<AppConfig>().session.email ?? '';
  String get _target => _channel == OtpChannel.email ? maskEmail(_email) : maskPhone(_phone ?? '');

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
    super.dispose();
  }

  Future<void> _send() async {
    final api = context.read<AppConfig>().apiClient;
    setState(() => _busy = true);
    widget.onError?.call(null);
    try {
      if (_channel == OtpChannel.email) {
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
      widget.onSent?.call();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _cooldown <= 1) {
          t.cancel();
          if (mounted) setState(() => _cooldown = 0);
          return;
        }
        setState(() => _cooldown--);
      });
    } catch (e) {
      widget.onError?.call(formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Verifies the code and returns a fresh session token for the signed-in
  /// user. Throws [OtpRefused] with a readable message when it cannot.
  Future<String> proveToken() async {
    if (!codeLooksValid) throw const OtpRefused('กรอกรหัส OTP ให้ครบ');
    final config = context.read<AppConfig>();
    final api = config.apiClient;
    var proof = _channel == OtpChannel.email
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
      throw const OtpRefused('ยืนยันรหัสไม่สำเร็จ ลองขอรหัสใหม่');
    }
    if (uid != null && uid != config.session.userId) {
      throw const OtpRefused('รหัสนี้เป็นของบัญชีอื่น');
    }
    return token;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasPhone = (_phone ?? '').isNotEmpty;
    final p = widget.keyPrefix;
    final enabled = widget.enabled && !_busy;

    Widget channel(OtpChannel c, IconData icon, String title, String sub, {bool on = true}) {
      final sel = _channel == c;
      return Expanded(
        child: Opacity(
          opacity: on ? 1 : 0.45,
          child: InkWell(
            key: ValueKey('$p-channel-${c.name}'),
            borderRadius: BorderRadius.circular(18),
            onTap: !on || !enabled
                ? null
                : () {
                    setState(() {
                      _channel = c;
                      _sent = false;
                      _code.clear();
                    });
                    widget.onError?.call(null);
                  },
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

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('1. รับรหัสทาง'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Row(children: [
        channel(OtpChannel.email, NxI.envelope, 'อีเมล', maskEmail(_email), on: _email.isNotEmpty),
        const SizedBox(width: 10),
        channel(OtpChannel.sms, NxI.phone, 'SMS', hasPhone ? maskPhone(_phone!) : tr('ยังไม่มีเบอร์มือถือ'), on: hasPhone),
      ]),
      const SizedBox(height: 12),
      FilledButton.tonalIcon(
        key: ValueKey('$p-send'),
        onPressed: !enabled || _cooldown > 0 ? null : _send,
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
                Text(tr(widget.codeTitle), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(tr('ส่งรหัสไปที่ $_target แล้ว'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 10),
                TextField(
                  key: ValueKey('$p-code'),
                  controller: _code,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 6, fontWeight: FontWeight.w800),
                  decoration: InputDecoration(
                    labelText: tr('รหัส OTP'),
                    prefixIcon: const Icon(NxI.shieldCheck, size: 20),
                    counterText: '',
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
              ]),
      ),
    ]);
  }
}

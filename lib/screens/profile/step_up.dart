import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/nx_icons.dart';
import 'profile_ui.dart';

/// What `GET /api/me/verify/methods` offers this user.
class VerifyMethods {
  const VerifyMethods({this.email = false, this.emailMasked, this.sms = false, this.smsMasked, this.password = false, this.reasons = const {}});

  factory VerifyMethods.fromJson(Map<String, dynamic> j) {
    bool on(Object? m) => m is Map && (m['available'] == true || m['available'] == 1);
    String? masked(Object? m) {
      final v = m is Map ? '${m['masked'] ?? ''}'.trim() : '';
      return v.isEmpty || v == 'null' ? null : v;
    }

    String? reason(Object? m) {
      final v = m is Map ? '${m['reason'] ?? ''}'.trim() : '';
      return v.isEmpty || v == 'null' ? null : v;
    }

    return VerifyMethods(
      reasons: {
        for (final c in ['email', 'sms', 'password'])
          if (reason(j[c]) case final r?) c: r,
      },
      email: on(j['email']),
      emailMasked: masked(j['email']),
      sms: on(j['sms']),
      smsMasked: masked(j['sms']),
      password: on(j['password']),
    );
  }

  final bool email;
  final String? emailMasked;
  final bool sms;
  final String? smsMasked;
  final bool password;

  /// Why a channel is off: `no_phone`, `no_email`, `not_configured`.
  final Map<String, String> reasons;

  /// Friendly Thai text for why [channel] cannot be used.
  String unavailableText(String channel) {
    switch (reasons[channel]) {
      case 'no_phone':
        return 'ยังไม่มีเบอร์มือถือที่ยืนยันแล้ว';
      case 'no_email':
        return 'บัญชีนี้ยังไม่มีอีเมล';
      case 'not_configured':
        return channel == 'sms' ? 'ระบบยังไม่ได้ตั้งค่าการส่ง SMS' : (channel == 'email' ? 'ระบบยังไม่ได้ตั้งค่าการส่งอีเมล' : 'ยังใช้วิธีนี้ไม่ได้');
    }
    return switch (channel) {
      'email' => 'บัญชีนี้ยังไม่มีอีเมล',
      'sms' => 'ยังไม่มีเบอร์มือถือที่ยืนยันแล้ว',
      _ => 'บัญชีนี้ยังไม่มีรหัสผ่าน',
    };
  }

  bool available(String channel) => switch (channel) {
        'email' => email,
        'sms' => sms,
        'password' => password,
        _ => false,
      };

  String? masked(String channel) => channel == 'email' ? emailMasked : (channel == 'sms' ? smsMasked : null);

  /// One-time-code channels this account can use (for "verify both").
  List<String> get codeChannels => [if (email) 'email', if (sms) 'sms'];
}

/// Thai title + icon of a verify channel.
(String, IconData) verifyChannelLabel(String channel) => switch (channel) {
      'email' => ('รหัส OTP ทางอีเมล', NxI.envelope),
      'sms' => ('รหัส OTP ทาง SMS', NxI.phone),
      _ => ('รหัสผ่านปัจจุบัน', NxI.keyRound),
    };

/// Friendly text for a refused step-up call.
String stepUpErrorText(Object e) {
  if (e is ApiEnvelopeException) {
    final code = e.errorCode.toUpperCase();
    if (e.statusCode == 429 || code.contains('RATE') || code.contains('TOO_MANY')) {
      return e.message.isNotEmpty ? e.message : 'ลองหลายครั้งเกินไป กรุณารอสักครู่แล้วลองใหม่';
    }
    if (code.contains('EXPIRED')) return 'รหัสหมดอายุแล้ว กรุณาขอรหัสใหม่';
    final left = int.tryParse('${e.details?['attempts_left'] ?? ''}');
    if (left != null) {
      final base = e.message.isNotEmpty ? e.message : 'รหัสไม่ถูกต้อง';
      return left > 0 ? '$base · ${tr('เหลือ $left ครั้ง')}' : '$base · ${tr('ขอรหัสใหม่')}';
    }
    if (code.contains('PASSWORD')) return e.message.isNotEmpty ? e.message : 'รหัสผ่านไม่ถูกต้อง';
    if (code.contains('INVALID') || code.contains('OTP') || code.contains('CODE')) {
      return e.message.isNotEmpty ? e.message : 'รหัสไม่ถูกต้อง ลองอีกครั้ง';
    }
    return e.message.isNotEmpty ? e.message : 'ยืนยันตัวตนไม่สำเร็จ';
  }
  return formatApiError(e);
}

/// Seconds to wait before asking again: `resend_after` / `retry_after` from
/// the reply or error details, else [fallback].
int resendSeconds(Map<String, dynamic>? m, {int fallback = 60}) {
  for (final k in ['resend_after', 'retry_after', 'cooldown']) {
    final v = num.tryParse('${m?[k] ?? ''}');
    if (v != null && v > 0) return v.round().clamp(1, 600);
  }
  return fallback;
}

/// One step-up proof: a code by email / SMS (`/api/me/verify/request` then
/// `/confirm`) or the current password (`/api/me/verify/password`). Calls
/// [onVerified] with the `verify_token`. Keys: `<prefix>-send`, `-code`,
/// `-confirm`, `-password`, `-verified`.
class StepUpVerifier extends StatefulWidget {
  const StepUpVerifier({
    super.key,
    required this.channel,
    required this.keyPrefix,
    required this.onVerified,
    this.masked,
    this.verified = false,
    this.enabled = true,
    this.autoSend = false,
    this.compact = false,
  });

  /// `email`, `sms` or `password`.
  final String channel;
  final String keyPrefix;
  final String? masked;
  final ValueChanged<String> onVerified;
  final bool verified;
  final bool enabled;

  /// Ask for the code as soon as it shows (one tap less).
  final bool autoSend;

  /// Card without its own title row (when the page already says what it is).
  final bool compact;

  @override
  State<StepUpVerifier> createState() => StepUpVerifierState();
}

class StepUpVerifierState extends State<StepUpVerifier> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  bool _showPw = false;
  int _cooldown = 0;
  String? _destination;
  String? _ref;
  String? _error;
  Timer? _timer;

  bool get _isPassword => widget.channel == 'password';

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
    _password.addListener(() => setState(() {}));
    if (widget.autoSend && !_isPassword && !widget.verified) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) send();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  void _startCooldown(int s) {
    _timer?.cancel();
    setState(() => _cooldown = s);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _cooldown <= 1) {
        t.cancel();
        if (mounted) setState(() => _cooldown = 0);
        return;
      }
      setState(() => _cooldown--);
    });
  }

  /// Requests a code (email / SMS).
  Future<void> send() async {
    if (_busy || _cooldown > 0) return;
    final api = context.read<AppConfig>().apiClient;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await api.requestVerifyCode(widget.channel);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _sent = true;
        final d = '${r['destination_masked'] ?? ''}'.trim();
        _destination = d.isEmpty || d == 'null' ? widget.masked : d;
        final ref = '${r['ref_code'] ?? ''}'.trim();
        _ref = ref.isEmpty || ref == 'null' ? null : ref;
        _code.clear();
      });
      _startCooldown(resendSeconds(r));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = stepUpErrorText(e));
      if (e is ApiEnvelopeException && e.statusCode == 429) _startCooldown(resendSeconds(e.details));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final api = context.read<AppConfig>().apiClient;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = _isPassword ? await api.verifyCurrentPassword(_password.text) : await api.confirmVerifyCode(widget.channel, _code.text.trim());
      final token = '${r['verify_token'] ?? ''}'.trim();
      if (token.isEmpty) throw ApiEnvelopeException(400, 'VERIFY_FAILED', tr('ยืนยันตัวตนไม่สำเร็จ'));
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _password.clear());
      widget.onVerified(token);
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _error = stepUpErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Back to "not verified" (the proof expired or the server asked again).
  void reset() {
    _timer?.cancel();
    setState(() {
      _sent = false;
      _cooldown = 0;
      _code.clear();
      _password.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = widget.keyPrefix;
    final (title, icon) = verifyChannelLabel(widget.channel);
    const green = Color(0xFF16A34A);
    final enabled = widget.enabled && !_busy;
    final codeOk = RegExp(r'^\d{4,8}$').hasMatch(_code.text.trim());

    Widget body;
    if (widget.verified) {
      body = Row(key: ValueKey('$p-verified'), children: [
        const Icon(NxI.checkCircle, color: green, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(tr('ยืนยันแล้ว'), style: theme.textTheme.titleSmall?.copyWith(color: green, fontWeight: FontWeight.w700))),
      ]);
    } else if (_isPassword) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          key: ValueKey('$p-password'),
          controller: _password,
          enabled: widget.enabled,
          obscureText: !_showPw,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _password.text.isEmpty || !enabled ? null : _confirm(),
          decoration: profileInput(
            context,
            'รหัสผ่านปัจจุบัน',
            icon: NxI.keyRound,
            suffix: IconButton(
              tooltip: tr(_showPw ? 'ซ่อนรหัสผ่าน' : 'แสดงรหัสผ่าน'),
              icon: Icon(_showPw ? NxI.eyeSlash : NxI.eye, size: 20),
              onPressed: () => setState(() => _showPw = !_showPw),
            ),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          key: ValueKey('$p-confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          onPressed: _password.text.isEmpty || !enabled ? null : _confirm,
          child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('ยืนยัน')),
        ),
      ]);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!_sent)
          FilledButton.tonalIcon(
            key: ValueKey('$p-send'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            onPressed: !enabled || _cooldown > 0 ? null : send,
            icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.send, size: 18),
            label: Text(_cooldown > 0 ? tr('ขอรหัสใหม่ได้ใน $_cooldown วินาที') : tr('ส่งรหัส OTP')),
          )
        else ...[
          Text(
            tr('ส่งรหัสไปที่ ${_destination ?? widget.masked ?? ''} แล้ว'),
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (_ref != null)
            Text('Ref: $_ref', key: ValueKey('$p-ref'), style: theme.textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            key: ValueKey('$p-code'),
            controller: _code,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => codeOk && enabled ? _confirm() : null,
            style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 6, fontWeight: FontWeight.w800),
            decoration: profileInput(context, 'รหัส OTP', icon: NxI.shieldCheck).copyWith(counterText: ''),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextButton(
                key: ValueKey('$p-resend'),
                onPressed: !enabled || _cooldown > 0 ? null : send,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_cooldown > 0 ? tr('ขอรหัสใหม่ได้ใน $_cooldown วินาที') : tr('ส่งรหัสอีกครั้ง'), maxLines: 1),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: ValueKey('$p-confirm'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                onPressed: codeOk && enabled ? _confirm : null,
                child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('ยืนยัน')),
              ),
            ),
          ]),
        ],
      ]);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: widget.verified ? green.withValues(alpha: 0.08) : cs.surfaceContainerHighest.withValues(alpha: 0.7),
        border: Border.all(color: widget.verified ? green.withValues(alpha: 0.4) : Colors.transparent),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!widget.compact) ...[
          Row(children: [
            Icon(icon, size: 20, color: widget.verified ? green : cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if ((widget.masked ?? '').isNotEmpty)
                  Text(widget.masked!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
        ],
        body,
        if (_error != null) ProfileErrorText(_error!, key: ValueKey('$p-error')),
      ]),
    );
  }
}

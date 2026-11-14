import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../widgets/fields/nx_field_chrome.dart';
import '../../widgets/nx_icons.dart';
import 'profile_ui.dart';
import 'step_up.dart' show resendSeconds;

/// Digits of a phone number, `+66…` folded to `0…` (Thai mobile style).
String normalizePhone(String raw) {
  var d = raw.replaceAll(RegExp(r'[^\d+]'), '');
  if (d.startsWith('+66')) d = '0${d.substring(3)}';
  if (d.startsWith('66') && d.length == 11) d = '0${d.substring(2)}';
  return d.replaceAll('+', '');
}

/// Null when [raw] looks like a mobile number, else the Thai reason.
String? phoneProblem(String raw, {String? current}) {
  final d = normalizePhone(raw);
  if (d.isEmpty) return 'กรุณากรอกเบอร์มือถือใหม่';
  if (!RegExp(r'^0\d{8,9}$').hasMatch(d)) return 'เบอร์มือถือไม่ถูกต้อง (เช่น 0812345678)';
  if (current != null && normalizePhone(current) == d) return 'เป็นเบอร์เดิมอยู่แล้ว';
  return null;
}

/// `081-234-5678` for display.
String formatPhone(String raw) {
  final d = normalizePhone(raw);
  if (d.length == 10) return '${d.substring(0, 3)}-${d.substring(3, 6)}-${d.substring(6)}';
  if (d.length == 9) return '${d.substring(0, 2)}-${d.substring(2, 5)}-${d.substring(5)}';
  return raw;
}

/// Friendly text for the phone-bind OTP errors (NEXTX: 409 in use, 429 wait,
/// 401 wrong code / expired).
String phoneOtpErrorText(Object e) {
  if (e is ApiEnvelopeException) {
    final msg = e.message.trim();
    if (e.statusCode == 409 || msg.contains('ถูกใช้')) return 'เบอร์นี้ถูกใช้กับบัญชีอื่นแล้ว';
    if (e.statusCode == 429) return msg.isNotEmpty ? msg : 'กรุณารอสักครู่ก่อนขอรหัสใหม่';
    if (e.statusCode == 401 || e.errorCode.toUpperCase().contains('INVALID')) {
      return msg.isNotEmpty ? msg : 'รหัสยืนยันไม่ถูกต้อง';
    }
    return msg.isNotEmpty ? msg : 'ทำรายการไม่สำเร็จ';
  }
  return formatApiError(e);
}

/// "เปลี่ยนเบอร์โทรศัพท์": the current number, a new one → "ขอ OTP"
/// (`POST /api/me/phone/otp/request {phone}`) → the code → verify
/// (`POST /api/me/phone/otp/verify {phone, code}`) which changes it.
/// Pops `true` after a change.
class PhoneChangeScreen extends StatefulWidget {
  const PhoneChangeScreen({super.key, this.currentPhone});

  /// Shown at the top; loaded from `GET /api/me/profile` when null.
  final String? currentPhone;

  @override
  State<PhoneChangeScreen> createState() => _PhoneChangeScreenState();
}

class _PhoneChangeScreenState extends State<PhoneChangeScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  late String? _current = widget.currentPhone;
  String? _sentTo;
  String? _ref;
  String? _done;
  bool _busy = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _phone.addListener(() => setState(() {}));
    _code.addListener(() => setState(() {}));
    if (_current == null) {
      context.read<AppConfig>().apiClient.getMyProfile().then((p) {
        final v = '${p['phone_mobile'] ?? ''}'.trim();
        if (mounted && v.isNotEmpty) setState(() => _current = v);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
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

  Future<void> _request() async {
    final bad = phoneProblem(_phone.text, current: _current);
    if (bad != null) {
      HapticFeedback.heavyImpact();
      return setState(() => _error = bad);
    }
    final phone = normalizePhone(_phone.text);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await context.read<AppConfig>().apiClient.requestPhoneBindOtp(phone);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _sentTo = phone;
        final ref = '${r['ref'] ?? r['ref_code'] ?? ''}'.trim();
        _ref = ref.isEmpty || ref == 'null' ? null : ref;
        _code.clear();
      });
      _startCooldown(resendSeconds(r));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = phoneOtpErrorText(e));
      if (e is ApiEnvelopeException && e.statusCode == 429) _startCooldown(resendSeconds(e.details));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 4) return setState(() => _error = 'กรุณากรอกรหัส OTP');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await context.read<AppConfig>().apiClient.verifyPhoneBindOtp(_sentTo!, code);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final saved = '${r['phone_mobile'] ?? r['phone'] ?? ''}'.trim();
      setState(() => _done = saved.isEmpty || saved == 'null' ? _sentTo : saved);
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _error = phoneOtpErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _edit() {
    _timer?.cancel();
    setState(() {
      _sentTo = null;
      _cooldown = 0;
      _code.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const green = Color(0xFF16A34A);

    if (_done != null) {
      return ProfileSubPage(title: 'เปลี่ยนเบอร์โทรศัพท์', maxWidth: 560, children: [
        const SizedBox(height: 24),
        const ProfileHeroIcon(icon: NxI.checkCircle, color: green, size: 88),
        const SizedBox(height: 18),
        Text(tr('เปลี่ยนเบอร์โทรศัพท์แล้ว'), textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(tr('เบอร์ใหม่ของคุณ'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(formatPhone(_done!), key: const ValueKey('phone-done-number'), textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(height: 10),
        Text(tr('ใช้เข้าสู่ระบบด้วย OTP SMS และรับรหัสยืนยันได้ทันที'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 28),
        FilledButton(
          key: const ValueKey('phone-done'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(tr('เสร็จ')),
        ),
      ]);
    }

    final sent = _sentTo != null;
    final current = (_current ?? '').trim();
    return ProfileSubPage(
      title: 'เปลี่ยนเบอร์โทรศัพท์',
      maxWidth: 560,
      children: [
        Container(
          key: const ValueKey('phone-current'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(22)),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: green.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
              child: const Icon(NxI.phone, color: green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('เบอร์ปัจจุบัน'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                Text(
                  current.isEmpty ? tr('ยังไม่มีเบอร์มือถือ') : formatPhone(current),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: current.isEmpty ? cs.onSurfaceVariant : null),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        Text(tr('1. เบอร์มือถือใหม่'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('phone-new'),
          controller: _phone,
          enabled: !sent && !_busy,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+\- ]')), LengthLimitingTextInputFormatter(16)],
          onSubmitted: (_) => sent || _busy ? null : _request(),
          decoration: NxFieldStyle.input(
            context,
            label: 'เบอร์มือถือใหม่',
            icon: NxI.deviceMobile,
            hint: '08x-xxx-xxxx',
            suffix: sent ? NxFieldAction(key: const ValueKey('phone-edit'), tooltip: 'แก้เบอร์', icon: NxI.pencilSimple, onPressed: _busy ? null : _edit) : null,
          ),
        ),
        if (!sent) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('phone-request'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _busy || _cooldown > 0 || _phone.text.trim().isEmpty ? null : _request,
            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.send, size: 18),
            label: Text(_cooldown > 0 ? tr('ขอรหัสใหม่ได้ใน $_cooldown วินาที') : tr('ขอ OTP')),
          ),
        ],
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !sent
              ? const SizedBox(width: double.infinity)
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 20),
                  Text(tr('2. ใส่รหัส OTP'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    '${tr('ส่งรหัสไปที่ ${formatPhone(_sentTo!)} แล้ว')}${_ref == null ? '' : ' (Ref: $_ref)'}',
                    key: const ValueKey('phone-sent-info'),
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('phone-code'),
                    controller: _code,
                    enabled: !_busy,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    maxLength: 8,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _busy ? null : _verify(),
                    style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 6, fontWeight: FontWeight.w800),
                    decoration: NxFieldStyle.input(context, label: 'รหัส OTP', icon: NxI.shieldCheck, counter: false),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextButton(
                        key: const ValueKey('phone-resend'),
                        onPressed: _busy || _cooldown > 0 ? null : _request,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(_cooldown > 0 ? tr('ขอรหัสใหม่ได้ใน $_cooldown วินาที') : tr('ส่งรหัสอีกครั้ง'), maxLines: 1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('phone-verify'),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                        onPressed: _busy || _code.text.trim().length < 4 ? null : _verify,
                        child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('ยืนยันเบอร์ใหม่')),
                      ),
                    ),
                  ]),
                ]),
        ),
        if (_error != null) ProfileErrorText(_error!, key: const ValueKey('phone-error')),
        const SizedBox(height: 18),
        Text(
          tr('เบอร์มือถือใช้เข้าสู่ระบบด้วย OTP SMS และรับรหัสยืนยันตัวตน'),
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

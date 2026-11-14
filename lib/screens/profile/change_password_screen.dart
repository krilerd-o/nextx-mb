import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../widgets/fields/nx_field_chrome.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/settings_tiles.dart';
import 'otp_proof.dart';
import 'profile_ui.dart';
import 'step_up.dart';

/// 0–4 strength score and its Thai label for a new password.
({int score, String label}) passwordStrength(String pw) {
  if (pw.isEmpty) return (score: 0, label: '');
  var s = 0;
  if (pw.length >= 8) s++;
  if (pw.length >= 12) s++;
  if (RegExp(r'[a-z]').hasMatch(pw) && RegExp(r'[A-Z]').hasMatch(pw)) s++;
  if (RegExp(r'\d').hasMatch(pw)) s++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(pw)) s++;
  if (pw.length < 6) s = 0;
  final score = s.clamp(0, 4);
  const labels = ['สั้นเกินไป', 'อ่อน', 'พอใช้', 'ดี', 'แข็งแรงมาก'];
  return (score: score, label: labels[score]);
}

/// "เปลี่ยนรหัสผ่าน" in three steps:
/// 1) pick how to prove it is me (`GET /api/me/verify/methods`: email OTP,
///    SMS OTP or the current password),
/// 2) verify (`/api/me/verify/request|confirm` or `/verify/password`),
/// 3) the new password + confirm → `PUT /api/me/password {new_password, verify_token}`.
///
/// Servers without the step-up API keep the older OTP sign-in proof.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  VerifyMethods? _methods;
  bool _legacy = false;
  Object? _loadError;
  String? _channel;
  String? _token;
  String? _error;
  bool _busy = false;
  bool _show = false;
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pw.addListener(() => setState(() {}));
    _pw2.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final m = VerifyMethods.fromJson(await context.read<AppConfig>().apiClient.getVerifyMethods());
      if (mounted) setState(() => _methods = m);
    } catch (e) {
      if (!mounted) return;
      setState(() => isMissingEndpoint(e) ? _legacy = true : _loadError = e);
    }
  }

  int get _step => _token != null ? 2 : (_channel != null ? 1 : 0);

  String? _check() {
    if (_pw.text.length < 6) return 'รหัสผ่านใหม่อย่างน้อย 6 ตัวอักษร';
    if (_pw.text != _pw2.text) return 'รหัสไม่ตรงกัน';
    return null;
  }

  Future<void> _save() async {
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
      await api.changePasswordVerified(_pw.text, _token!);
      HapticFeedback.mediumImpact();
      messenger.showSnackBar(SnackBar(content: Text(tr('เปลี่ยนรหัสผ่านแล้ว'))));
      nav.pop(true);
    } catch (e) {
      if (!mounted) return;
      final stepUp = e is ApiEnvelopeException &&
          (e.errorCode.toUpperCase().contains('STEP_UP') || e.errorCode.toUpperCase().startsWith('VERIFY_') || e.statusCode == 401);
      setState(() {
        // verify_token is single-use: any refused save needs a fresh proof.
        // The typed password stays.
        _token = null;
        _channel = null;
        final msg = e is ApiEnvelopeException ? e.message.trim() : '';
        _error = stepUp
            ? (msg.isNotEmpty ? msg : 'การยืนยันตัวตนหมดอายุ กรุณายืนยันอีกครั้ง')
            : '${formatApiError(e)} — ${tr('กรุณายืนยันตัวตนอีกครั้ง')}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_legacy) return const _LegacyOtpPassword();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = _methods;
    final children = <Widget>[];
    if (m == null) {
      children.add(_loadError == null
          ? const NxSkeletonList(rows: 3)
          : NxSoftNote(
              icon: NxI.warningCircle,
              color: cs.error,
              text: formatApiError(_loadError!),
              action: TextButton(onPressed: _load, child: Text(tr('ลองใหม่'))),
            ));
    } else {
      children.addAll([
        ProfileSteps(labels: const ['เลือกวิธี', 'ยืนยันตัวตน', 'รหัสใหม่'], current: _step),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(a), child: c),
          ),
          child: KeyedSubtree(key: ValueKey(_step), child: _stepBody(context, m)),
        ),
      ]);
    }
    if (_error != null) children.add(ProfileErrorText(_error!, key: const ValueKey('pw-error')));
    return ProfileSubPage(title: 'เปลี่ยนรหัสผ่าน', maxWidth: 560, children: children);
  }

  Widget _stepBody(BuildContext context, VerifyMethods m) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    switch (_step) {
      case 0:
        final none = !m.email && !m.sms && !m.password;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('ยืนยันว่าเป็นคุณก่อนเปลี่ยนรหัสผ่าน'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(tr('เลือกวิธีที่สะดวก'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 14),
          for (final c in ['email', 'sms', 'password'])
            Padding(padding: const EdgeInsets.only(bottom: 10), child: _MethodCard(channel: c, methods: m, onTap: () => setState(() {
                  _channel = c;
                  _error = null;
                }))),
          if (none)
            const NxSoftNote(
              icon: NxI.warningCircle,
              text: 'บัญชีนี้ยังไม่มีอีเมล เบอร์มือถือ หรือรหัสผ่านสำหรับยืนยัน — ติดต่อผู้ดูแลระบบ',
            ),
        ]);
      case 1:
        final c = _channel!;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          StepUpVerifier(
            key: ValueKey('pw-verifier-$c'),
            channel: c,
            keyPrefix: 'pw',
            masked: m.masked(c),
            autoSend: c != 'password',
            onVerified: (t) => setState(() {
              _token = t;
              _error = null;
            }),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('pw-change-method'),
              onPressed: () => setState(() => _channel = null),
              icon: const Icon(NxI.arrowLeft, size: 16),
              label: Text(tr('เปลี่ยนวิธียืนยัน')),
            ),
          ),
        ]);
      default:
        final st = passwordStrength(_pw.text);
        final colors = [cs.error, const Color(0xFFF97316), const Color(0xFFEAB308), const Color(0xFF22C55E), const Color(0xFF16A34A)];
        final match = _pw2.text.isNotEmpty && _pw.text == _pw2.text;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NxSoftNote(
            key: ValueKey('pw-verified-note'),
            icon: NxI.checkCircle,
            color: Color(0xFF16A34A),
            text: 'ยืนยันตัวตนแล้ว ตั้งรหัสผ่านใหม่ได้เลย',
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('pw-new'),
            controller: _pw,
            obscureText: !_show,
            autofillHints: const [AutofillHints.newPassword],
            decoration: NxFieldStyle.input(
              context,
              label: 'รหัสผ่านใหม่',
              icon: NxI.password,
              suffix: NxPasswordToggle(
                key: const ValueKey('pw-show'),
                obscured: !_show,
                onToggle: () => setState(() => _show = !_show),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: _pw.text.isNotEmpty && i < st.score.clamp(1, 4) ? colors[st.score] : cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 4),
          Text(
            _pw.text.isEmpty ? tr('อย่างน้อย 6 ตัวอักษร · ใช้ตัวพิมพ์ใหญ่ ตัวเลข และสัญลักษณ์จะปลอดภัยขึ้น') : '${tr('ความแข็งแรง')}: ${tr(st.label)}',
            key: const ValueKey('pw-strength'),
            style: theme.textTheme.bodySmall?.copyWith(color: _pw.text.isEmpty ? cs.onSurfaceVariant : colors[st.score]),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('pw-confirm'),
            controller: _pw2,
            obscureText: !_show,
            autofillHints: const [AutofillHints.newPassword],
            onSubmitted: (_) => _busy ? null : _save(),
            decoration: NxFieldStyle.input(
              context,
              label: 'ยืนยันรหัสผ่านใหม่',
              icon: NxI.password,
              suffix: match ? const Icon(NxI.checkCircle, color: Color(0xFF16A34A), size: 20) : null,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            key: const ValueKey('pw-submit'),
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('บันทึกรหัสผ่านใหม่')),
          ),
        ]);
    }
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({required this.channel, required this.methods, required this.onTap});
  final String channel;
  final VerifyMethods methods;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final on = methods.available(channel);
    final (title, icon) = verifyChannelLabel(channel);
    final sub = !on
        ? tr(methods.unavailableText(channel))
        : switch (channel) {
            'email' => methods.emailMasked ?? tr('อีเมลของบัญชี'),
            'sms' => methods.smsMasked ?? tr('เบอร์มือถือของบัญชี'),
            _ => tr('ใช้รหัสผ่านที่ใช้อยู่ตอนนี้'),
          };
    return Opacity(
      opacity: on ? 1 : 0.45,
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: ValueKey('pw-method-$channel'),
          borderRadius: BorderRadius.circular(20),
          onTap: on ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: cs.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
              if (on) Icon(NxI.caretRight, color: cs.onSurfaceVariant, size: 18),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Older servers (no `/api/me/verify/*`): one-time code through the OTP
/// sign-in endpoints ([OtpProofSection]), then `PUT /api/me/password` with
/// that session.
class _LegacyOtpPassword extends StatefulWidget {
  const _LegacyOtpPassword();

  @override
  State<_LegacyOtpPassword> createState() => _LegacyOtpPasswordState();
}

class _LegacyOtpPasswordState extends State<_LegacyOtpPassword> {
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
    return ProfileSubPage(
      title: 'เปลี่ยนรหัสผ่าน',
      maxWidth: 560,
      children: [
        Text(tr('ยืนยันตัวตนด้วยรหัส OTP แทนรหัสผ่านเดิม'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
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
                    decoration: NxFieldStyle.input(
                      context,
                      label: 'รหัสผ่านใหม่',
                      icon: NxI.password,
                      suffix: NxPasswordToggle(obscured: !_show, onToggle: () => setState(() => _show = !_show)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('pw-confirm'),
                    controller: _pw2,
                    obscureText: !_show,
                    decoration: NxFieldStyle.input(context, label: 'ยืนยันรหัสผ่านใหม่', icon: NxI.password),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('pw-submit'),
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('เปลี่ยนรหัสผ่าน')),
                  ),
                ]),
        ),
        if (_error != null) ProfileErrorText(_error!, key: const ValueKey('pw-error')),
      ],
    );
  }
}

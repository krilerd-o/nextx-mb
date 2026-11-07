import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/auth_errors.dart';
import '../../core/auth_redirect.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_page_route.dart';
import '../../core/server_profile.dart';
import '../../services/google_auth.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_hero_illustration.dart';
import '../../widgets/nx_icons.dart';
import '../crm/field_gallery_screen.dart';
import 'line_login_screen.dart';
import 'link_confirm_screen.dart';
import 'register_screen.dart';
import '../../core/i18n.dart';

enum _Mode { password, otpEmail, otpSms }

/// Which social sign-ins the current server has configured.
class SocialAvailability {
  const SocialAvailability({this.line = false, this.googleClientId});
  final bool line;
  final String? googleClientId;
  bool get google => googleClientId != null && googleClientId!.isNotEmpty;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _id = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  _Mode _mode = _Mode.password;
  bool _otpSent = false;
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  SocialAvailability _social = const SocialAvailability();

  @override
  void initState() {
    super.initState();
    final config = context.read<AppConfig>();
    if (config.sessionExpiredNotice) {
      _error = config.sessionRevokedNotice
          ? 'ถูกออกจากระบบจากอุปกรณ์อื่น กรุณาเข้าสู่ระบบใหม่'
          : 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
      WidgetsBinding.instance.addPostFrameCallback((_) => config.clearSessionExpiredNotice());
    }
    final recent = config.recentAccounts;
    if (recent.isNotEmpty && !RegExp(r'^\+?[0-9 -]+$').hasMatch(recent.first.loginId)) _id.text = recent.first.loginId;
    final invite = config.pendingInvite;
    if (invite != null) WidgetsBinding.instance.addPostFrameCallback((_) => _openRegister());
    _loadSocial();
  }

  Future<void> _openRegister() async {
    if (!mounted) return;
    await nxPush<bool>(context, RegisterScreen(inviteToken: context.read<AppConfig>().pendingInvite?.token));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _id.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _loadSocial() async {
    final api = context.read<AppConfig>().apiClient;
    var line = false;
    String? google;
    try {
      final c = await api.getLineCheck();
      line = (c['channel_id']?.toString() ?? '').isNotEmpty;
    } catch (_) {}
    if (GoogleAuth.supported) {
      try {
        final g = await api.getGoogleOneTapConfig();
        if (g['sign_in_ready'] == true || g['enabled'] == true) google = g['client_id']?.toString();
      } catch (_) {}
    }
    if (mounted) setState(() => _social = SocialAvailability(line: line, googleClientId: google));
  }

  Future<void> _run(Future<void> Function() action) async {
    context.read<AppConfig>().clearAuthLinkError();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } on LinkConfirmRequired catch (e) {
      await _openLinkConfirm(e.intentToken, google: false);
    } on GoogleMergeRequired catch (e) {
      await _openLinkConfirm(e.intentToken, google: true);
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openLinkConfirm(String intent, {required bool google}) async {
    if (!mounted || intent.isEmpty) return;
    await nxPush<bool>(context, LinkConfirmScreen(intentToken: intent, google: google));
  }

  Future<void> _primary() async {
    final id = _id.text.trim();
    final config = context.read<AppConfig>();
    switch (_mode) {
      case _Mode.password:
        if (id.isEmpty || _password.text.isEmpty) {
          setState(() => _error = 'กรุณากรอกอีเมล/ชื่อผู้ใช้ และรหัสผ่าน');
          return;
        }
        await _run(() => config.loginWithPassword(email: id, password: _password.text));
      case _Mode.otpEmail:
      case _Mode.otpSms:
        final sms = _mode == _Mode.otpSms;
        if (id.isEmpty) {
          setState(() => _error = sms ? 'กรุณากรอกเบอร์มือถือ' : 'กรุณากรอกอีเมล');
          return;
        }
        if (!_otpSent) {
          await _run(() async {
            sms ? await config.requestSmsOtp(id) : await config.requestEmailOtp(id);
            if (mounted) {
              setState(() => _otpSent = true);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ส่งรหัส OTP ไปที่ $id แล้ว'))));
            }
          });
        } else {
          final code = _code.text.trim();
          if (code.length < 4) {
            setState(() => _error = 'กรุณากรอกรหัส OTP');
            return;
          }
          await _run(() => sms ? config.loginWithSmsOtp(phone: id, code: code) : config.loginWithEmailOtp(email: id, code: code));
        }
    }
  }

  Future<void> _line() async {
    final config = context.read<AppConfig>();
    // Newer servers send the browser back to moainext://app/login (LINE app sign-in,
    // saved LINE session). The router hands that link to AppConfig.handleAuthDeepLink.
    if (config.serverInfo?.has('line_app') ?? false) {
      final uri = Uri.parse(config.apiClient.lineLoginUrlFor(app: true));
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok || !mounted) return;
    }
    if (!mounted) return;
    final result = await nxPush<String>(context, const LineLoginScreen());
    if (result == null || !mounted) return;
    if (result.startsWith('error:')) {
      setState(() => _error = authRedirectErrorText(result.substring(6)));
      return;
    }
    await _run(() => context.read<AppConfig>().loginWithToken(result));
  }

  Future<void> _google() async {
    final clientId = _social.googleClientId;
    if (clientId == null) return;
    await _run(() async {
      final idToken = await GoogleAuth.idToken(clientId);
      if (idToken == null) return; // cancelled
      if (!mounted) return;
      await context.read<AppConfig>().loginWithGoogleIdToken(idToken);
    });
  }

  Future<void> _forgot() async {
    final email = _id.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'กรอกอีเมลของคุณในช่องด้านบนก่อน แล้วกด "ลืมรหัสผ่าน"');
      return;
    }
    await _run(() async {
      await context.read<AppConfig>().apiClient.forgotPassword(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ถ้าอีเมลนี้มีในระบบ จะได้รับลิงก์ตั้งรหัสผ่านใหม่'))));
      }
    });
  }

  void _setMode(_Mode m) => setState(() {
        _mode = m;
        _otpSent = false;
        _error = null;
        _code.clear();
      });

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: trn(label),
        prefixIcon: Icon(icon),
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = context.watch<AppConfig>();
    final otp = _mode != _Mode.password;
    final sms = _mode == _Mode.otpSms;
    final primaryLabel = switch (_mode) {
      _Mode.password => 'เข้าสู่ระบบ',
      _ => _otpSent ? 'ยืนยันรหัส OTP' : 'ส่งรหัส OTP',
    };

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Stack(
            children: [
              const NxHeroIllustration(height: 230),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: ActionChip(
                      avatar: const Icon(NxI.globe, size: 16),
                      label: Text(tr(serverLabel(config.apiBaseUrl)), overflow: TextOverflow.ellipsis),
                      tooltip: tr('เปลี่ยนเซิร์ฟเวอร์'),
                      onPressed: _loading
                          ? null
                          : () async {
                              await config.resetServerChoice();
                              if (context.mounted) context.go(AppRoutes.server);
                            },
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('ยินดีต้อนรับกลับ'), textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(tr('เข้าสู่ระบบ MOAI NEXT ของธุรกิจคุณ'),
                    textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 20),
                SegmentedButton<_Mode>(
                  segments: [
                    ButtonSegment(value: _Mode.password, label: Text(tr('รหัสผ่าน'))),
                    ButtonSegment(value: _Mode.otpEmail, label: Text(tr('OTP อีเมล'))),
                    ButtonSegment(value: _Mode.otpSms, label: Text(tr('OTP SMS'))),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: _loading ? null : (v) => _setMode(v.first),
                ),
                if (config.pendingInvite != null) ...[
                  const SizedBox(height: 14),
                  Material(
                    color: cs.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      leading: Icon(NxI.envelope, color: cs.primary),
                      title: Text(tr('คุณได้รับลิงก์เชิญเข้าธุรกิจ')),
                      subtitle: Text(tr('ยังไม่มีบัญชี แตะเพื่อสมัคร · มีบัญชีแล้ว เข้าสู่ระบบเพื่อเข้าร่วม')),
                      onTap: _loading ? null : _openRegister,
                    ),
                  ),
                ],
                if (config.recentAccounts.isNotEmpty && _mode != _Mode.otpSms) ...[
                  const SizedBox(height: 14),
                  Text(tr('บัญชีที่เคยใช้'), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final a in config.recentAccounts)
                        InputChip(
        deleteIcon: const Icon(NxI.x, size: 16),
                          avatar: CircleAvatar(
                            child: Text(tr((a.name.isNotEmpty ? a.name : a.loginId).characters.first.toUpperCase())),
                          ),
                          label: Text(tr(a.name.isNotEmpty ? a.name : a.loginId), overflow: TextOverflow.ellipsis),
                          tooltip: trn(a.loginId),
                          selected: _id.text.trim().toLowerCase() == a.loginId.toLowerCase(),
                          showCheckmark: false,
                          onPressed: _loading || (otp && _otpSent) ? null : () => setState(() => _id.text = a.loginId),
                          onDeleted: _loading ? null : () => config.forgetRecentAccount(a),
                          deleteButtonTooltipMessage: 'ลบออกจากเครื่องนี้',
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _id,
                  enabled: !_loading && !(otp && _otpSent),
                  keyboardType: sms ? TextInputType.phone : TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: sms ? const [AutofillHints.telephoneNumber] : const [AutofillHints.username, AutofillHints.email],
                  decoration: _dec(
                    switch (_mode) { _Mode.password => 'อีเมลหรือชื่อผู้ใช้', _Mode.otpEmail => 'อีเมล', _Mode.otpSms => 'เบอร์มือถือ' },
                    sms ? NxI.phone : NxI.envelope,
                  ),
                ),
                const SizedBox(height: 12),
                if (!otp)
                  TextField(
                    controller: _password,
                    enabled: !_loading,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _loading ? null : _primary(),
                    decoration: _dec('รหัสผ่าน', NxI.password).copyWith(
                      suffixIcon: IconButton(
                        tooltip: trn(_obscure ? 'แสดงรหัสผ่าน' : 'ซ่อนรหัสผ่าน'),
                        icon: Icon(_obscure ? NxI.eye : NxI.eyeOff),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  )
                else if (_otpSent)
                  TextField(
                    controller: _code,
                    enabled: !_loading,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 10, fontWeight: FontWeight.w700),
                    autofillHints: const [AutofillHints.oneTimeCode],
                    onSubmitted: (_) => _loading ? null : _primary(),
                    decoration: _dec('รหัส OTP 6 หลัก', NxI.shieldCheck).copyWith(counterText: ''),
                  ),
                if (!otp)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: _loading ? null : _forgot, child: Text(tr('ลืมรหัสผ่าน?'))),
                  ),
                if (otp && _otpSent)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _loading ? null : () => setState(() => _otpSent = false),
                        child: Text(tr(sms ? 'เปลี่ยนเบอร์' : 'เปลี่ยนอีเมล')),
                      ),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                setState(() => _otpSent = false);
                                _primary();
                              },
                        child: Text(tr('ส่งรหัสอีกครั้ง')),
                      ),
                    ],
                  ),
                if (config.authLinkBusy)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text(tr('กำลังเข้าสู่ระบบด้วย LINE…')),
                    ]),
                  ),
                if ((_error ?? config.authLinkError) != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        Icon(NxI.warningCircle, color: cs.onErrorContainer, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(tr((_error ?? config.authLinkError)!), style: TextStyle(color: cs.onErrorContainer))),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                NxHeroCta(label: primaryLabel, busy: _loading, onPressed: _loading ? null : _primary),
                if (_social.line || _social.google) ...[
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(tr('หรือเข้าสู่ระบบด้วย'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (_social.line)
                        Expanded(
                          child: _SocialButton(
                            label: 'LINE',
                            background: const Color(0xFF06C755),
                            foreground: Colors.white,
                            icon: NxI.chatCircle,
                            onPressed: _loading ? null : _line,
                          ),
                        ),
                      if (_social.line && _social.google) const SizedBox(width: 12),
                      if (_social.google)
                        Expanded(
                          child: _SocialButton(
                            label: 'Google',
                            background: cs.surface,
                            foreground: cs.onSurface,
                            border: cs.outlineVariant,
                            leading: Text(tr('G'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Color(0xFF4285F4))),
                            onPressed: _loading ? null : _google,
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(tr('ยังไม่มีบัญชี?'), style: theme.textTheme.bodyMedium),
                    TextButton(
                      onPressed: _loading ? null : _openRegister,
                      child: Text(tr('สมัครสมาชิก')),
                    ),
                  ],
                ),
                if (kDebugMode)
                  TextButton(
                    onPressed: () => nxPush<void>(context, const FieldGalleryScreen()),
                    child: Text(tr('พรีวิว UI Type')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.background,
    required this.foreground,
    this.border,
    this.icon,
    this.leading,
    this.onPressed,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color? border;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          side: BorderSide(color: border ?? background),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading ?? Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(tr(label), style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

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
import '../../services/apple_auth.dart';
import '../../services/google_auth.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_app_logo.dart';
import '../../widgets/nx_icons.dart';
import '../crm/field_gallery_screen.dart';
import 'line_login_screen.dart';
import 'qr_login_scan_screen.dart';
import 'link_confirm_screen.dart';
import 'register_screen.dart';
import '../../core/i18n.dart';

enum _Mode { password, otpEmail, otpSms, scan }

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
      _error = config.sessionRevokedNotice ? 'ถูกออกจากระบบจากอุปกรณ์อื่น กรุณาเข้าสู่ระบบใหม่' : 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
      WidgetsBinding.instance.addPostFrameCallback((_) => config.clearSessionExpiredNotice());
    }
    final recent = config.recentAccounts;
    if (recent.isNotEmpty && !RegExp(r'^\+?[0-9 -]+$').hasMatch(recent.first.loginId)) _id.text = recent.first.loginId;
    final invite = config.pendingInvite;
    if (invite != null) WidgetsBinding.instance.addPostFrameCallback((_) => _openRegister());
    _loadSocial();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePending());
    _config = context.read<AppConfig>()..addListener(_onConfig);
  }

  AppConfig? _config;
  bool _consuming = false;

  /// A Google browser sign-in that needs linking can arrive while this screen
  /// is already open (deep link) — open the confirm screen then too.
  void _onConfig() {
    final c = _config;
    if (c == null || _consuming || !mounted || !c.hasPendingGoogleMerge) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePending());
  }

  /// QR opened from the phone camera app, or a Google browser sign-in that
  /// needs the user to confirm linking an existing account.
  Future<void> _consumePending() async {
    if (!mounted || _consuming) return;
    _consuming = true;
    try {
      final config = context.read<AppConfig>();
      final merge = config.takePendingGoogleMerge();
      if (merge != null) await _openLinkConfirm(merge, google: true);
      final qr = config.takePendingQr();
      if (qr != null && mounted) await nxPush<bool>(context, QrLoginScanScreen(initial: qr));
    } finally {
      _consuming = false;
    }
  }

  Future<void> _scan() async {
    context.read<AppConfig>().clearAuthLinkError();
    setState(() => _error = null);
    await nxPush<bool>(context, const QrLoginScanScreen());
  }

  Future<void> _openRegister() async {
    if (!mounted) return;
    await nxPush<bool>(context, RegisterScreen(inviteToken: context.read<AppConfig>().pendingInvite?.token));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _config?.removeListener(_onConfig);
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
      case _Mode.scan:
        await _scan();
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
    final config = context.read<AppConfig>();
    await _run(() async {
      String? idToken;
      try {
        idToken = await GoogleAuth.idToken(clientId);
      } on GoogleAuthError {
        // Huawei with GBox / microG (no Credential Manager) or a key not yet
        // registered: sign in through the browser, which returns to the app.
        if (config.serverInfo?.has('google_app') ?? false) {
          final ok = await launchUrl(Uri.parse(config.apiClient.googleAppLoginUrl), mode: LaunchMode.externalApplication);
          if (ok) return;
        }
        rethrow;
      }
      if (idToken == null) return; // cancelled
      if (!mounted) return;
      await config.loginWithGoogleIdToken(idToken);
    });
  }

  Future<void> _apple() async {
    await _run(() async {
      final token = await AppleAuth.identityToken();
      if (token == null || !mounted) return; // cancelled
      await context.read<AppConfig>().loginWithAppleIdToken(token);
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
    final scan = _mode == _Mode.scan;
    final otp = _mode == _Mode.otpEmail || _mode == _Mode.otpSms;
    final sms = _mode == _Mode.otpSms;
    final primaryLabel = switch (_mode) {
      _Mode.password => 'เข้าสู่ระบบ',
      _Mode.scan => 'สแกน QR จากเว็บ',
      _ => _otpSent ? 'ยืนยันรหัส OTP' : 'ส่งรหัส OTP',
    };

    final err = _error ?? config.authLinkError;
    InputDecoration field(String label, IconData icon) =>
        _dec(label, icon).copyWith(fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16));

    return Scaffold(
      body: Stack(
        children: [
          // Soft colour wash behind the logo (no busy illustration).
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 340,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [cs.primary.withValues(alpha: 0.14), cs.surface.withValues(alpha: 0)]),
              ),
            ),
          ),
          // Content sits in the middle of the screen; with the keyboard open the
          // page shrinks and it scrolls up so the field stays visible.
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 52, 24, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: (box.maxHeight - 76).clamp(0.0, double.infinity)),
                  child: Column(
                    key: const ValueKey('login-body'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [BoxShadow(color: const Color(0xFF0B0A5C).withValues(alpha: 0.28), blurRadius: 26, offset: const Offset(0, 12))],
                          ),
                          child: const NxAppLogo(size: 76),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        tr('ยินดีต้อนรับกลับ'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr('เข้าสู่ระบบ MOAI NEXT ของธุรกิจคุณ'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24),
                      _ModeSwitch(value: _mode.index, labels: [tr('รหัสผ่าน'), tr('อีเมล'), tr('SMS'), tr('สแกน')], onChanged: _loading ? null : (i) => _setMode(_Mode.values[i])),
                      if (config.pendingInvite != null) ...[
                        const SizedBox(height: 14),
                        Material(
                          color: cs.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            leading: Icon(NxI.envelope, color: cs.primary),
                            title: Text(tr('คุณได้รับลิงก์เชิญเข้าธุรกิจ')),
                            subtitle: Text(tr('ยังไม่มีบัญชี แตะเพื่อสมัคร · มีบัญชีแล้ว เข้าสู่ระบบเพื่อเข้าร่วม')),
                            onTap: _loading ? null : _openRegister,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      if (scan) _ScanPanel(key: const ValueKey('login-scan'), onTap: _loading ? null : _scan),
                      if (!scan) ...[
                        TextField(
                          key: const ValueKey('login-id'),
                          controller: _id,
                          enabled: !_loading && !(otp && _otpSent),
                          keyboardType: sms ? TextInputType.phone : TextInputType.emailAddress,
                          autocorrect: false,
                          autofillHints: sms ? const [AutofillHints.telephoneNumber] : const [AutofillHints.username, AutofillHints.email],
                          decoration:
                              field(switch (_mode) {
                                _Mode.password => 'อีเมลหรือชื่อผู้ใช้',
                                _Mode.otpEmail => 'อีเมล',
                                _Mode.otpSms => 'เบอร์มือถือ',
                                _Mode.scan => '',
                              }, sms ? NxI.phone : NxI.envelope).copyWith(
                                // Saved accounts live behind one small button instead of a row of chips.
                                suffixIcon: config.recentAccounts.isEmpty || sms || (otp && _otpSent)
                                    ? null
                                    : IconButton(
                                        key: const ValueKey('login-recent'),
                                        tooltip: tr('บัญชีที่เคยใช้'),
                                        icon: const Icon(NxI.users, size: 20),
                                        onPressed: _loading ? null : () => _pickRecent(config),
                                      ),
                              ),
                        ),
                        const SizedBox(height: 12),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: !otp
                              ? TextField(
                                  key: const ValueKey('login-password'),
                                  controller: _password,
                                  enabled: !_loading,
                                  obscureText: _obscure,
                                  autofillHints: const [AutofillHints.password],
                                  onSubmitted: (_) => _loading ? null : _primary(),
                                  decoration: field('รหัสผ่าน', NxI.password).copyWith(
                                    suffixIcon: IconButton(
                                      tooltip: trn(_obscure ? 'แสดงรหัสผ่าน' : 'ซ่อนรหัสผ่าน'),
                                      icon: Icon(_obscure ? NxI.eye : NxI.eyeOff, size: 20),
                                      onPressed: () => setState(() => _obscure = !_obscure),
                                    ),
                                  ),
                                )
                              : _otpSent
                              ? TextField(
                                  controller: _code,
                                  enabled: !_loading,
                                  autofocus: true,
                                  keyboardType: TextInputType.number,
                                  maxLength: 6,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 10, fontWeight: FontWeight.w700),
                                  autofillHints: const [AutofillHints.oneTimeCode],
                                  onSubmitted: (_) => _loading ? null : _primary(),
                                  decoration: field('รหัส OTP 6 หลัก', NxI.shieldCheck).copyWith(counterText: ''),
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                        if (!otp && !scan)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(onPressed: _loading ? null : _forgot, child: Text(tr('ลืมรหัสผ่าน?'))),
                          ),
                        if (otp && _otpSent)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(onPressed: _loading ? null : () => setState(() => _otpSent = false), child: Text(tr(sms ? 'เปลี่ยนเบอร์' : 'เปลี่ยนอีเมล'))),
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
                      ],
                      if (config.authLinkBusy)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                              const SizedBox(width: 10),
                              Text(tr('กำลังเข้าสู่ระบบด้วย LINE…')),
                            ],
                          ),
                        ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        child: err == null
                            ? const SizedBox(width: double.infinity)
                            : Container(
                                key: const ValueKey('login-error'),
                                margin: const EdgeInsets.only(top: 8, bottom: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(14)),
                                child: Row(
                                  children: [
                                    Icon(NxI.warningCircle, color: cs.onErrorContainer, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(tr(err), style: TextStyle(color: cs.onErrorContainer)),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      SizedBox(height: otp && !_otpSent ? 4 : 12),
                      NxHeroCta(key: const ValueKey('login-primary'), label: primaryLabel, busy: _loading, onPressed: _loading ? null : _primary),
                      if (_social.line || _social.google || AppleAuth.supported) ...[
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(child: Divider(color: cs.outlineVariant.withValues(alpha: 0.6))),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(tr('หรือ'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                            ),
                            Expanded(child: Divider(color: cs.outlineVariant.withValues(alpha: 0.6))),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (AppleAuth.supported) ...[
                          SizedBox(
                            width: double.infinity,
                            child: _SocialButton(
                              key: const ValueKey('login-apple'),
                              label: 'เข้าสู่ระบบด้วย Apple',
                              background: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                              foreground: theme.brightness == Brightness.dark ? Colors.black : Colors.white,
                              leading: Icon(NxI.brandApple, size: 18, color: theme.brightness == Brightness.dark ? Colors.black : Colors.white),
                              onPressed: _loading ? null : _apple,
                            ),
                          ),
                          if (_social.line || _social.google) const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            if (_social.google)
                              Expanded(
                                child: _SocialButton(
                                  label: 'Google',
                                  background: cs.surface,
                                  foreground: cs.onSurface,
                                  border: cs.outlineVariant,
                                  leading: const Icon(NxI.brandGoogle, size: 18, color: Color(0xFF4285F4)),
                                  onPressed: _loading ? null : _google,
                                ),
                              ),
                            if (_social.line && _social.google) const SizedBox(width: 12),
                            if (_social.line)
                              Expanded(
                                child: _SocialButton(
                                  label: 'LINE',
                                  background: const Color(0xFF06C755),
                                  foreground: Colors.white,
                                  leading: const Icon(NxI.brandLine, size: 18, color: Colors.white),
                                  onPressed: _loading ? null : _line,
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(tr('ยังไม่มีบัญชี?'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                          TextButton(onPressed: _loading ? null : _openRegister, child: Text(tr('สมัครสมาชิก'))),
                        ],
                      ),
                      if (kDebugMode) TextButton(onPressed: () => nxPush<void>(context, const FieldGalleryScreen()), child: Text(tr('พรีวิว UI Type'))),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Server: small pill pinned top-right, tap to change.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Align(
                alignment: Alignment.topRight,
                child: Material(
                  color: cs.surface.withValues(alpha: 0.7),
                  shape: StadiumBorder(side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
                  child: InkWell(
                    key: const ValueKey('login-server'),
                    customBorder: const StadiumBorder(),
                    onTap: _loading
                        ? null
                        : () async {
                            await config.resetServerChoice();
                            if (context.mounted) context.go(AppRoutes.server);
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(NxI.globe, size: 15, color: cs.onSurfaceVariant),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Text(serverLabel(config.apiBaseUrl), overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium),
                          ),
                          const SizedBox(width: 2),
                          Icon(NxI.caretDown, size: 14, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Saved accounts on this device: pick one, or remove it.
  Future<void> _pickRecent(AppConfig config) async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListenableBuilder(
          listenable: config,
          builder: (ctx, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(tr('บัญชีที่เคยใช้'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              for (final a in config.recentAccounts)
                ListTile(
                  leading: CircleAvatar(child: Text((a.name.isNotEmpty ? a.name : a.loginId).characters.first.toUpperCase())),
                  title: Text(a.name.isNotEmpty ? a.name : a.loginId),
                  subtitle: a.name.isNotEmpty ? Text(a.loginId) : null,
                  trailing: IconButton(tooltip: tr('ลบออกจากเครื่องนี้'), icon: const Icon(NxI.x, size: 18), onPressed: () => config.forgetRecentAccount(a)),
                  onTap: () {
                    setState(() => _id.text = a.loginId);
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill switch with a sliding highlight (password / email OTP / SMS OTP).
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.value, required this.labels, required this.onChanged});
  final int value;
  final List<String> labels;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(22)),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / labels.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: w * value,
                top: 0,
                bottom: 0,
                width: w,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: InkWell(
                        key: ValueKey('login-mode-$i'),
                        borderRadius: BorderRadius.circular(18),
                        onTap: onChanged == null || i == value ? null : () => onChanged!(i),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
                              fontWeight: i == value ? FontWeight.w800 : FontWeight.w500,
                              color: i == value ? cs.primary : cs.onSurfaceVariant,
                            ),
                            child: Text(labels[i]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({super.key, required this.label, required this.background, required this.foreground, this.border, this.leading, this.onPressed});

  final String label;
  final Color background;
  final Color foreground;
  final Color? border;
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
            ?leading,
            const SizedBox(width: 8),
            Text(tr(label), style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// Body of the "สแกน" mode: what to open on the web, and a big scan button.
class _ScanPanel extends StatelessWidget {
  const _ScanPanel({super.key, required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
                child: Icon(NxI.qrCode, color: cs.primary, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('เข้าสู่ระบบด้วย QR'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      tr('บนเว็บ: ตั้งค่า → ความปลอดภัย → เข้าใช้งานแอปมือถือด้วย QR แล้วสแกนด้วยแอปนี้ เข้าได้ทันทีไม่ต้องพิมพ์รหัส'),
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_logout.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/settings_tiles.dart';
import 'otp_proof.dart';
import 'profile_ui.dart';
import 'step_up.dart';

/// Shown on the login screen after the account was closed.
const kAccountClosedNotice = 'ปิดบัญชีแล้ว บัญชีนี้ใช้งานไม่ได้อีกจนกว่าผู้ดูแลระบบจะเปิดใช้งานให้';

/// "ลบบัญชี" — required by App Store and Google Play. On NEXTX it closes
/// the account (status Inactive on app and web); the data stays and an admin
/// can turn the account back on. It is not deleting the user record.
///
/// 1) explain, 2) "I understand", 3) verify every available code channel
/// (email OTP and SMS OTP through `/api/me/verify/*`), 4) type the confirm
/// word → `POST /api/me/delete-account {confirm:'DELETE', verify_tokens}` →
/// sign out here and back to the login screen with a message.
///
/// Servers without the step-up API keep the older OTP sign-in proof.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  /// Typed to confirm (Thai, or English for the English UI).
  static const confirmWords = {'ลบบัญชี', 'DELETE'};

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _typed = TextEditingController();
  VerifyMethods? _methods;
  bool _legacy = false;
  Object? _loadError;
  bool _understood = false;
  bool _busy = false;
  String? _error;
  bool _webOnly = false;
  final Map<String, String> _tokens = {};
  final Map<String, GlobalKey<StepUpVerifierState>> _verifiers = {};

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _typed.dispose();
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

  /// Channels to verify: every code channel the account has (email + SMS);
  /// the password only when it has neither.
  List<String> get _required {
    final m = _methods;
    if (m == null) return const [];
    final codes = m.codeChannels;
    if (codes.isNotEmpty) return codes;
    return m.password ? const ['password'] : const [];
  }

  bool get _allVerified => _required.isNotEmpty && _required.every(_tokens.containsKey);
  bool get _typedOk => DeleteAccountScreen.confirmWords.contains(_typed.text.trim());
  bool get _ready => _understood && _allVerified && _typedOk && !_busy;

  String get _webPage => '${context.read<AppConfig>().apiBaseUrl.replaceAll(RegExp(r'/+$'), '')}/account-deletion';

  Future<void> _submit() async {
    final config = context.read<AppConfig>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _webOnly = false;
    });
    try {
      final r = await config.apiClient.deactivateMyAccount([for (final c in _required) _tokens[c]!]);
      HapticFeedback.heavyImpact();
      final msg = '${r['message'] ?? ''}'.trim();
      final notice = msg.isEmpty || msg == 'null' ? kAccountClosedNotice : msg;
      messenger.showSnackBar(SnackBar(content: Text(tr(notice))));
      nav.popUntil((r) => r.isFirst);
      // The server signed every session out: forget this one here too.
      await config.signOutDeletedAccount(notice: notice);
    } catch (e) {
      if (!mounted) return;
      // verify_tokens are single-use: after any refused call, verify again.
      void resetProofs() {
        for (final c in [..._tokens.keys]) {
          _tokens.remove(c);
          _verifiers[c]?.currentState?.reset();
        }
      }

      if (e is ApiEnvelopeException && e.errorCode.toUpperCase() == 'STEP_UP_REQUIRED') {
        setState(() {
          resetProofs();
          _error = e.message.trim().isNotEmpty ? e.message.trim() : 'ต้องยืนยันตัวตนอีกครั้งก่อนปิดบัญชี';
        });
      } else if (isMissingEndpoint(e)) {
        setState(() {
          _webOnly = true;
          _error = 'เซิร์ฟเวอร์นี้ยังไม่รองรับการลบบัญชีในแอป ขอลบได้จากหน้าเว็บ';
        });
      } else {
        setState(() {
          resetProofs();
          _error = formatApiError(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_legacy) return const _LegacyDeleteAccount();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final danger = nxDangerColor(context);
    final m = _methods;
    final req = _required;
    var n = 0;
    return ProfileSubPage(
      title: 'ลบบัญชี',
      maxWidth: 600,
      children: [
        const AccountClosureExplainer(),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const ValueKey('del-understand'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _understood,
          onChanged: _busy ? null : (v) => setState(() => _understood = v ?? false),
          title: Text(tr('ฉันเข้าใจและต้องการปิดบัญชีนี้')),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !_understood
              ? const SizedBox(width: double.infinity)
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 8),
                  if (m == null)
                    (_loadError == null
                        ? const NxSkeletonList(rows: 2)
                        : NxSoftNote(
                            icon: NxI.warningCircle,
                            color: cs.error,
                            text: formatApiError(_loadError!),
                            action: TextButton(onPressed: _load, child: Text(tr('ลองใหม่'))),
                          ))
                  else if (req.isEmpty)
                    const NxSoftNote(
                      key: ValueKey('del-no-method'),
                      icon: NxI.warningCircle,
                      text: 'บัญชีนี้ยังไม่มีอีเมลหรือเบอร์มือถือสำหรับยืนยัน — ติดต่อผู้ดูแลระบบเพื่อปิดบัญชี',
                    )
                  else ...[
                    Text(
                      tr(req.length > 1 ? '${++n}. ยืนยันตัวตนทั้ง ${req.length} ช่องทาง' : '${++n}. ยืนยันตัวตน'),
                      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr(req.length > 1 ? 'ต้องยืนยันทั้งอีเมลและ SMS เพื่อความปลอดภัยของบัญชี' : 'ยืนยันว่าเป็นเจ้าของบัญชี'),
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    for (final c in req)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: StepUpVerifier(
                          key: _verifiers.putIfAbsent(c, () => GlobalKey<StepUpVerifierState>()),
                          channel: c,
                          keyPrefix: 'del-$c',
                          masked: m.masked(c),
                          verified: _tokens.containsKey(c),
                          enabled: !_busy,
                          onVerified: (t) => setState(() {
                            _tokens[c] = t;
                            _error = null;
                          }),
                        ),
                      ),
                    for (final c in const ['email', 'sms'])
                      if (!m.available(c))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            '${tr(c == 'email' ? 'อีเมล' : 'SMS')}: ${tr(m.unavailableText(c))} · ${tr('ไม่ต้องยืนยันช่องทางนี้')}',
                            key: ValueKey('del-$c-unavailable'),
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _allVerified ? 1 : 0.45,
                      child: IgnorePointer(
                        ignoring: !_allVerified,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const SizedBox(height: 8),
                          Text(tr('${++n}. พิมพ์ "${L10n.isEn ? 'DELETE' : 'ลบบัญชี'}" เพื่อยืนยัน'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          TextField(
                            key: const ValueKey('del-type'),
                            controller: _typed,
                            enabled: !_busy && _allVerified,
                            decoration: profileInput(context, L10n.isEn ? 'DELETE' : 'ลบบัญชี', icon: NxI.textT),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            key: const ValueKey('del-submit'),
                            onPressed: _ready ? _submit : null,
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: danger, foregroundColor: Colors.white),
                            icon: _busy
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(NxI.userCog, size: 18),
                            label: Text(tr('ปิดบัญชีของฉัน')),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ]),
        ),
        if (_error != null) ProfileErrorText(_error!, key: const ValueKey('del-error')),
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
    );
  }
}

/// What closing the account means: Inactive on app and web, data kept, an
/// admin can turn it back on — not deleting the user.
class AccountClosureExplainer extends StatelessWidget {
  const AccountClosureExplainer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final danger = nxDangerColor(context);
    Widget point(IconData icon, Color color, String title, String body) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(tr(body), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4)),
              ]),
            ),
          ]),
        );
    return Container(
      key: const ValueKey('del-explain'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: theme.brightness == Brightness.dark ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: danger.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(NxI.shieldAlert, color: danger),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('การลบบัญชีคือการปิดบัญชี'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: danger))),
        ]),
        point(NxI.lock, danger, 'บัญชีเป็น "ไม่ใช้งาน" (Inactive)', 'เข้าสู่ระบบไม่ได้ทั้งในแอปและบนเว็บ ทุกเครื่องจะถูกออกจากระบบ และหยุดการแจ้งเตือน'),
        point(NxI.database, cs.primary, 'ข้อมูลยังเก็บไว้ครบ', 'ข้อมูลงานที่บันทึกไว้ (ลูกค้า ใบเสนอราคา กิจกรรม ไฟล์) และประวัติยังอยู่กับธุรกิจ ไม่ถูกลบ'),
        point(NxI.userCheck, const Color(0xFF16A34A), 'ผู้ดูแลระบบเปิดใช้งานคืนได้', 'ถ้าต้องการกลับมาใช้ ติดต่อผู้ดูแลระบบของธุรกิจให้เปิดบัญชีอีกครั้ง'),
        point(NxI.info, cs.onSurfaceVariant, 'ไม่ใช่การลบผู้ใช้ออกจากระบบ', 'ถ้าใช้บัญชีเดียวกันหลายธุรกิจ จะเข้าไม่ได้ทั้งหมดจนกว่าจะเปิดใช้งานคืน'),
      ]),
    );
  }
}

/// Older servers (no `/api/me/verify/*`): OTP sign-in proof and the fresh
/// token as the bearer (`POST /api/me/delete-account {confirm:'DELETE'}`).
class _LegacyDeleteAccount extends StatefulWidget {
  const _LegacyDeleteAccount();

  @override
  State<_LegacyDeleteAccount> createState() => _LegacyDeleteAccountState();
}

class _LegacyDeleteAccountState extends State<_LegacyDeleteAccount> {
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

  bool get _ready => _understood && _sent && DeleteAccountScreen.confirmWords.contains(_typed.text.trim()) && !_busy;

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
      messenger.showSnackBar(SnackBar(content: Text(tr(kAccountClosedNotice))));
      nav.popUntil((r) => r.isFirst);
      await config.signOutDeletedAccount(notice: kAccountClosedNotice);
    } catch (e) {
      if (mounted) setState(() => _error = e is OtpRefused ? e.message : formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = nxDangerColor(context);
    return ProfileSubPage(
      title: 'ลบบัญชี',
      maxWidth: 600,
      children: [
        const AccountClosureExplainer(),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const ValueKey('del-understand'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _understood,
          onChanged: _busy ? null : (v) => setState(() => _understood = v ?? false),
          title: Text(tr('ฉันเข้าใจและต้องการปิดบัญชีนี้')),
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
                    Text(tr('3. พิมพ์ "ลบบัญชี" เพื่อยืนยัน'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('del-type'),
                      controller: _typed,
                      enabled: !_busy,
                      decoration: profileInput(context, L10n.isEn ? 'DELETE' : 'ลบบัญชี', icon: NxI.textT),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const ValueKey('del-submit'),
                      onPressed: _ready ? _delete : null,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: danger, foregroundColor: Colors.white),
                      icon: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(NxI.userCog, size: 18),
                      label: Text(tr('ปิดบัญชีของฉัน')),
                    ),
                  ],
                ]),
        ),
        if (_error != null) ProfileErrorText(_error!, key: const ValueKey('del-error')),
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
    );
  }
}

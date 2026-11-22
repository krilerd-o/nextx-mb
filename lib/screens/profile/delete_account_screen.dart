import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/navigation/app_routes.dart';
import '../../services/api_client.dart';
import '../../widgets/fields/nx_field_chrome.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_logout.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/settings_tiles.dart';
import 'otp_proof.dart';
import 'profile_ui.dart';
import 'step_up.dart';

/// Shown on the login screen after the account was closed (older servers: close, not delete).
const kAccountClosedNotice = 'ปิดบัญชีแล้ว บัญชีนี้ใช้งานไม่ได้อีกจนกว่าผู้ดูแลระบบจะเปิดใช้งานให้';

/// Shown on the first screen after a permanent deletion.
const kAccountDeletedNotice = 'ลบบัญชีถาวรแล้ว ข้อมูลส่วนตัวของคุณถูกลบทั้งหมด';

/// "ลบบัญชีถาวร" — required by the App Store (5.1.1(v)) and Google Play.
///
/// 1) what is deleted and what stays (`GET /api/me/delete-account/preview`); the only owner of a business
///    must transfer ownership first and cannot go on; 2) "เข้าใจและต้องการลบ"; 3) type the confirm word;
/// 4) verify every channel the account has — SMS OTP and email OTP (password only when it has neither);
/// 5) `POST /api/me/delete-account {confirm:'DELETE', mode:'erase', verify_tokens}` → the server erases the
///    personal data → sign out here and land on the first (welcome) screen with a notice.
///
/// Servers without the preview endpoint cannot delete permanently: the web page is offered instead.
/// Servers without the step-up API keep the older OTP flow (closes the account).
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  /// Typed to confirm (Thai, or English for the English UI).
  static const confirmWords = {'ลบบัญชีถาวร', 'DELETE'};

  /// Older servers (close the account only).
  static const legacyConfirmWords = {'ลบบัญชี', 'DELETE'};

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _typed = TextEditingController();
  VerifyMethods? _methods;
  Map<String, dynamic>? _preview;
  bool _legacy = false;
  bool _noErase = false;
  Object? _loadError;
  bool _accepted = false;
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
    final api = context.read<AppConfig>().apiClient;
    try {
      final m = VerifyMethods.fromJson(await api.getVerifyMethods());
      Map<String, dynamic>? p;
      try {
        p = await api.getDeleteAccountPreview();
      } catch (e) {
        if (!isMissingEndpoint(e)) rethrow;
      }
      if (!mounted) return;
      setState(() {
        _methods = m;
        _preview = p;
        _noErase = p == null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isMissingEndpoint(e) ? _legacy = true : _loadError = e);
    }
  }

  List<Map<String, dynamic>> _list(String key) =>
      [for (final x in (_preview?[key] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];

  List<Map<String, dynamic>> get _soleOwner => _list('sole_owner');

  /// Channels to verify: every code channel the account has (email + SMS); the password only when it has neither.
  List<String> get _required {
    final m = _methods;
    if (m == null) return const [];
    final codes = m.codeChannels;
    if (codes.isNotEmpty) return codes;
    return m.password ? const ['password'] : const [];
  }

  bool get _typedOk => DeleteAccountScreen.confirmWords.contains(_typed.text.trim());
  bool get _allVerified => _required.isNotEmpty && _required.every(_tokens.containsKey);
  bool get _ready => _accepted && _typedOk && _allVerified && _soleOwner.isEmpty && !_busy;

  String get _webPage => '${context.read<AppConfig>().apiBaseUrl.replaceAll(RegExp(r'/+$'), '')}/account-deletion';

  void _resetProofs() {
    for (final c in [..._tokens.keys]) {
      _tokens.remove(c);
      _verifiers[c]?.currentState?.reset();
    }
  }

  Future<void> _submit() async {
    final config = context.read<AppConfig>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final router = GoRouter.maybeOf(context);
    setState(() {
      _busy = true;
      _error = null;
      _webOnly = false;
    });
    try {
      await config.apiClient.eraseMyAccount([for (final c in _required) _tokens[c]!]);
      HapticFeedback.heavyImpact();
      messenger.showSnackBar(SnackBar(content: Text(tr(kAccountDeletedNotice))));
      nav.popUntil((r) => r.isFirst);
      // The server erased the account and signed every session out: forget it here and start over.
      await config.signOutDeletedAccount(notice: kAccountDeletedNotice);
      router?.go(AppRoutes.welcome);
    } catch (e) {
      if (!mounted) return;
      final code = e is ApiEnvelopeException ? e.errorCode.toUpperCase() : '';
      if (code == 'SOLE_OWNER') {
        setState(() {
          _resetProofs();
          _error = (e as ApiEnvelopeException).message;
        });
        await _load();
      } else if (code == 'STEP_UP_REQUIRED') {
        setState(() {
          _resetProofs();
          final msg = (e as ApiEnvelopeException).message.trim();
          _error = msg.isNotEmpty ? msg : 'ต้องยืนยันตัวตนอีกครั้งก่อนลบบัญชี';
        });
      } else if (isMissingEndpoint(e)) {
        setState(() {
          _webOnly = true;
          _error = 'เซิร์ฟเวอร์นี้ยังไม่รองรับการลบบัญชีในแอป ขอลบได้จากหน้าเว็บ';
        });
      } else {
        setState(() {
          _resetProofs();
          _error = formatApiError(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _step(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(tr(text), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
      );

  @override
  Widget build(BuildContext context) {
    if (_legacy) return const _LegacyDeleteAccount();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final danger = nxDangerColor(context);
    final m = _methods;
    final req = _required;
    final word = L10n.isEn ? 'DELETE' : 'ลบบัญชีถาวร';
    final children = <Widget>[];
    if (m == null) {
      children.add(_loadError == null
          ? const NxSkeletonSettings(key: ValueKey('delete-account-skeleton'), groups: [3], trailing: NxSkelTrailing.chevron, padded: false)
          : NxSoftNote(
              icon: NxI.warningCircle,
              color: cs.error,
              text: formatApiError(_loadError!),
              action: TextButton(onPressed: _load, child: Text(tr('ลองใหม่'))),
            ));
    } else if (_noErase) {
      children.add(const NxSoftNote(
        key: ValueKey('del-no-erase'),
        icon: NxI.info,
        text: 'เซิร์ฟเวอร์นี้ยังไม่รองรับการลบบัญชีถาวรในแอป — ขอลบได้จากหน้าเว็บ',
      ));
      children.add(Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('del-web'),
          onPressed: () => launchUrl(Uri.parse(_webPage), mode: LaunchMode.externalApplication),
          icon: const Icon(NxI.arrowSquareOut, size: 18),
          label: Text(tr('เปิดหน้าขอลบบัญชี')),
        ),
      ));
    } else {
      children.add(AccountErasureExplainer(
        businesses: _list('businesses'),
        linkedSignIns: [for (final p in (_preview?['linked_sign_ins'] as List? ?? const [])) '$p'],
        devices: (_preview?['devices'] as num?)?.toInt() ?? 0,
      ));
      if (_soleOwner.isNotEmpty) {
        children.add(const SizedBox(height: 12));
        children.add(_SoleOwnerBlock(businesses: _soleOwner));
      } else if (!_accepted) {
        children.add(const SizedBox(height: 14));
        children.add(FilledButton.tonal(
          key: const ValueKey('del-accept'),
          onPressed: () => setState(() => _accepted = true),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(tr('เข้าใจและต้องการลบ')),
        ));
      } else {
        children.addAll([
          _step(theme, L10n.isEn ? '1. Type "DELETE" to confirm' : '1. พิมพ์ "ลบบัญชีถาวร" เพื่อยืนยัน'),
          TextField(
            key: const ValueKey('del-type'),
            controller: _typed,
            enabled: !_busy,
            decoration: NxFieldStyle.input(context, label: word, icon: NxI.textT),
          ),
        ]);
        final verify = <Widget>[
          _step(theme, req.length > 1 ? '2. ยืนยันตัวตนทาง SMS และอีเมล' : '2. ยืนยันตัวตน'),
        ];
        if (req.isEmpty) {
          verify.add(const NxSoftNote(
            key: ValueKey('del-no-method'),
            icon: NxI.warningCircle,
            text: 'บัญชีนี้ยังไม่มีอีเมล เบอร์มือถือ หรือรหัสผ่านสำหรับยืนยัน — ขอลบได้จากหน้าเว็บ',
          ));
        } else {
          for (final c in req) {
            verify.add(Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: StepUpVerifier(
                key: _verifiers.putIfAbsent(c, () => GlobalKey<StepUpVerifierState>()),
                channel: c,
                keyPrefix: 'del-$c',
                masked: m.masked(c),
                verified: _tokens.containsKey(c),
                enabled: !_busy && _typedOk,
                onVerified: (t) => setState(() {
                  _tokens[c] = t;
                  _error = null;
                }),
              ),
            ));
          }
          for (final c in const ['email', 'sms']) {
            if (!m.available(c)) {
              verify.add(Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '${tr(c == 'email' ? 'อีเมล' : 'SMS')}: ${tr(m.unavailableText(c))} · ${tr('ไม่ต้องยืนยันช่องทางนี้')}',
                  key: ValueKey('del-$c-unavailable'),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ));
            }
          }
        }
        children.add(AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _typedOk ? 1 : 0.45,
          child: IgnorePointer(ignoring: !_typedOk, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: verify)),
        ));
        children.addAll([
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('del-submit'),
            onPressed: _ready ? _submit : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: danger, foregroundColor: Colors.white),
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(NxI.trash, size: 18),
            label: Text(tr('ลบบัญชีถาวร')),
          ),
        ]);
      }
    }
    return ProfileSubPage(
      title: 'ลบบัญชีถาวร',
      maxWidth: 600,
      children: [
        ...children,
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

/// What permanent deletion removes, and what stays with each business.
class AccountErasureExplainer extends StatelessWidget {
  const AccountErasureExplainer({super.key, this.businesses = const [], this.linkedSignIns = const [], this.devices = 0});
  final List<Map<String, dynamic>> businesses;
  final List<String> linkedSignIns;
  final int devices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final danger = nxDangerColor(context);
    Widget point(IconData icon, Color color, String title, String body, {Key? key}) => Padding(
          key: key,
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
                Text(body, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4)),
              ]),
            ),
          ]),
        );
    const names = {'google': 'Google', 'line': 'LINE', 'apple': 'Apple'};
    final linked = linkedSignIns.map((p) => names[p] ?? p).join(', ');
    final bizNames = businesses.map((b) => '${b['name'] ?? ''}').where((s) => s.isNotEmpty).join(', ');
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
          Expanded(child: Text(tr('ลบบัญชีถาวร — กู้คืนไม่ได้'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: danger))),
        ]),
        point(NxI.userCog, danger, 'ข้อมูลส่วนตัวถูกลบทั้งหมด', tr('ชื่อ อีเมล เบอร์โทร ที่อยู่ รูปโปรไฟล์ ลายเซ็น และรหัสผ่าน')),
        point(
          NxI.lock,
          danger,
          'เข้าสู่ระบบไม่ได้อีก',
          [
            tr('ออกจากระบบทุกเครื่อง'),
            if (devices > 0) tr('ลบอุปกรณ์รับแจ้งเตือน $devices เครื่อง'),
            if (linked.isNotEmpty) '${tr('ยกเลิกการเชื่อม')} $linked',
          ].join(' · '),
          key: const ValueKey('del-explain-signin'),
        ),
        point(
          NxI.users,
          danger,
          'ออกจากทุกธุรกิจ',
          businesses.isEmpty ? tr('ยังไม่ได้อยู่ในธุรกิจใด') : '${tr('${businesses.length} ธุรกิจ')}: $bizNames',
          key: const ValueKey('del-explain-businesses'),
        ),
        point(NxI.database, cs.primary, 'ข้อมูลงานยังอยู่กับธุรกิจ', tr('ลูกค้า ใบเสนอราคา งาน และการลงเวลาที่คุณบันทึก ยังเป็นของธุรกิจ โดยแสดงเป็น "ผู้ใช้ที่ถูกลบ"')),
        point(NxI.info, cs.onSurfaceVariant, 'ใช้อีเมลหรือเบอร์เดิมสมัครใหม่ได้', tr('ถ้าต้องการลบข้อมูลการประชุมและบันทึกเสียงด้วย ให้ลบก่อนที่ โปรไฟล์ → ความเป็นส่วนตัวและ AI')),
      ]),
    );
  }
}

/// The only owner of a business must hand it over first.
class _SoleOwnerBlock extends StatelessWidget {
  const _SoleOwnerBlock({required this.businesses});
  final List<Map<String, dynamic>> businesses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: const ValueKey('del-sole-owner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(NxI.warningCircle, color: cs.error, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('โอนความเป็นเจ้าของก่อนลบบัญชี'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 6),
        Text(
          tr('คุณเป็นเจ้าของคนเดียวของธุรกิจด้านล่าง ให้โอนความเป็นเจ้าของให้สมาชิกคนอื่นก่อน (ตั้งค่าธุรกิจ → สมาชิก บนเว็บ) แล้วกลับมาลบบัญชีอีกครั้ง'),
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
        ),
        const SizedBox(height: 6),
        for (final b in businesses)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('• ${b['name'] ?? ''}', key: ValueKey('del-sole-${b['business_id']}'), style: theme.textTheme.bodyMedium),
          ),
      ]),
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

  bool get _ready => _understood && _sent && DeleteAccountScreen.legacyConfirmWords.contains(_typed.text.trim()) && !_busy;

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
                      decoration: NxFieldStyle.input(context, label: L10n.isEn ? 'DELETE' : 'ลบบัญชี', icon: NxI.textT),
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

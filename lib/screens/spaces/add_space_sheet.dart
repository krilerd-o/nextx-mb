import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/server_profile.dart';
import '../../core/spaces.dart';
import '../../services/api_client.dart';
import '../../widgets/fields/nx_field_chrome.dart';
import '../../widgets/nx_icons.dart';
import 'space_switcher.dart';
import '../auth/qr_login_scan_screen.dart';
import '../../core/nx_page_route.dart';

/// "เพิ่ม Space" in a window over the current screen: server, email and
/// password, signed in right here. The current Space stays as it is until the
/// sign-in works; then the new Space opens with the usual colour hand-off.
/// (No full login screen; wrong password / server errors stay in the window.)
Future<void> showAddSpaceSheet(BuildContext context, {String? baseUrl}) async {
  final config = context.read<AppConfig>();
  final host = context;
  final result = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider<AppConfig>.value(
      value: config,
      child: _AddSpaceSheet(initialServer: baseUrl ?? config.apiBaseUrl),
    ),
  );
  if (result == null || !host.mounted) return;
  if (result == _scan) {
    // Scan the web's login QR: the scanner adds (or opens) the Space itself.
    await nxPush<bool>(host, const QrLoginScanScreen(addSpace: true));
    return;
  }
  if (result is! _Added) return;
  final preview = Space(
    id: '',
    baseUrl: result.url,
    email: result.email,
    businessName: result.businessName,
  );
  await runSpaceTransition(
    host,
    preview,
    null,
    () => config.addSpaceWithLogin(
      baseUrl: result.url,
      data: result.data,
      email: result.email,
    ),
  );
}

/// Sheet result: open the QR scanner.
const _scan = 'scan';

class _Added {
  const _Added(this.url, this.email, this.data, this.businessName);
  final String url;
  final String email;
  final Map<String, dynamic> data;
  final String? businessName;
}

class _AddSpaceSheet extends StatefulWidget {
  const _AddSpaceSheet({required this.initialServer});
  final String initialServer;

  @override
  State<_AddSpaceSheet> createState() => _AddSpaceSheetState();
}

class _AddSpaceSheetState extends State<_AddSpaceSheet> {
  late final _server = TextEditingController(
    text: serverLabel(widget.initialServer),
  );
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _editServer = false;
  bool _byQr = false; // "สแกน QR" tab
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      HapticFeedback.heavyImpact();
      return setState(() => _error = 'กรอกอีเมลและรหัสผ่าน');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The field shows the host only; keep the full address (scheme, port) when unchanged.
      final typed = _server.text.trim();
      final server = typed == serverLabel(widget.initialServer)
          ? widget.initialServer
          : typed;
      final check = await verifyNextxServer(server);
      if (!check.ok) throw _Msg(check.message ?? 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้');
      final config = context.read<AppConfig>();
      if (config.spaces.any(
        (s) =>
            normalizeServerUrl(s.baseUrl) == check.url &&
            (s.email ?? '').toLowerCase() == email.toLowerCase(),
      )) {
        throw const _Msg('มีพื้นที่ทำงานของบัญชีนี้อยู่แล้ว');
      }
      // Sign in on a separate client: the current Space is untouched until this works.
      final api = ApiClient()..attachSession(baseUrl: check.url);
      final data = await api.login(
        email: email,
        password: _password.text,
        remember: true,
      );
      if ((data['token']?.toString() ?? '').isEmpty)
        throw ApiException(500, 'ไม่พบ token จากเซิร์ฟเวอร์');
      final biz = data['business'];
      HapticFeedback.mediumImpact();
      if (mounted)
        Navigator.pop(
          context,
          _Added(
            check.url,
            email,
            data,
            biz is Map ? biz['business_name']?.toString() : null,
          ),
        );
    } catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted)
        setState(() => _error = e is _Msg ? e.message : formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final recent = context.read<AppConfig>().recentServers;
    InputDecoration deco(
      String label,
      IconData icon, {
      Widget? suffix,
      String? hint,
    }) => NxFieldStyle.input(context, label: label, hint: hint, icon: icon, suffix: suffix);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        key: const ValueKey('add-space-sheet'),
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? cs.surfaceContainerHigh
              : cs.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(NxI.plus, color: cs.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('เพิ่มพื้นที่ทำงาน'),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            tr('บัญชีอื่นหรือโดเมนอื่น · พื้นที่ทำงานเดิมยังใช้ได้'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // How to add: email + password, or scan the web's login QR.
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      for (final (qr, label, icon) in [
                        (false, 'อีเมลและรหัสผ่าน', NxI.envelope),
                        (true, 'สแกน QR', NxI.qrCode),
                      ])
                        Expanded(
                          child: GestureDetector(
                            key: ValueKey(
                              qr
                                  ? 'add-space-mode-qr'
                                  : 'add-space-mode-password',
                            ),
                            onTap: () {
                              if (_byQr == qr) return;
                              HapticFeedback.selectionClick();
                              FocusScope.of(context).unfocus();
                              setState(() {
                                _byQr = qr;
                                _error = null;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _byQr == qr
                                    ? (theme.brightness == Brightness.dark
                                          ? cs.surfaceContainerHigh
                                          : cs.surface)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: _byQr == qr
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.08,
                                          ),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    icon,
                                    size: 16,
                                    color: _byQr == qr
                                        ? cs.primary
                                        : cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      tr(label),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelLarge?.copyWith(
                                        color: _byQr == qr
                                            ? cs.primary
                                            : cs.onSurfaceVariant,
                                        fontWeight: _byQr == qr
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (_byQr)
                  ..._qrPanel(theme, cs)
                else ...[
                  // Server: the current one by default, tap to change.
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 220),
                    crossFadeState: _editServer
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: InkWell(
                      key: const ValueKey('add-space-server'),
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() => _editServer = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              NxI.globe,
                              size: 20,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tr('เซิร์ฟเวอร์'),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    _server.text,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              tr('เปลี่ยน'),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: cs.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    secondChild: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          key: const ValueKey('add-space-server-field'),
                          controller: _server,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: deco(
                            'เซิร์ฟเวอร์',
                            NxI.globe,
                            hint: 'moainext.example.com',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        if (recent.length > 1) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final r in recent)
                                ActionChip(
                                  label: Text(serverLabel(r)),
                                  onPressed: () => setState(
                                    () => _server.text = serverLabel(r),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('add-space-email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: deco('อีเมล', NxI.envelope),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('add-space-password'),
                    controller: _password,
                    obscureText: !_show,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _busy ? null : _submit(),
                    decoration: deco(
                      'รหัสผ่าน',
                      NxI.password,
                      suffix: NxPasswordToggle(obscured: !_show, onToggle: () => setState(() => _show = !_show)),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: _error == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              children: [
                                Icon(
                                  NxI.warningCircle,
                                  size: 18,
                                  color: cs.error,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    tr(_error!),
                                    key: const ValueKey('add-space-error'),
                                    style: TextStyle(color: cs.error),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('add-space-submit'),
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(tr('เพิ่มและเปิดพื้นที่ทำงาน')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension on _AddSpaceSheetState {
  /// "สแกน QR": where to find the QR on the web, then the scanner.
  List<Widget> _qrPanel(ThemeData theme, ColorScheme cs) => [
    Container(
      key: const ValueKey('add-space-qr-panel'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(NxI.qrCode, color: cs.primary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('เพิ่มด้วย QR จากเว็บ'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    'บนเว็บ MOAI NEXT ของบัญชีที่ต้องการ กดรูปโปรไฟล์ → คิวอาร์โค้ดเข้าสู่ระบบ แล้วสแกน ไม่ต้องพิมพ์เซิร์ฟเวอร์ อีเมล หรือรหัสผ่าน',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 16),
    FilledButton.icon(
      key: const ValueKey('add-space-scan'),
      onPressed: () {
        HapticFeedback.selectionClick();
        Navigator.pop(context, _scan);
      },
      icon: const Icon(NxI.scanLine, size: 20),
      label: Text(tr('สแกน QR จากเว็บ')),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  ];
}

class _Msg implements Exception {
  const _Msg(this.message);
  final String message;
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/auth_errors.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_icons.dart';
import '../../core/i18n.dart';

/// Confirms linking a new sign-in method (OTP) or merging a Google account
/// with an existing NEXTX user — same as the web's /auth/link/confirm.
class LinkConfirmScreen extends StatefulWidget {
  const LinkConfirmScreen({super.key, required this.intentToken, this.google = false});

  final String intentToken;

  /// true → Google merge (`/google/merge/*`), false → `/link/*`.
  final bool google;

  @override
  State<LinkConfirmScreen> createState() => _LinkConfirmScreenState();
}

class _LinkConfirmScreenState extends State<LinkConfirmScreen> {
  Map<String, dynamic>? _preview;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AppConfig>().apiClient;
    try {
      final p = widget.google ? await api.googleMergePreview(widget.intentToken) : await api.linkPreview(widget.intentToken);
      if (mounted) setState(() => _preview = p);
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final config = context.read<AppConfig>();
    try {
      widget.google ? await config.confirmGoogleMerge(widget.intentToken) : await config.confirmLink(widget.intentToken);
      // Signed in: the router may already have replaced this screen.
      if (mounted) Navigator.of(context).maybePop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = authErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = _preview;
    final who = p?['display_name']?.toString() ?? '';
    final hint = p?['email_hint']?.toString() ?? p?['phone']?.toString() ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(tr('ยืนยันการเชื่อมบัญชี'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: CircleAvatar(
                radius: 36,
                backgroundColor: cs.primary.withValues(alpha: 0.12),
                child: Icon(NxI.link, size: 34, color: cs.primary),
              ),
            ),
            const SizedBox(height: 20),
            Text(tr('พบบัญชีเดิมในระบบ'), textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              tr(widget.google
                  ? 'อีเมล Google นี้ตรงกับบัญชีที่มีอยู่แล้ว ต้องการรวมเพื่อเข้าสู่ระบบด้วย Google ต่อจากนี้หรือไม่?'
                  : 'ต้องการเพิ่มวิธีเข้าสู่ระบบนี้ให้กับบัญชีเดิมหรือไม่?'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            if (p == null && _error == null) const Center(child: CircularProgressIndicator()),
            if (p != null)
              Card(
                child: ListTile(
                  leading: const Icon(NxI.user),
                  title: Text(tr(who.isEmpty ? 'บัญชีของคุณ' : who)),
                  subtitle: hint.isEmpty ? null : Text(tr(hint)),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(tr(_error!), textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
              ),
            const SizedBox(height: 24),
            NxHeroCta(label: 'ยืนยันและเข้าสู่ระบบ', busy: _busy, onPressed: p == null || _busy ? null : _confirm),
            TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: Text(tr('ยกเลิก'))),
          ],
        ),
      ),
    );
  }
}

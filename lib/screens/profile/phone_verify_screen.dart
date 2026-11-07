import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/auth_errors.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_icons.dart';
import '../../core/i18n.dart';

/// Bind / verify the account's mobile number with an SMS code
/// (`/api/me/phone/otp/request|verify`) — then "OTP SMS" sign-in works.
class PhoneVerifyScreen extends StatefulWidget {
  const PhoneVerifyScreen({super.key, this.initialPhone});

  final String? initialPhone;

  @override
  State<PhoneVerifyScreen> createState() => _PhoneVerifyScreenState();
}

class _PhoneVerifyScreenState extends State<PhoneVerifyScreen> {
  late final _phone = TextEditingController(text: widget.initialPhone ?? '');
  final _code = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final phone = _phone.text.trim();
    if (phone.isEmpty) return setState(() => _error = 'กรุณากรอกเบอร์มือถือ');
    if (_sent && _code.text.trim().isEmpty) return setState(() => _error = 'กรุณากรอกรหัส OTP');
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<AppConfig>().apiClient;
    try {
      if (!_sent) {
        final r = await api.requestPhoneBindOtp(phone);
        if (!mounted) return;
        setState(() {
          _sent = true;
          _info = r['ref']?.toString().isNotEmpty == true ? 'ส่งรหัสแล้ว (Ref: ${r['ref']})' : 'ส่งรหัส OTP ไปที่ $phone แล้ว';
        });
      } else {
        await api.verifyPhoneBindOtp(phone, _code.text.trim());
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ยืนยันเบอร์มือถือแล้ว'))));
        Navigator.of(context).pop(true);
        return;
      }
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    InputDecoration dec(String label, IconData icon) => InputDecoration(
          labelText: trn(label),
          prefixIcon: Icon(icon),
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        );
    return Scaffold(
      appBar: const NxAppHeader(title: 'ยืนยันเบอร์มือถือ'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(tr('ยืนยันเบอร์เพื่อเข้าสู่ระบบด้วย OTP SMS และรับการแจ้งเตือนทาง SMS'),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          TextField(
            controller: _phone,
            enabled: !_sent && !_busy,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: dec('เบอร์มือถือ', NxI.phone),
          ),
          if (_sent) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              decoration: dec('รหัส OTP', NxI.password),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy ? null : () => setState(() => _sent = false),
                child: Text(tr('เปลี่ยนเบอร์ / ขอรหัสใหม่')),
              ),
            ),
          ],
          if (_info != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr(_info!))),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr(_error!), style: TextStyle(color: theme.colorScheme.error))),
          const SizedBox(height: 24),
          NxHeroCta(label: _sent ? 'ยืนยัน' : 'ส่งรหัส OTP', busy: _busy, onPressed: _busy ? null : _go),
        ],
      ),
    );
  }
}

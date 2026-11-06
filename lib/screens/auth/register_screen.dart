import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/auth_errors.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_icons.dart';

/// Sign up (NEXTX `POST /api/auth/register`): with a serial/invite key the
/// account is created right away; without one it waits for admin approval.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.inviteToken});

  /// From a "join business" link — the account joins that business directly.
  final String? inviteToken;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _key = TextEditingController();
  final _business = TextEditingController();
  bool _hasKey = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  bool _pendingDone = false;

  bool get _invite => (widget.inviteToken ?? '').isNotEmpty;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm, _key, _business]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_form.currentState?.validate() != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pending = await context.read<AppConfig>().registerAccount(
            fullName: _name.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            serialKey: !_invite && _hasKey ? _key.text.trim() : null,
            businessName: _invite ? null : _business.text.trim(),
            inviteToken: widget.inviteToken,
          );
      if (!mounted) return;
      if (pending) {
        setState(() {
          _busy = false;
          _pendingDone = true;
        });
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = authErrorMessage(e);
        });
      }
    }
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (_pendingDone) {
      return Scaffold(
        appBar: AppBar(),
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(radius: 40, backgroundColor: cs.primary.withValues(alpha: 0.12), child: Icon(NxI.clockCountdown, size: 38, color: cs.primary)),
              const SizedBox(height: 20),
              Text('ส่งคำขอสมัครแล้ว', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('ผู้ดูแลระบบจะตรวจสอบและอนุมัติบัญชีของคุณ\nเมื่ออนุมัติแล้วจะได้รับอีเมลแจ้ง',
                  textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 28),
              NxHeroCta(label: 'กลับไปหน้าเข้าสู่ระบบ', onPressed: () => Navigator.of(context).pop(false)),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('สมัครสมาชิก')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text('สร้างบัญชี MOAI NEXT', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('มีรหัสเชิญ/ซีเรียลจากบริษัท ใช้งานได้ทันที ไม่มีรหัสจะรอผู้ดูแลอนุมัติ',
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 20),
              TextFormField(
                controller: _name,
                decoration: _dec('ชื่อ-นามสกุล', NxI.user),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'กรุณากรอกชื่อ' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: _dec('อีเมล', NxI.envelope),
                validator: (v) => (v == null || !v.contains('@')) ? 'อีเมลไม่ถูกต้อง' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                decoration: _dec('รหัสผ่าน', NxI.password).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                // Strength rules live on the server (authValidation.js) — its message is shown.
                validator: (v) => (v == null || v.isEmpty) ? 'กรุณากรอกรหัสผ่าน' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirm,
                obscureText: _obscure,
                decoration: _dec('ยืนยันรหัสผ่าน', NxI.password),
                validator: (v) => v != _password.text ? 'รหัสผ่านไม่ตรงกัน' : null,
              ),
              const SizedBox(height: 16),
              if (_invite)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    Icon(NxI.checkCircleFill, color: cs.primary),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('สมัครจากลิงก์เชิญ — เข้าธุรกิจได้ทันทีโดยไม่ต้องรออนุมัติ (ใช้อีเมลที่ได้รับคำเชิญ)')),
                  ]),
                ),
              if (!_invite) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('ฉันมีรหัสเชิญ / ซีเรียลคีย์'),
                value: _hasKey,
                onChanged: (v) => setState(() => _hasKey = v),
              ),
              if (_hasKey) ...[
                TextFormField(
                  controller: _key,
                  decoration: _dec('รหัสเชิญ / ซีเรียลคีย์', NxI.shieldCheck),
                  validator: (v) => _hasKey && (v == null || v.trim().isEmpty) ? 'กรุณากรอกรหัส' : null,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _business,
                decoration: _dec('ชื่อธุรกิจ (ถ้ามี)', NxI.buildings),
              ),
              ],
              if (_error != null)
                Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: cs.error))),
              const SizedBox(height: 24),
              NxHeroCta(label: 'สมัครสมาชิก', busy: _busy, onPressed: _busy ? null : _submit),
            ],
          ),
        ),
      ),
    );
  }
}

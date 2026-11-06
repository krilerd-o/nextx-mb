import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../widgets/fields/nx_field_chrome.dart';
import '../../widgets/nx_app_logo.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_surface_card.dart';
import '../crm/field_gallery_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'กรุณากรอกอีเมลและรหัสผ่าน');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AppConfig>().loginWithPassword(
            email: email,
            password: password,
          );
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NxAppLogo(size: 72),
              const SizedBox(height: 16),
              Text(
                'ยินดีต้อนรับ',
                style: theme.textTheme.headlineLarge?.copyWith(letterSpacing: -0.5),
              ),
              const SizedBox(height: 4),
              Text(
                'เข้าสู่ระบบด้วยอีเมลและรหัสผ่าน\n(LINE Login ยังไม่รองรับบนแอปมือถือ)',
                style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: NxSurfaceCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(NxI.clock, color: colorScheme.primary),
                          const SizedBox(height: 8),
                          Text('ลงเวลา', style: theme.textTheme.bodySmall),
                          Text('วันนี้', style: theme.textTheme.titleLarge),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: NxSurfaceCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(NxI.checkCircle, color: colorScheme.primary),
                          const SizedBox(height: 8),
                          Text('งานของฉัน', style: theme.textTheme.bodySmall),
                          Text('พร้อมใช้', style: theme.textTheme.titleLarge),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              NxSurfaceCard(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username, AutofillHints.email],
                      decoration: NxFieldStyle.decoration(context, label: 'อีเมล'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _loading ? null : _login(),
                      decoration: NxFieldStyle.decoration(context, label: 'รหัสผ่าน'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    NxHeroCta(
                      label: 'เข้าสู่ระบบ',
                      busy: _loading,
                      onPressed: _loading ? null : _login,
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () async {
                              final email = _email.text.trim();
                              if (email.isEmpty) {
                                setState(() => _error = 'กรอกอีเมลก่อนขอรีเซ็ต');
                                return;
                              }
                              try {
                                await context.read<AppConfig>().apiClient.forgotPassword(email);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('ถ้าอีเมลมีในระบบ จะได้รับลิงก์รีเซ็ต')),
                                  );
                                }
                              } catch (e) {
                                if (mounted) setState(() => _error = formatApiError(e));
                              }
                            },
                      child: Text(
                        'ลืมรหัสผ่าน',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (kDebugMode)
                TextButton(
                  onPressed: () {
                    nxPush<void>(context, const FieldGalleryScreen());
                  },
                  child: const Text('พรีวิว UI Type'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../services/app_lock.dart';
import '../../widgets/nx_app_logo.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_icons.dart';

/// Covers the app until fingerprint / face unlock succeeds.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    final ok = await AppLock.instance.unlock();
    if (mounted) {
      setState(() {
        _busy = false;
        _failed = !ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final session = context.watch<AppConfig>().session;
    return Material(
      color: cs.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(),
              const NxAppLogo(size: 72),
              const SizedBox(height: 20),
              Text('แอปถูกล็อก', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                [session.displayName, session.businessName].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              Icon(NxI.fingerprint, size: 64, color: cs.primary),
              if (_failed) ...[
                const SizedBox(height: 12),
                Text('ยืนยันตัวตนไม่สำเร็จ ลองอีกครั้ง', style: TextStyle(color: cs.error)),
              ],
              const Spacer(),
              NxHeroCta(label: 'ปลดล็อก', busy: _busy, onPressed: _busy ? null : _unlock),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        AppLock.instance.reset();
                        await context.read<AppConfig>().logout();
                      },
                child: const Text('ใช้รหัสผ่านแทน (ออกจากระบบ)'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

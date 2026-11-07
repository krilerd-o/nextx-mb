import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/app_version.dart';
import '../core/server_profile.dart';
import '../widgets/nx_app_logo.dart';
import '../widgets/nx_hero_cta.dart';
import '../widgets/nx_icons.dart';

/// Store link for this platform, if the server published one.
String? storeUrlFor(MobileServerInfo? info) {
  if (info == null) return null;
  final ios = !kIsWeb && Platform.isIOS;
  return ios ? (info.storeUrlIos ?? info.storeUrl) : info.storeUrl;
}

Future<void> openStore(MobileServerInfo? info) async {
  final url = storeUrlFor(info);
  final uri = url == null ? null : Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Shown instead of the app when the server's `min_version` is newer than this build.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = context.watch<AppConfig>();
    final info = config.serverInfo;
    final hasStore = storeUrlFor(info) != null;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(),
              const NxAppLogo(size: 72),
              const SizedBox(height: 24),
              Icon(NxI.arrowsClockwise, size: 40, color: cs.primary),
              const SizedBox(height: 16),
              Text('กรุณาอัปเดตแอป', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'เซิร์ฟเวอร์ ${serverLabel(config.apiBaseUrl)} ต้องใช้แอปเวอร์ชัน ${info?.minVersion ?? ''} ขึ้นไป\n'
                'เวอร์ชันในเครื่อง: ${AppVersion.value}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
              ),
              const Spacer(),
              if (hasStore) NxHeroCta(label: 'อัปเดตแอป', onPressed: () => openStore(info)),
              if (!hasStore)
                Text('ติดต่อผู้ดูแลระบบเพื่อรับแอปเวอร์ชันใหม่', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => config.refreshServerInfo(force: true),
                child: const Text('ตรวจสอบอีกครั้ง'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

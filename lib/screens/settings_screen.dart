import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/navigation/app_routes.dart';
import '../core/nx_breakpoint.dart';
import '../services/api_client.dart';
import '../widgets/nx_app_header.dart';
import '../widgets/nx_app_logo.dart';
import '../widgets/nx_surface_card.dart';
import '../widgets/nx_icons.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Keep in sync with `version:` in pubspec.yaml (or override with --dart-define=APP_VERSION=...).
  static const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.2.0+2');

  /// Release builds lock the API endpoint; QA builds can re-enable with
  /// `--dart-define=ALLOW_API_URL_EDIT=true`.
  static const bool _allowApiUrlEditInRelease = bool.fromEnvironment('ALLOW_API_URL_EDIT');
  static bool get canEditApiUrl => !kReleaseMode || _allowApiUrlEditInRelease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = context.watch<AppConfig>();

    return Scaffold(
      appBar: const NxAppHeader.hub(),
      body: ListView(
        padding: NxBreakpoint.of(context).scrollPadding(context, inShell: true),
        children: [
          Text(
            'About',
            style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          const NxSurfaceCard(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ListTile(
              leading: NxAppLogo(size: 40),
              title: Text('MOAI NEXT Mobile'),
              subtitle: Text('Version $appVersion'),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'API',
            style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          NxSurfaceCard(
            onTap: canEditApiUrl ? () => _showEditApiUrlDialog(context, config) : null,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ListTile(
              leading: Icon(NxI.link, color: colorScheme.primary),
              title: const Text('Base URL'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(config.apiBaseUrl, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 2),
                  Text(
                    'ค่าเริ่มต้นคือเซิร์ฟเวอร์เว็บ MOAINEXT',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              trailing: canEditApiUrl ? const Icon(NxI.pencilSimple) : null,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Appearance',
            style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          NxSurfaceCard(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(NxI.palette, color: colorScheme.primary),
                  title: const Text('Theme'),
                  subtitle: Text(_themeModeLabel(config.themeMode)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(NxI.moon)),
                      ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(NxI.sun)),
                      ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(NxI.deviceMobile)),
                    ],
                    selected: {config.themeMode},
                    onSelectionChanged: (Set<ThemeMode> selected) {
                      config.setThemeMode(selected.first);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'โปรไฟล์',
            style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          NxSurfaceCard(
            onTap: () => context.push(AppRoutes.profile),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ListTile(
              leading: Icon(NxI.user, color: colorScheme.primary),
              title: const Text('โปรไฟล์และความปลอดภัย'),
              subtitle: const Text('ภาษา, รูปแบบวันที่, accent, เปลี่ยนรหัสผ่าน'),
              trailing: const Icon(NxI.caretRight),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'บัญชี',
            style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          NxSurfaceCard(
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('ออกจากระบบ?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ออก')),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await context.read<AppConfig>().logout();
              }
            },
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ListTile(
              leading: Icon(NxI.signOut, color: colorScheme.error),
              title: Text('ออกจากระบบ', style: TextStyle(color: colorScheme.error)),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Shared DB • PostgreSQL • MongoDB • Node.js',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  static String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.system:
        return 'System';
    }
  }

  static Future<void> _showEditApiUrlDialog(BuildContext context, AppConfig config) async {
    final controller = TextEditingController(text: config.apiBaseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('API Base URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: kDefaultApiBaseUrl,
          ),
          autofocus: true,
          keyboardType: TextInputType.url,
          onSubmitted: (_) => Navigator.pop(ctx, controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await config.setApiBaseUrl(result);
    }
  }
}

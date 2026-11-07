import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_surface_card.dart';

/// Devices signed in to this Space. The device list / remote sign-out needs
/// server feature `device_sessions`; without it only "this device" is shown.
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    final theme = Theme.of(context);
    final sp = config.activeSpace;
    return NxScrollScaffold(
      header: const NxAppHeader(title: 'อุปกรณ์ที่เข้าใช้งาน'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NxSurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(NxI.deviceMobile),
              title: const Text('เครื่องนี้'),
              subtitle: Text([config.devicePlatform, if (sp != null) sp.host].join(' · ')),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('ออกจากระบบเครื่องนี้?'),
                  content: Text('ออกจาก ${sp?.title ?? 'Space นี้'} บนเครื่องนี้ (Space อื่นยังใช้งานได้)'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ออกจากระบบ')),
                  ],
                ),
              );
              if (ok == true) await config.logout();
            },
            icon: const Icon(NxI.signOut),
            label: const Text('ออกจากระบบเครื่องนี้'),
          ),
          const SizedBox(height: 12),
          Text(
            'การดูและออกจากระบบอุปกรณ์อื่น ต้องใช้ระบบ MOAI NEXT เวอร์ชันที่รองรับการจัดการอุปกรณ์',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

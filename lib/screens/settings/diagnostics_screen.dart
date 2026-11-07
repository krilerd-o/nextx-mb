import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_config.dart';
import '../../core/app_version.dart';
import '../../core/error_reporting.dart';
import '../../core/server_profile.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';

/// Plain-text report a tester can paste into chat / email.
String buildDiagnosticsReport(AppConfig config, List<String> errors) {
  final s = config.session;
  final lines = <String>[
    'MOAI NEXT Mobile ${AppVersion.value}',
    'อุปกรณ์: ${kIsWeb ? 'web' : defaultTargetPlatform.name}',
    'เซิร์ฟเวอร์: ${serverLabel(config.apiBaseUrl)}',
    'ผู้ใช้: ${s.email ?? '-'} (id ${s.userId ?? '-'})',
    'ธุรกิจ: ${s.businessName ?? '-'} (id ${s.businessId ?? '-'})',
    'Package: ${(s.packageCode ?? '').isEmpty ? '-' : s.packageCode}',
    'สิทธิ์: ${s.isSuperadmin ? 'superadmin' : (s.businessRole ?? '-')} · เมนู ${s.menuKeys?.length ?? 0} รายการ',
    'แท็บล่าง: ${config.shellTabs.join(', ')}',
    'เวลา: ${DateTime.now().toIso8601String()}',
    '',
    'ปัญหาล่าสุด (${errors.length}):',
    if (errors.isEmpty) '- ไม่มี',
    for (final e in errors.reversed) '- $e',
  ];
  return lines.join('\n');
}

/// Settings → บันทึกปัญหา: recent errors + device info, copy/share for testers.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = context.watch<AppConfig>();
    final errors = List.of(ErrorReporting.recent);
    final report = buildDiagnosticsReport(config, errors);
    return NxScrollScaffold(
      header: NxAppHeader(
        title: 'บันทึกปัญหา',
        actions: [
          IconButton(
            tooltip: 'ล้างบันทึก',
            icon: const Icon(NxI.trash),
            onPressed: errors.isEmpty
                ? null
                : () async {
                    await ErrorReporting.clear();
                    if (mounted) setState(() {});
                  },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('ส่งข้อมูลนี้ให้ทีมพัฒนาเมื่อพบปัญหา ช่วยให้แก้ได้เร็วขึ้น', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(NxI.shareNetwork),
                  label: const Text('แชร์'),
                  onPressed: () => Share.share(report, subject: 'MOAI NEXT Mobile – บันทึกปัญหา'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(NxI.clipboard),
                  label: const Text('คัดลอก'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: report));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('คัดลอกแล้ว')));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                report,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/hub_selection.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_step_header.dart';

/// Step: choose the business (skipped automatically when there is only one).
class BusinessHubScreen extends StatefulWidget {
  const BusinessHubScreen({super.key});

  @override
  State<BusinessHubScreen> createState() => _BusinessHubScreenState();
}

class _BusinessHubScreenState extends State<BusinessHubScreen> {
  List<Map<String, dynamic>>? _list;
  Object? _error;
  String? _choosing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _list = null;
    });
    try {
      final all = await context.read<AppConfig>().apiClient.getBusinesses();
      final list = visibleBusinesses(all);
      if (!mounted) return;
      setState(() => _list = list);
      if (list.length == 1 && !context.read<AppConfig>().manualBusinessPick) await _choose(list.first);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _choose(Map<String, dynamic> b) async {
    final id = b['id']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() => _choosing = id);
    await context.read<AppConfig>().selectBusiness(
          businessId: id,
          businessName: b['business_name']?.toString() ?? 'ธุรกิจ',
        );
    if (mounted) setState(() => _choosing = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = context.watch<AppConfig>();
    final list = _list;
    final def = list == null ? null : defaultBusiness(list);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            NxStepHeader(step: 1, total: 4, onBack: () => config.logout()),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                  children: [
                    Text('เลือกธุรกิจ', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      'สวัสดี ${config.session.displayName ?? ''}\nเลือกธุรกิจที่ต้องการทำงานวันนี้',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    if (_error != null) ...[
                      Text(formatApiError(_error!), textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
                      TextButton(onPressed: _load, child: const Text('ลองใหม่')),
                    ] else if (list == null)
                      const NxSkeletonList(rows: 3)
                    else if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('บัญชีนี้ยังไม่มีธุรกิจที่เข้าถึงได้\nติดต่อผู้ดูแลระบบให้เชิญเข้าธุรกิจ',
                            textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                      )
                    else
                      for (final b in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: NxChoiceCard(
                            icon: NxI.buildings,
                            title: b['business_name']?.toString() ?? 'ธุรกิจ',
                            subtitle: [
                              if ((b['business_code']?.toString() ?? '').isNotEmpty) b['business_code'].toString(),
                              if (b['role'] != null) _roleLabel(b['role'].toString()),
                              if (identical(b, def)) 'ค่าเริ่มต้น',
                            ].join(' · '),
                            selected: _choosing == b['id']?.toString(),
                            onTap: _choosing != null ? null : () => _choose(b),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _roleLabel(String r) => switch (r) {
        'owner' => 'เจ้าของ',
        'admin' => 'แอดมิน',
        'member' => 'สมาชิก',
        _ => r,
      };
}

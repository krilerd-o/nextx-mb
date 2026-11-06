import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/server_profile.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_step_header.dart';

/// "เชื่อมต่อระบบ" — any NEXTX server, verified via /api/health signature.
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  late final TextEditingController _url = TextEditingController(
    text: serverLabel(context.read<AppConfig>().pendingInvite?.server ?? context.read<AppConfig>().apiBaseUrl),
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _connect([String? value]) async {
    final input = (value ?? _url.text).trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await verifyNextxServer(input);
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _busy = false;
        _error = result.message;
      });
      return;
    }
    await context.read<AppConfig>().selectServer(result.url);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.maintenance) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('เซิร์ฟเวอร์อยู่ระหว่างปรับปรุง บางฟังก์ชันอาจใช้ไม่ได้')));
    }
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = context.watch<AppConfig>();
    final recent = config.recentServers.where((u) => serverLabel(u) != serverLabel(kDefaultApiBaseUrl)).toList();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            NxStepHeader(step: 1, total: 2, onBack: () => context.go(AppRoutes.welcome)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(22)),
                      child: Icon(NxI.globe, size: 36, color: cs.primary),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('เชื่อมต่อระบบของคุณ',
                      textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    'ใช้เซิร์ฟเวอร์ MOAI NEXT ของธุรกิจคุณ\nถ้าไม่แน่ใจ ใช้ค่าเริ่มต้นได้เลย',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  NxChoiceCard(
                    title: 'MOAI NEXT (ค่าเริ่มต้น)',
                    subtitle: serverLabel(kDefaultApiBaseUrl),
                    icon: NxI.cloud,
                    selected: serverLabel(_url.text) == serverLabel(kDefaultApiBaseUrl),
                    onTap: _busy ? null : () => setState(() => _url.text = serverLabel(kDefaultApiBaseUrl)),
                  ),
                  for (final u in recent) ...[
                    const SizedBox(height: 10),
                    NxChoiceCard(
                      title: serverLabel(u),
                      subtitle: 'ใช้ล่าสุด',
                      icon: NxI.hardDrives,
                      selected: serverLabel(_url.text) == serverLabel(u),
                      onTap: _busy ? null : () => setState(() => _url.text = serverLabel(u)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  TextField(
                    controller: _url,
                    enabled: !_busy,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textInputAction: TextInputAction.go,
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _connect(),
                    decoration: InputDecoration(
                      labelText: 'หรือใส่ที่อยู่เซิร์ฟเวอร์อื่น',
                      hintText: 'crm.yourcompany.com',
                      prefixIcon: const Icon(NxI.link),
                      filled: true,
                      errorText: _error,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(NxI.shieldCheck, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('แอปตรวจสอบก่อนว่าเป็นระบบ MOAI NEXT จริง',
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: NxHeroCta(label: 'เชื่อมต่อ', busy: _busy, onPressed: _busy ? null : () => _connect()),
            ),
          ],
        ),
      ),
    );
  }
}

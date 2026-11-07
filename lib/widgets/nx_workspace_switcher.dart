import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/hub_selection.dart';
import '../services/api_client.dart';
import 'nx_icons.dart';

/// "ธุรกิจ · Package" chip; tap to switch package (or business) in place.
class NxWorkspaceSwitcher extends StatelessWidget {
  const NxWorkspaceSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = context.select((AppConfig c) => c.session);
    final pkg = (s.packageCode ?? '').isEmpty ? null : s.packageCode!.toUpperCase().replaceAll('_', ' ');
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => const _SwitcherSheet(),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(NxI.buildings, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  [s.businessName ?? 'ธุรกิจ', ?pkg].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 4),
              Icon(NxI.caretDown, size: 14, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitcherSheet extends StatefulWidget {
  const _SwitcherSheet();

  @override
  State<_SwitcherSheet> createState() => _SwitcherSheetState();
}

class _SwitcherSheetState extends State<_SwitcherSheet> {
  List<Map<String, dynamic>>? _packages;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppConfig>();
    config.apiClient.getPackagesFor(config.session.businessId ?? '').then((all) {
      if (mounted) setState(() => _packages = visiblePackages(all));
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = context.watch<AppConfig>();
    final current = config.session.packageCode;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(config.session.businessName ?? 'ธุรกิจ', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('สลับ Package — เมนูจะเปลี่ยนตาม Package และสิทธิ์', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            if (_error != null) Text(formatApiError(_error!), style: TextStyle(color: theme.colorScheme.error)),
            if (_packages == null && _error == null) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            for (final p in _packages ?? const <Map<String, dynamic>>[])
              ListTile(
                leading: Icon(p['code']?.toString() == current ? NxI.radioOn : NxI.radioOff),
                title: Text(p['name']?.toString() ?? p['code']?.toString() ?? 'Package'),
                subtitle: (p['description']?.toString() ?? '').isEmpty ? null : Text(p['description'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                enabled: !_busy,
                onTap: p['code']?.toString() == current
                    ? () => Navigator.pop(context)
                    : () async {
                        setState(() => _busy = true);
                        final nav = Navigator.of(context);
                        await config.selectPackage(code: p['code']?.toString() ?? '', packageId: p['id']?.toString());
                        nav.pop();
                      },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(NxI.buildings),
              title: const Text('เปลี่ยนธุรกิจ'),
              enabled: !_busy,
              onTap: () {
                Navigator.pop(context);
                config.clearBusiness();
              },
            ),
          ],
        ),
      ),
    );
  }
}

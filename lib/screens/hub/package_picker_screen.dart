import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/hub_selection.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_step_header.dart';
import '../../core/i18n.dart';

/// Friendly names for the standard NEXTX packages (API names win when present).
const kPackageHints = <String, (String, IconData)>{
  'next_x': ('ทุกเมนูของ NEXTX', NxI.squaresFour),
  'next_t': ('ทีมและงาน: Workspace แชท ปฏิทิน เคส', NxI.kanban),
  'next_s': ('งานขาย: ผู้มุ่งหวัง ดีล ใบเสนอราคา ลูกค้า', NxI.handshake),
  'next_c': ('สื่อสาร: Omni Chat และเมล', NxI.chatCircle),
  'next_o': ('สินค้าและบริการ', NxI.package),
  'next_h': ('HR: ลงเวลา การลา พนักงาน', NxI.briefcase),
};

Color? _hexColor(String? hex) {
  final h = (hex ?? '').replaceAll('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// Step: choose the package (web Hub). Auto-enters the last/default/only one
/// unless [manual] (switching from inside the app).
class PackagePickerScreen extends StatefulWidget {
  const PackagePickerScreen({super.key, this.manual = false});

  final bool manual;

  @override
  State<PackagePickerScreen> createState() => _PackagePickerScreenState();
}

class _PackagePickerScreenState extends State<PackagePickerScreen> {
  List<Map<String, dynamic>>? _packages;
  Object? _error;
  String? _selected;
  bool _setDefault = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = context.read<AppConfig>();
    final bid = config.session.businessId ?? '';
    setState(() {
      _error = null;
      _packages = null;
    });
    try {
      final all = await config.apiClient.getPackagesFor(bid);
      final list = visiblePackages(all);
      if (!mounted) return;
      if (list.isEmpty) {
        // Business without packages: menus come from the role only.
        await config.selectPackage(code: '');
        return;
      }
      Map<String, dynamic>? business;
      try {
        final bs = await config.apiClient.getBusinesses();
        business = bs.where((b) => b['id']?.toString() == bid).firstOrNull;
      } catch (_) {}
      final last = await config.lastPackageFor(bid);
      final auto = autoPackage(
        list,
        lastCode: last,
        userDefaultId: business?['user_default_package_id']?.toString(),
        businessDefaultId: business?['default_package_id']?.toString(),
      );
      if (!mounted) return;
      setState(() {
        _packages = list;
        _selected = auto?['code']?.toString() ?? config.session.packageCode;
      });
      if (!widget.manual && !config.manualPackagePick && auto != null) await _enter(auto);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _enter(Map<String, dynamic> p) async {
    setState(() => _busy = true);
    await context.read<AppConfig>().selectPackage(
          code: p['code']?.toString() ?? '',
          packageId: p['id']?.toString(),
          setDefault: _setDefault,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (widget.manual && Navigator.of(context).canPop()) Navigator.of(context).pop(true);
  }

  // System back does the same as the header's back (instead of closing the app).
  @override
  Widget build(BuildContext context) => PopScope(
        canPop: widget.manual,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) context.read<AppConfig>().clearBusiness();
        },
        child: _buildPage(context),
      );


  Widget _buildPage(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = context.watch<AppConfig>();
    final list = _packages;
    final chosen = list?.where((p) => p['code']?.toString() == _selected).firstOrNull;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            NxStepHeader(
              step: 2,
              total: 4,
              onBack: widget.manual ? () => Navigator.of(context).maybePop() : () => config.clearBusiness(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                children: [
                  Text(tr('เลือกแพ็กเกจ'), textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    tr('${config.session.businessName ?? ''}\nเมนูที่เห็นจะเป็นไปตามแพ็กเกจและสิทธิ์ของคุณ'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  if (_error != null) ...[
                    Text(tr(formatApiError(_error!)), textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
                    TextButton(onPressed: _load, child: Text(tr('ลองใหม่'))),
                  ] else if (list == null)
                    const NxSkeletonList(rows: 3)
                  else ...[
                    for (final p in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: NxChoiceCard(
                          icon: kPackageHints[p['code']]?.$2 ?? NxI.package,
                          color: _hexColor(p['color']?.toString()),
                          title: p['name']?.toString() ?? p['code']?.toString() ?? 'แพ็กเกจ',
                          subtitle: (p['description']?.toString().trim().isNotEmpty == true)
                              ? p['description'].toString()
                              : (kPackageHints[p['code']]?.$1 ?? p['name_en']?.toString() ?? ''),
                          selected: _selected == p['code']?.toString(),
                          onTap: _busy ? null : () => setState(() => _selected = p['code']?.toString()),
                        ),
                      ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _setDefault,
                      onChanged: (v) => setState(() => _setDefault = v ?? false),
                      title: Text(tr('ใช้แพ็กเกจนี้เป็นค่าเริ่มต้น')),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: NxHeroCta(label: 'เข้าใช้งาน', busy: _busy, onPressed: chosen == null || _busy ? null : () => _enter(chosen)),
            ),
          ],
        ),
      ),
    );
  }
}

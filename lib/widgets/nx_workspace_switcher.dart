import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/hub_selection.dart';
import '../services/api_client.dart';
import 'nx_icons.dart';
import '../screens/spaces/space_switcher.dart' show runColorHandOff;
import '../core/i18n.dart';

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
        onTap: () {
          HapticFeedback.selectionClick();
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
            builder: (_) => _SwitcherSheet(host: context),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(NxI.buildings, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  tr([s.businessName ?? 'ธุรกิจ', ?pkg].join(' · ')),
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
  const _SwitcherSheet({required this.host});

  /// The page under the sheet: the colour hand-off plays over it.
  final BuildContext host;

  @override
  State<_SwitcherSheet> createState() => _SwitcherSheetState();
}

/// `#6366f1` → Color (package colour from NEXTX), or null.
Color? _hex(Object? v) {
  final s = v?.toString().replaceAll('#', '').trim() ?? '';
  if (s.length != 6) return null;
  final n = int.tryParse(s, radix: 16);
  return n == null ? null : Color(0xFF000000 | n);
}

class _SwitcherSheetState extends State<_SwitcherSheet> {
  List<Map<String, dynamic>>? _packages;
  Object? _error;
  String? _switching; // package code being switched to

  /// Business whose packages are listed (null = the current one). Changing
  /// business happens right here: the current business stays in use until a
  /// new business + package is picked, and back simply returns.
  String? _bizId;
  String? _bizName;
  bool _pickBusiness = false;
  List<Map<String, dynamic>>? _businesses;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final config = context.read<AppConfig>();
    final bid = _bizId ?? config.session.businessId ?? '';
    setState(() => _error = null);
    config.apiClient
        .getPackagesFor(bid)
        .then((all) {
          if (!mounted || bid != (_bizId ?? config.session.businessId ?? '')) return;
          final list = visiblePackages(all);
          setState(() => _packages = list);
          // Another business with a single package: switch straight away.
          if (_bizId != null && list.length == 1) {
            _switch(list.first, null, _hex(list.first['color']) ?? Theme.of(context).colorScheme.primary);
          }
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = e);
        });
  }

  void _openBusinesses() {
    HapticFeedback.selectionClick();
    setState(() {
      _pickBusiness = true;
      _error = null;
    });
    if (_businesses != null) return;
    context
        .read<AppConfig>()
        .apiClient
        .getBusinesses()
        .then((all) {
          if (mounted) setState(() => _businesses = visibleBusinesses(all));
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = e);
        });
  }

  void _chooseBusiness(Map<String, dynamic> b) {
    final config = context.read<AppConfig>();
    final id = b['id']?.toString() ?? '';
    if (id.isEmpty) return;
    HapticFeedback.selectionClick();
    final isCurrent = id == config.session.businessId;
    setState(() {
      _pickBusiness = false;
      _bizId = isCurrent ? null : id;
      _bizName = isCurrent ? null : (b['business_name']?.toString() ?? 'ธุรกิจ');
      _packages = null;
    });
    _load();
  }

  List<Widget> _businessList(ThemeData theme, ColorScheme cs, String? currentId) {
    final list = _businesses;
    return [
      const SizedBox(height: 18),
      Text(tr('เลือกธุรกิจ'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(tr(formatApiError(_error!)), style: TextStyle(color: cs.error)),
              ),
              TextButton(
                onPressed: () {
                  _businesses = null;
                  _openBusinesses();
                },
                child: Text(tr('ลองใหม่')),
              ),
            ],
          ),
        )
      else if (list == null)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        )
      else
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final b in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: b['id']?.toString() == currentId
                          ? cs.primary.withValues(alpha: 0.10)
                          : cs.surfaceContainerHighest.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        key: ValueKey('biz-${b['id']}'),
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _chooseBusiness(b),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Icon(NxI.buildings, color: cs.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tr(b['business_name']?.toString() ?? 'ธุรกิจ'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    if ((b['business_code']?.toString() ?? '').isNotEmpty)
                                      Text(
                                        b['business_code'].toString(),
                                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                      ),
                                  ],
                                ),
                              ),
                              if (b['id']?.toString() == currentId)
                                Icon(NxI.check, color: cs.primary)
                              else
                                Icon(NxI.caretRight, size: 18, color: cs.outline),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
    ];
  }

  void _back() {
    HapticFeedback.selectionClick();
    if (_pickBusiness) {
      setState(() => _pickBusiness = false);
      return;
    }
    // Viewing another business's packages → back to the business list.
    setState(() {
      _bizId = null;
      _bizName = null;
      _packages = null;
      _pickBusiness = true;
    });
    _load();
  }

  Future<void> _switch(Map<String, dynamic> p, Rect? from, Color color) async {
    final config = context.read<AppConfig>();
    final code = p['code']?.toString() ?? '';
    final name = p['name']?.toString() ?? code;
    HapticFeedback.mediumImpact();
    setState(() => _switching = code);
    // Let the chosen card show it is picked before the hand-off starts.
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    final host = widget.host;
    Navigator.pop(context);
    if (!host.mounted) return;
    await runColorHandOff(
      host,
      color: color,
      badge: name.characters.take(2).toString().toUpperCase(),
      title: tr('กำลังเปลี่ยนเป็น $name'),
      subtitle: _bizName ?? config.session.businessName ?? '',
      origin: from,
      action: () async {
        final otherBiz = _bizId;
        if (otherBiz != null) {
          // New business and its package in one go — never an empty session.
          await config.selectBusiness(businessId: otherBiz, businessName: _bizName ?? 'ธุรกิจ', packageCode: code);
        }
        await config.selectPackage(code: code, packageId: p['id']?.toString());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = context.watch<AppConfig>();
    final s = config.session;
    final current = _bizId == null ? s.packageCode : null;
    final biz = _bizName ?? s.businessName ?? 'ธุรกิจ';
    final pkgs = _packages ?? const <Map<String, dynamic>>[];
    final currentName =
        pkgs.where((p) => p['code']?.toString() == current).map((p) => p['name']?.toString()).firstOrNull ??
        (current ?? '').toUpperCase().replaceAll('_', ' ');

    Widget card(Map<String, dynamic> p, int index) {
      final code = p['code']?.toString() ?? '';
      final sel = code == current;
      final busy = _switching == code;
      final color = _hex(p['color']) ?? cs.primary;
      final name = tr(p['name']?.toString() ?? code);
      final desc = p['description']?.toString() ?? '';
      final menus = (p['menu_keys'] is List) ? (p['menu_keys'] as List).length : 0;
      return TweenAnimationBuilder<double>(
        key: ValueKey('pkg-$code'),
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 260 + 60 * index),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Builder(
            builder: (c) => AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: busy ? 0.97 : 1,
              child: Material(
                color: sel || busy
                    ? Color.alphaBlend(color.withValues(alpha: 0.10), cs.surface)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: sel || busy ? color : Colors.transparent, width: 1.6),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _switching != null
                      ? null
                      : sel
                      ? () => Navigator.pop(context)
                      : () {
                          final box = c.findRenderObject() as RenderBox?;
                          _switch(p, box == null ? null : box.localToGlobal(Offset.zero) & box.size, color);
                        },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: [color, Color.lerp(color, Colors.white, 0.25)!],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Text(
                            name.characters.take(2).toString().toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                              if (desc.isNotEmpty)
                                Text(
                                  tr(desc),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              if (menus > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    tr('$menus เมนู'),
                                    style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
                          child: busy
                              ? SizedBox(
                                  key: const ValueKey('busy'),
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.4, color: color),
                                )
                              : sel
                              ? Container(
                                  key: const ValueKey('sel'),
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                  child: const Icon(NxI.check, size: 16, color: Colors.white),
                                )
                              : Icon(NxI.caretRight, key: const ValueKey('go'), size: 18, color: cs.outline),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('pkg-sheet'),
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? cs.surfaceContainerHigh : cs.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 30, offset: const Offset(0, 10))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            // Business: logo, name, current package, and "change business".
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                  child: Icon(NxI.buildings, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(biz),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (currentName.isNotEmpty)
                        Text(tr('ใช้อยู่: $currentName'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (_pickBusiness || _bizId != null)
                  TextButton.icon(
                    key: const ValueKey('pkg-back'),
                    onPressed: _switching != null ? null : _back,
                    style: TextButton.styleFrom(backgroundColor: cs.surfaceContainerHighest, shape: const StadiumBorder()),
                    icon: const Icon(NxI.arrowLeft, size: 16),
                    label: Text(tr('กลับ')),
                  )
                else
                  TextButton.icon(
                    key: const ValueKey('pkg-change-business'),
                    onPressed: _switching != null ? null : _openBusinesses,
                    style: TextButton.styleFrom(backgroundColor: cs.surfaceContainerHighest, shape: const StadiumBorder()),
                    icon: const Icon(NxI.arrowsLeftRight, size: 16),
                    label: Text(tr('เปลี่ยนธุรกิจ')),
                  ),
              ],
            ),
            if (_pickBusiness)
              ..._businessList(theme, cs, s.businessId)
            else ...[
              const SizedBox(height: 18),
              Text(tr('เลือก Package'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 10),
                child: Text(
                  tr('เมนูจะเปลี่ยนตาม Package และสิทธิ์ของคุณ'),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(tr(formatApiError(_error!)), style: TextStyle(color: cs.error)),
                      ),
                      TextButton(onPressed: _load, child: Text(tr('ลองใหม่'))),
                    ],
                  ),
                ),
              if (_packages == null && _error == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              Flexible(
                child: SingleChildScrollView(child: Column(children: [for (var i = 0; i < pkgs.length; i++) card(pkgs[i], i)])),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

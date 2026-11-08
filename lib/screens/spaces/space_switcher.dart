import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/spaces.dart';
import '../../services/unread_service.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_overlay_panel.dart';
import 'add_space_sheet.dart';

/// Rounded-square Space logo (initials on the Space colour).
class SpaceAvatar extends StatelessWidget {
  const SpaceAvatar({super.key, required this.space, this.size = 48, this.selected = false, this.badge = 0});

  final Space space;
  final double size;
  final bool selected;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      width: size,
      height: size,
      padding: EdgeInsets.all(selected ? 3 : 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: selected ? cs.onSurface : Colors.transparent, width: 2),
      ),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.24),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [space.color, Color.lerp(space.color, Colors.black, 0.18)!]),
        ),
        child: Text(
          tr(space.initials),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.34),
        ),
      ),
    );
    if (badge <= 0) return tile;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        tile,
        Positioned(
          top: -6,
          right: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            constraints: const BoxConstraints(minWidth: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: cs.surface, width: 2),
            ),
            child: Text(
              tr(badge > 99 ? '99+' : '$badge'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Space ของฉัน" sheet (Slack-style workspaces).
Future<void> showSpaceSwitcher(BuildContext context) {
  HapticFeedback.selectionClick();
  return showNxSnapSheet<void>(
    context: context,
    snaps: const [0.62, 0.92],
    builder: (ctx, controller) => _SpaceSheet(controller: controller, hostContext: context),
  );
}

class _SpaceSheet extends StatefulWidget {
  const _SpaceSheet({required this.controller, required this.hostContext});
  final ScrollController controller;
  final BuildContext hostContext;

  @override
  State<_SpaceSheet> createState() => _SpaceSheetState();
}

class _SpaceSheetState extends State<_SpaceSheet> {
  bool _editing = false;
  final Map<String, int> _unread = {};

  @override
  void initState() {
    super.initState();
    _loadUnread();
  }

  /// Unread count of every other Space, each with its own token.
  Future<void> _loadUnread() async {
    final config = context.read<AppConfig>();
    for (final sp in config.spaces) {
      if (sp.id == config.activeSpace?.id) continue;
      try {
        final api = await config.spaceClient(sp);
        if (api == null) continue;
        final n = parseUnreadSummary(await api.getNotificationSummary());
        if (mounted) setState(() => _unread[sp.id] = n);
      } catch (_) {}
    }
  }

  Future<void> _switch(Space sp, Rect? origin) async {
    final config = context.read<AppConfig>();
    if (sp.id == config.activeSpace?.id) {
      Navigator.pop(context);
      return;
    }
    final host = widget.hostContext;
    Navigator.pop(context);
    await runSpaceTransition(host, sp, origin, () => config.switchSpace(sp.id));
  }

  /// Opens the "เพิ่ม Space" window over the current screen (no full login page).
  Future<void> _add({String? baseUrl}) async {
    final host = widget.hostContext;
    Navigator.pop(context);
    await showAddSpaceSheet(host, baseUrl: baseUrl);
  }

  Future<void> _menu(Space sp) async {
    final pick = await showNxBlurPanel<String>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              title: Text(
                sp.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(leading: const Icon(NxI.pencilSimple), title: Text(tr('แก้ไขชื่อ / สี')), onTap: () => Navigator.pop(context, 'edit')),
            ListTile(
              leading: const Icon(NxI.copySimple),
              title: Text(tr('ทำซ้ำ')),
              subtitle: Text(tr('เพิ่มอีกบัญชีใน ${sp.host}')),
              onTap: () => Navigator.pop(context, 'dup'),
            ),
            ListTile(
              leading: Icon(NxI.signOut, color: Theme.of(context).colorScheme.error),
              title: Text(tr('ออกจากระบบ'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              subtitle: Text(tr('ลบ Space นี้ออกจากเครื่อง (Space อื่นยังใช้งานได้)')),
              onTap: () => Navigator.pop(context, 'out'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || pick == null) return;
    final config = context.read<AppConfig>();
    switch (pick) {
      case 'edit':
        await showSpaceEditor(context, sp);
      case 'dup':
        await _add(baseUrl: sp.baseUrl);
      case 'out':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('ออกจาก ${sp.title}?')),
            content: Text(tr('${sp.host}\n${sp.email ?? ''}\nข้อมูลบนเซิร์ฟเวอร์ไม่ถูกลบ เพิ่มกลับได้ด้วยการเข้าสู่ระบบอีกครั้ง')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ออกจากระบบ'))),
            ],
          ),
        );
        if (ok == true) {
          HapticFeedback.mediumImpact();
          await config.removeSpace(sp.id);
          if (mounted && config.spaces.isEmpty) Navigator.pop(context);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final spaces = config.spaces;
    final activeId = config.activeSpace?.id;
    Widget tile(Space sp, int i) {
      final selected = sp.id == activeId;
      final key = GlobalKey();
      return Padding(
        key: ValueKey(sp.id),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _editing
              ? null
              : () {
                  final box = key.currentContext?.findRenderObject() as RenderBox?;
                  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
                  _switch(sp, origin);
                },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
            child: Row(
              children: [
                SpaceAvatar(key: key, space: sp, size: 54, selected: selected, badge: selected ? UnreadNotifications.instance.count : (_unread[sp.id] ?? 0)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(sp.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        tr(sp.host),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      if ((sp.email ?? '').isNotEmpty)
                        Text(
                          tr(sp.email!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                if (_editing)
                  ReorderableDragStartListener(
                    index: i,
                    child: const Padding(padding: EdgeInsets.all(12), child: Icon(NxI.grip)),
                  )
                else
                  Builder(builder: (bc) => IconButton(tooltip: tr('ตัวเลือก'), icon: const Icon(NxI.dotsThreeVertical), onPressed: NxTapTracker.from(bc, () => _menu(sp)))),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(tr('Space ของฉัน'), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              TextButton(onPressed: spaces.length < 2 ? null : () => setState(() => _editing = !_editing), child: Text(tr(_editing ? 'เสร็จ' : 'แก้ไข'))),
            ],
          ),
        ),
        Expanded(
          child: _editing
              ? ReorderableListView(
                  scrollController: widget.controller,
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onReorder: (a, b) => config.reorderSpaces(a, b),
                  children: [for (var i = 0; i < spaces.length; i++) tile(spaces[i], i)],
                )
              : ListView(
                  controller: widget.controller,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (var i = 0; i < spaces.length; i++)
                      TweenAnimationBuilder<double>(
                        key: ValueKey('in-${spaces[i].id}'),
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(milliseconds: 220 + 40 * i),
                        curve: Curves.easeOutCubic,
                        builder: (context, t, child) => Opacity(
                          opacity: t,
                          child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child),
                        ),
                        child: tile(spaces[i], i),
                      ),
                  ],
                ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Column(
            children: [
              ListTile(leading: const Icon(NxI.plus), title: Text(tr('เพิ่ม Space')), subtitle: Text(tr('โดเมนอื่น หรือบัญชีอื่น')), onTap: () => _add()),
              ListTile(
                leading: const Icon(NxI.deviceMobile),
                title: Text(tr('อุปกรณ์ที่เข้าใช้งาน')),
                onTap: () {
                  final router = GoRouter.of(widget.hostContext);
                  Navigator.pop(context);
                  router.push(AppRoutes.devices);
                },
              ),
              ListTile(
                leading: const Icon(NxI.gear),
                title: Text(tr('ตั้งค่า')),
                onTap: () {
                  final router = GoRouter.of(widget.hostContext);
                  Navigator.pop(context);
                  router.push(AppRoutes.settings);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Rename / recolour a Space.
Future<void> showSpaceEditor(BuildContext context, Space sp) async {
  final name = TextEditingController(text: sp.label ?? '');
  var color = sp.color.toARGB32();
  await showAppBottomSheet<void>(
    context: context,
    title: 'แก้ไข Space',
    child: StatefulBuilder(
      builder: (ctx, set) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: SpaceAvatar(
              space: sp.copyWith(label: name.text.isEmpty ? null : name.text, colorValue: color),
              size: 72,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: tr('ชื่อที่แสดง'), hintText: trn(sp.businessName ?? sp.host)),
            onChanged: (_) => set(() {}),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in spacePalette)
                GestureDetector(
                  onTap: () => set(() => color = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(color: c == color ? Theme.of(ctx).colorScheme.onSurface : Colors.transparent, width: 3),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              await ctx.read<AppConfig>().updateSpace(sp.id, label: name.text, colorValue: color);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(tr('บันทึก')),
          ),
        ],
      ),
    ),
  );
  name.dispose();
}

/// Full-screen hand-off: the Space colour grows out of its logo, the new
/// Space loads underneath, then the colour fades away to reveal it.
Future<void> runSpaceTransition(BuildContext context, Space sp, Rect? origin, Future<void> Function() action) =>
    runColorHandOff(context, color: sp.color, badge: sp.initials, title: sp.title, subtitle: sp.host, origin: origin, action: action);

/// The colour hand-off used for Spaces and Packages: [color] grows out of
/// [origin] with [badge] / [title] / [subtitle], [action] runs underneath, then
/// the colour fades to reveal the result. [goHome] returns to the main shell.
Future<void> runColorHandOff(
  BuildContext context, {
  required Color color,
  required String badge,
  required String title,
  required String subtitle,
  Rect? origin,
  required Future<void> Function() action,
  bool goHome = true,
}) async {
  final overlay = Overlay.of(context, rootOverlay: true);
  final size = MediaQuery.sizeOf(context);
  final from = origin ?? Rect.fromCenter(center: size.center(Offset.zero), width: 56, height: 56);
  final grow = ValueNotifier<double>(0);
  final fade = ValueNotifier<double>(1);
  // The overlay sits above the app's Material: give it the app theme and text
  // style, or Flutter draws the yellow "missing Material" underline and a
  // fallback font.
  final theme = Theme.of(context);
  final entry = OverlayEntry(
    builder: (ctx) => Theme(
      data: theme,
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(
          style: theme.textTheme.bodyMedium!.copyWith(color: Colors.white, decoration: TextDecoration.none),
          child: IgnorePointer(
      child: ValueListenableBuilder<double>(
        valueListenable: fade,
        builder: (ctx, o, _) => Opacity(
          opacity: o,
          child: ValueListenableBuilder<double>(
            valueListenable: grow,
            builder: (ctx, t, _) {
              final maxR = size.longestSide * 1.2;
              final r = from.width / 2 + (maxR - from.width / 2) * Curves.easeInOutCubic.transform(t);
              final c = from.center;
              return Stack(
                children: [
                  Positioned(
                    left: c.dx - r,
                    top: c.dy - r,
                    width: r * 2,
                    height: r * 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                  ),
                  Center(
                    child: Opacity(
                      opacity: ((t - 0.4) / 0.6).clamp(0.0, 1.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Badge as text only (like the switcher popup), app font, no box.
                          Text(
                            tr(badge),
                            key: const ValueKey('handoff-badge'),
                            style: theme.textTheme.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1, decoration: TextDecoration.none),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            tr(title),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700, decoration: TextDecoration.none),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tr(subtitle),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
          ),
        ),
      ),
  );
  overlay.insert(entry);
  HapticFeedback.mediumImpact();
  Future<void> animate(ValueNotifier<double> v, double to, int ms) async {
    final start = v.value;
    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < ms) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      v.value = start + (to - start) * (sw.elapsedMilliseconds / ms).clamp(0.0, 1.0);
    }
    v.value = to;
  }

  try {
    await animate(grow, 1, 420);
    final router = GoRouter.maybeOf(context);
    final rootNav = Navigator.maybeOf(context, rootNavigator: true);
    await action();
    if (goHome) {
      // Pages of the old business / Space must not stay under the new one.
      rootNav?.popUntil((r) => r.isFirst || r.settings.name != null);
      router?.go(AppRoutes.mainShell);
    }
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await animate(fade, 0, 320);
  } finally {
    entry.remove();
    grow.dispose();
    fade.dispose();
  }
}

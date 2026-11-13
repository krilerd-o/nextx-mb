
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/entity_display.dart';
import '../core/navigation/app_routes.dart';
import 'nx_back_handler.dart' show NxShellTabScope;
import 'nx_icons.dart';
import '../screens/spaces/space_switcher.dart' show showSpaceSwitcher;
import 'nx_notif_morph.dart';
import 'nx_chrome.dart';
import 'nx_scroll_scaffold.dart' show NxFloatingHeaderScope;
import 'nx_overlay_panel.dart';
import '../services/unread_service.dart';
import '../core/i18n.dart';

class NxHeaderMenuItem {
  const NxHeaderMenuItem({
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
}

enum NxHeaderMode { hub, page }

class NxAppHeader extends StatelessWidget implements PreferredSizeWidget {
  const NxAppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.automaticallyImplyLeading = true,
    this.leading,
    this.menu,
    this.subtitleWidget,
    this.largeTitle = false,
    this.onTitleTap,
  })  : mode = NxHeaderMode.page,
        unreadCount = null;

  const NxAppHeader.hub({
    super.key,
    this.actions,
    this.unreadCount,
  })  : mode = NxHeaderMode.hub,
        title = '',
        subtitle = null,
        automaticallyImplyLeading = false,
        leading = null,
        menu = null,
        subtitleWidget = null,
        largeTitle = false,
        onTitleTap = null;

  const NxAppHeader.page({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.automaticallyImplyLeading = true,
    this.leading,
    this.menu,
    this.subtitleWidget,
    this.largeTitle = false,
    this.onTitleTap,
  })  : mode = NxHeaderMode.page,
        unreadCount = null;

  final NxHeaderMode mode;
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;
  final Widget? leading;
  final List<NxHeaderMenuItem>? menu;
  final int? unreadCount;

  /// Tappable row under the title (e.g. the CRM Custom View picker `ทั้งหมด ▾`).
  final Widget? subtitleWidget;

  /// Big menu title (list roots) that shrinks while the page chrome is collapsed.
  final bool largeTitle;

  /// Title becomes a button with a ▾ (e.g. calendar: switch year / month).
  final VoidCallback? onTitleTap;

  static const double controlSize = 40;

  @override
  Size get preferredSize =>
      Size.fromHeight(mode == NxHeaderMode.hub ? 64 : (subtitle == null && subtitleWidget == null ? 56 : 72));

  @override
  Widget build(BuildContext context) {
    // Inside NxScrollScaffold the header floats over a progressive blur.
    final floating = NxFloatingHeaderScope.of(context);
    return Material(
      color: floating ? Colors.transparent : Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        bottom: false,
        child: mode == NxHeaderMode.hub ? _HubBar(actions: actions, unreadCount: unreadCount) : _PageBar(header: this),
      ),
    );
  }
}

/// A header control wider than the round buttons (e.g. the TH | EN switch):
/// placed as-is in the header's action row, at the round buttons' height.
abstract class NxHeaderPill extends StatelessWidget {
  const NxHeaderPill({super.key});
}

/// TH | EN language switch for headers: a raised capsule like the round
/// buttons; the active language is filled.
class NxLanguagePill extends NxHeaderPill {
  const NxLanguagePill({super.key, required this.code, required this.onChanged});
  final String code;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF2A2B36) : Colors.white;
    Widget seg(String c, String label) {
      final on = code == c;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: c == 'th' ? 'ภาษาไทย' : 'English',
          child: GestureDetector(
            key: ValueKey('lang-pill-$c'),
            behavior: HitTestBehavior.opaque,
            onTap: on ? null : () => onChanged(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.all(3),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: on ? cs.primary : Colors.transparent, borderRadius: BorderRadius.circular(99)),
              child: Text(label, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: on ? cs.onPrimary : cs.onSurfaceVariant)),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      key: const ValueKey('lang-pill'),
      width: 84,
      height: NxAppHeader.controlSize,
      child: Material(
        color: fill,
        shape: const StadiumBorder(),
        elevation: isDark ? 4 : 3,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.22),
        child: Row(children: [seg('th', 'TH'), seg('en', 'EN')]),
      ),
    );
  }
}

/// ระบบ / สว่าง / มืด switch for headers: a raised capsule with three icon
/// segments; the active one is filled.
class NxThemePill extends NxHeaderPill {
  const NxThemePill({super.key, required this.mode, required this.onChanged});
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  static const _modes = [(ThemeMode.system, NxI.deviceMobile, 'ระบบ'), (ThemeMode.light, NxI.sun, 'สว่าง'), (ThemeMode.dark, NxI.moon, 'มืด')];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return SizedBox(
      key: const ValueKey('theme-pill'),
      width: 112,
      height: NxAppHeader.controlSize,
      child: Material(
        color: isDark ? const Color(0xFF2A2B36) : Colors.white,
        shape: const StadiumBorder(),
        elevation: isDark ? 4 : 3,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.22),
        child: Row(children: [
          for (final (m, icon, label) in _modes)
            Expanded(
              child: Tooltip(
                message: tr(label),
                child: Semantics(
                  button: true,
                  selected: m == mode,
                  label: tr(label),
                  child: GestureDetector(
                    key: ValueKey('theme-pill-${m.name}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: m == mode
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            onChanged(m);
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.all(3),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: m == mode ? cs.primary : Colors.transparent, shape: BoxShape.circle),
                      child: Icon(icon, size: 16, color: m == mode ? cs.onPrimary : cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.badgeCount,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF2A2B36) : Colors.white;
    final count = badgeCount ?? 0;
    final button = SizedBox(
      width: NxAppHeader.controlSize,
      height: NxAppHeader.controlSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Material(
            color: fill,
            shape: const CircleBorder(),
            elevation: isDark ? 4 : 3,
            shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.22),
            child: InkWell(
              customBorder: const CircleBorder(),
              // Menus opened from here grow out of this button.
              onTap: NxTapTracker.from(context, onTap),
              child: Center(
                child: Icon(icon, size: 22, color: theme.colorScheme.onSurface),
              ),
            ),
          ),
          if (count > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF375F),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: fill, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  tr(count > 99 ? '99+' : '$count'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

List<Widget> _circleActions(List<Widget>? actions) {
  if (actions == null || actions.isEmpty) return const [];
  return [
    for (final w in actions)
      Padding(
        // Keep the page's key on the converted button so tests and callers can still find it.
        key: w.key,
        padding: const EdgeInsets.only(left: 10),
        child: w is NxHeaderPill
            ? w
            : w is IconButton
            ? _CircleBtn(
                icon: w.icon is Icon ? (w.icon as Icon).icon ?? NxI.dotsThreeCircle : NxI.dotsThreeCircle,
                onTap: w.onPressed ?? () {},
                tooltip: trn(w.tooltip),
              )
            : SizedBox(
                width: NxAppHeader.controlSize,
                height: NxAppHeader.controlSize,
                child: Center(child: w),
              ),
      ),
  ];
}

class _HubBar extends StatelessWidget {
  const _HubBar({this.actions, this.unreadCount});

  final List<Widget>? actions;
  final int? unreadCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SizedBox(
        height: NxAppHeader.controlSize,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const NxHubAvatar(),
            const Spacer(),
            ..._circleActions(actions),
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: _HubBell(unreadCount: unreadCount),
            ),
          ],
        ),
      ),
    );
  }
}

/// Signed-in user's photo (or initials). Tap = profile hub; long-press =
/// Space switcher. Also used on Home's hero ([ring] = white outline on a photo).
class NxHubAvatar extends StatelessWidget {
  const NxHubAvatar({super.key, this.size = NxAppHeader.controlSize, this.ring = false});

  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    AppConfig? config;
    try {
      config = context.watch<AppConfig>();
    } catch (_) {}
    final name = config?.session.displayName ?? config?.session.email ?? 'U';
    // Same picture as the web (server imagename), else the copy on this phone.
    final image = config?.profileAvatarImage;
    return GestureDetector(
      // Tap = profile hub (profile + all settings); long-press = Space switcher.
      onTap: () => GoRouter.maybeOf(context)?.push(AppRoutes.profile),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        showSpaceSwitcher(context);
      },
      child: Container(
        width: size,
        height: size,
        decoration: ring
            ? BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 2))],
              )
            : null,
        child: CircleAvatar(
          radius: size / 2,
          backgroundColor: ring ? Colors.white : Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
          backgroundImage: image,
          onBackgroundImageError: image == null ? null : (_, _) {},
          child: image == null
              ? Text(
                  tr(entityInitials(name)),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _HubBell extends StatelessWidget {
  const _HubBell({this.unreadCount});

  /// Explicit override (tests); otherwise the shared [UnreadNotifications] count.
  final int? unreadCount;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UnreadNotifications.instance,
      builder: (context, _) => _CircleBtn(
        icon: NxI.bell,
        tooltip: tr('การแจ้งเตือน'),
        badgeCount: unreadCount ?? UnreadNotifications.instance.count,
        onTap: () async {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) {
            await GoRouter.maybeOf(context)?.push(AppRoutes.notifications);
            await UnreadNotifications.instance.refreshIfBound();
            return;
          }
          await showNotifMorph(context, box.localToGlobal(Offset.zero) & box.size);
        },
      ),
    );
  }
}

class _PageBar extends StatelessWidget {
  const _PageBar({required this.header});

  final NxAppHeader header;

  List<NxHeaderMenuItem> _items() => [...?header.menu];

  Future<void> _openMenu(BuildContext context, List<NxHeaderMenuItem> items) async {
    await showNxBlurPanel<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              ListTile(
                leading: item.icon == null ? null : Icon(item.icon),
                title: Text(tr(item.label)),
                onTap: () {
                  Navigator.pop(ctx);
                  item.onTap();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = header.automaticallyImplyLeading && Navigator.of(context).canPop();
    final items = _items();
    final chrome = NxChrome.of(context);
    final folded = chrome != null && chrome.collapsed;
    // Collapsed toolbars leave their search / filter / view icons here.
    final chromeActions = chrome == null ? const <NxChromeAction>[] : [for (final a in chrome.actions) if (folded || a.pinned) a];
    // Opened straight from a notification / link with nothing under it:
    // the back arrow takes you home instead of being missing.
    final homeBack = !canPop && header.automaticallyImplyLeading && nxIsOrphanAppPage(context);
    final leading = header.leading ??
        (canPop
            ? _CircleBtn(
                icon: NxI.arrowLeft,
                tooltip: tr('กลับ'),
                onTap: () => Navigator.of(context).maybePop(),
              )
            : homeBack
                ? _CircleBtn(
                    key: const ValueKey('nx-header-home-back'),
                    icon: NxI.arrowLeft,
                    tooltip: tr('กลับหน้าแรก'),
                    onTap: () => context.go(AppRoutes.mainShell),
                  )
                : null);
    final big = header.largeTitle && !folded;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SizedBox(
        height: header.subtitle == null && header.subtitleWidget == null ? NxAppHeader.controlSize : 56,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[
              SizedBox(width: NxAppHeader.controlSize, height: NxAppHeader.controlSize, child: leading),
              const SizedBox(width: 12),
            ] else
              const SizedBox(width: 4),
            Expanded(
              // Title + subtitle share a fixed 56 pt row: cap large text so they never spill out of it.
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: header.subtitle == null && header.subtitleWidget == null ? 1.6 : 1.1,
                child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    style: (big ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)!.copyWith(
                      fontWeight: big ? FontWeight.w800 : FontWeight.w700,
                      letterSpacing: -0.2,
                      color: theme.colorScheme.onSurface,
                    ),
                    child: header.onTitleTap == null
                        ? Text(
                            tr(header.title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.start,
                          )
                        : GestureDetector(
                            key: const ValueKey('nx-header-title'),
                            behavior: HitTestBehavior.opaque,
                            onTap: header.onTitleTap,
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Flexible(child: Text(tr(header.title), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 2),
                              Icon(NxI.caretDown, size: 18, color: theme.colorScheme.onSurfaceVariant),
                            ]),
                          ),
                  ),
                  if (header.subtitleWidget != null)
                    header.subtitleWidget!
                  else if (header.subtitle != null)
                    Text(
                      tr(header.subtitle!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.start,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              ),
            ),
            for (final a in chromeActions)
              Padding(
                key: ValueKey('chrome-${a.id}'),
                padding: const EdgeInsets.only(left: 10),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.4, end: 1),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutBack,
                  builder: (context, v, child) => Transform.scale(scale: v, child: Opacity(opacity: v.clamp(0.0, 1.0), child: child)),
                  child: _CircleBtn(icon: a.icon, tooltip: tr(a.tooltip), badgeCount: a.badge, onTap: a.onTap),
                ),
              ),
            // While folded, the page's own icons step aside if the row would
            // crowd the title (pull-to-refresh / ⋯ still reach them).
            if (!folded || chromeActions.isEmpty || chromeActions.length + (header.actions?.length ?? 0) + (items.isEmpty ? 0 : 1) <= 3)
              ..._circleActions(header.actions),
            if (items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: _CircleBtn(
                  icon: NxI.dotsThreeCircle,
                  tooltip: tr('เพิ่มเติม'),
                  onTap: () => _openMenu(context, items),
                ),
              ),
          ],
        ),
      ),
    );
  }
}


/// Routes that are the first page of their own flow (no "back" expected).
const _kFlowRoots = {
  AppRoutes.splash, AppRoutes.login, AppRoutes.welcome, AppRoutes.server, AppRoutes.register,
  AppRoutes.lineLogin, AppRoutes.linkConfirm, AppRoutes.package, AppRoutes.roleSetup, AppRoutes.tabSetup,
  AppRoutes.updateRequired, AppRoutes.hub, AppRoutes.gettingStarted, AppRoutes.mainShell,
};

/// True for an app page that is alone on the stack outside the tabs (deep link / push).
bool nxIsOrphanAppPage(BuildContext context) {
  if (NxShellTabScope.maybeOf(context) != null) return false;
  final router = GoRouter.maybeOf(context);
  if (router == null) return false;
  final path = router.routerDelegate.currentConfiguration.uri.path;
  if (path.isEmpty || _kFlowRoots.contains(path)) return false;
  // Only signed-in app pages (the onboarding steps have their own back).
  return context.read<AppConfig>().isLoggedIn;
}

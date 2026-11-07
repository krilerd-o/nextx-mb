import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/entity_display.dart';
import '../core/navigation/app_routes.dart';
import 'nx_icons.dart';
import 'nx_notif_morph.dart';
import 'nx_overlay_panel.dart';
import '../services/unread_service.dart';

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
        menu = null;

  const NxAppHeader.page({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.automaticallyImplyLeading = true,
    this.leading,
    this.menu,
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

  static const double controlSize = 40;

  @override
  Size get preferredSize => Size.fromHeight(mode == NxHeaderMode.hub ? 64 : (subtitle == null ? 56 : 72));

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        bottom: false,
        child: mode == NxHeaderMode.hub ? _HubBar(actions: actions, unreadCount: unreadCount) : _PageBar(header: this),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({
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
              onTap: onTap,
              child: Center(
                child: Icon(NxI.regularOf(icon), size: 22, color: theme.colorScheme.onSurface),
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
                  count > 99 ? '99+' : '$count',
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
        padding: const EdgeInsets.only(left: 10),
        child: w is IconButton
            ? _CircleBtn(
                icon: w.icon is Icon ? (w.icon as Icon).icon ?? NxI.dotsThreeCircle : NxI.dotsThreeCircle,
                onTap: w.onPressed ?? () {},
                tooltip: w.tooltip,
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
            const _HubAvatar(),
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

class _HubAvatar extends StatelessWidget {
  const _HubAvatar();

  @override
  Widget build(BuildContext context) {
    AppConfig? config;
    try {
      config = context.watch<AppConfig>();
    } catch (_) {}
    final name = config?.session.displayName ?? config?.session.email ?? 'U';
    final b64 = config?.profileAvatarBase64;
    ImageProvider? image;
    if (b64 != null && b64.isNotEmpty) {
      try {
        image = MemoryImage(base64Decode(b64.contains(',') ? b64.split(',').last : b64));
      } catch (_) {}
    }
    return GestureDetector(
      onTap: () => GoRouter.maybeOf(context)?.push(AppRoutes.profile),
      child: SizedBox(
        width: NxAppHeader.controlSize,
        height: NxAppHeader.controlSize,
        child: CircleAvatar(
          radius: NxAppHeader.controlSize / 2,
          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
          backgroundImage: image,
          child: image == null
              ? Text(
                  entityInitials(name),
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
        tooltip: 'การแจ้งเตือน',
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
                title: Text(item.label),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SizedBox(
        height: header.subtitle == null ? NxAppHeader.controlSize : 56,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: NxAppHeader.controlSize,
              height: NxAppHeader.controlSize,
              child: header.leading ??
                  (canPop
                      ? _CircleBtn(
                          icon: NxI.arrowLeft,
                          tooltip: 'กลับ',
                          onTap: () => Navigator.of(context).maybePop(),
                        )
                      : null),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    header.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (header.subtitle != null)
                    Text(
                      header.subtitle!,
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
            ..._circleActions(header.actions),
            if (items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: _CircleBtn(
                  icon: NxI.dotsThreeCircle,
                  tooltip: 'เพิ่มเติม',
                  onTap: () => _openMenu(context, items),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

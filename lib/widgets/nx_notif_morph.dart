import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/effects.dart';
import '../core/navigation/app_routes.dart';
import '../core/navigation/notification_deep_link.dart';
import '../core/nx_motion.dart';
import '../screens/notifications/notification_center_screen.dart' show relativeTime;
import '../services/unread_service.dart';
import 'nx_icons.dart';
import 'nx_notification_view.dart';
import '../core/i18n.dart';

/// Bell that morphs into an inline notification tray (expo-notif-morph):
/// the circle grows from where the bell is into a card with the latest items.
Future<void> showNotifMorph(BuildContext context, Rect origin) async {
  HapticFeedback.lightImpact();
  await Navigator.of(context).push(_MorphRoute(origin: origin, blur: Effects.blur(context)));
  await UnreadNotifications.instance.refreshIfBound();
}

class _MorphRoute extends PopupRoute<void> {
  _MorphRoute({required this.origin, required this.blur});
  final Rect origin;
  final bool blur;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: blur ? 0.12 : 0.3);
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => 'ปิด';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);
  @override
  ui.ImageFilter? get filter => blur ? ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6) : null;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return _MorphTray(origin: origin, animation: animation);
  }
}

class _MorphTray extends StatefulWidget {
  const _MorphTray({required this.origin, required this.animation});
  final Rect origin;
  final Animation<double> animation;

  @override
  State<_MorphTray> createState() => _MorphTrayState();
}

class _MorphTrayState extends State<_MorphTray> {
  List<Map<String, dynamic>>? _items;
  Object? _error;
  String _cat = 'all';
  Map<String, int> _unreadBy = const {};
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    try {
      final s = await context.read<AppConfig>().apiClient.getNotificationSummary();
      final by = s['by_category'];
      if (by is Map && mounted) {
        setState(() => _unreadBy = {for (final e in by.entries) '${e.key}': int.tryParse('${e.value}') ?? 0});
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    final seq = ++_seq;
    try {
      final page = await context.read<AppConfig>().apiClient.getNotificationsPage(limit: 8, category: _cat);
      if (mounted && seq == _seq) setState(() => _items = page.items);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = e);
    }
  }

  void _openLink(String path) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(notificationDeepLink(path));
  }

  void _open(Map<String, dynamic> it) {
    final router = GoRouter.of(context);
    final id = it['id']?.toString();
    if (id != null && notifUnread(it)) {
      context.read<AppConfig>().apiClient.markNotificationRead(id).catchError((_) {});
      UnreadNotifications.instance.markedRead();
    }
    Navigator.of(context).pop();
    router.push(notificationDeepLink(it['link_path']?.toString() ?? '', linkId: it['link_id']?.toString(), extra: it['link_extra']?.toString()));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final width = (size.width - 24).clamp(0.0, 420.0);
    final target = Rect.fromLTWH(
      (size.width - width - 12).clamp(12.0, size.width),
      widget.origin.top.clamp(pad.top + 4, size.height),
      width,
      (size.height * 0.62).clamp(220.0, 460.0),
    );
    final curved = CurvedAnimation(parent: widget.animation, curve: NxMotion.settleCurve, reverseCurve: Curves.easeInCubic);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        final t = curved.value;
        final r = Rect.lerp(widget.origin, target, t)!;
        final radius = ui.lerpDouble(widget.origin.height / 2, 26, t)!;
        return Stack(
          children: [
            Positioned.fromRect(
              rect: r,
              child: Material(
                color: cs.surface,
                elevation: 12 * t,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(radius),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // The bell fades out as the tray content fades in.
                    Opacity(
                      opacity: (1 - t * 3).clamp(0.0, 1.0),
                      child: Center(child: Icon(NxI.bell, color: cs.onSurface, size: 20)),
                    ),
                    Opacity(
                      opacity: ((t - 0.35) / 0.65).clamp(0.0, 1.0),
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minWidth: target.width,
                        maxWidth: target.width,
                        minHeight: target.height,
                        maxHeight: target.height,
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
            child: Row(
              children: [
                Expanded(child: Text(tr('การแจ้งเตือน'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                IconButton(tooltip: tr('ปิด'), icon: const Icon(NxI.x, size: 20), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final c in kNotifTrayTabs)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      key: ValueKey('tray-tab-$c'),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      selected: _cat == c,
                      labelStyle: TextStyle(color: _cat == c ? Colors.white : null, fontWeight: FontWeight.w600),
                      label: Text([
                        tr(notifCategoryStyle(c).label),
                        if (c != 'all' && (_unreadBy[c] ?? 0) > 0) '${_unreadBy[c]}',
                      ].join(' ')),
                      onSelected: (_) {
                        setState(() {
                          _cat = c;
                          _items = null;
                          _error = null;
                        });
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _list(theme, cs)),
          const Divider(height: 1),
          TextButton(
            onPressed: () {
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              router.push(AppRoutes.notifications);
            },
            child: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text(tr('ดูทั้งหมด'))),
          ),
        ],
      ),
    );
  }

  Widget _list(ThemeData theme, ColorScheme cs) {
    if (_error != null) return Center(child: Text(tr('โหลดไม่สำเร็จ'), style: theme.textTheme.bodyMedium));
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (items.isEmpty) return Center(child: Text(tr('ไม่มีการแจ้งเตือน'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        // Stagger rows in after the box settles.
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 220 + i * 50),
          curve: Curves.easeOut,
          builder: (context, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(offset: Offset(0, (1 - v) * 8), child: child),
          ),
          child: NxNotifTile(
            item: it,
            compact: true,
            timeLabel: relativeTime(it['created_at']),
            onOpen: () => _open(it),
            onOpenLink: _openLink,
          ),
        );
      },
    );
  }
}

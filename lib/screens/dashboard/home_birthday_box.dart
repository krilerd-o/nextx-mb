import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/menu_access.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/thai_time.dart';
import '../../widgets/nx_icons.dart';
import '../calendar/cal/cal_birthday_actions.dart';
import '../calendar/cal/cal_birthdays.dart';
import '../calendar/cal/cal_model.dart';
import 'home_boxes.dart' show homeCardDecoration, kHomeWidgetGap;

/// Home: "วันเกิดลูกค้าวันนี้" — today's customer birthdays (Lead / Contact /
/// Account) with tomorrow's underneath, so nobody is missed. Tap a person for
/// the birthday card (call, email, plan a greeting, open the record).
/// Hidden when nobody has a birthday today or tomorrow.
class HomeBirthdayBox extends StatefulWidget {
  const HomeBirthdayBox({super.key, this.revision = 0});

  /// Bumped by Home's pull-to-refresh to reload.
  final int revision;

  @override
  State<HomeBirthdayBox> createState() => _HomeBirthdayBoxState();
}

class _HomeBirthdayBoxState extends State<HomeBirthdayBox> {
  late final CalBirthdays _b = CalBirthdays(
    context.read<AppConfig>().apiClient,
    scope: context.read<AppConfig>().prefsScope,
  );
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _b.addListener(_changed);
    _b.load();
  }

  @override
  void didUpdateWidget(covariant HomeBirthdayBox old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision) _b.load(force: true);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _b.removeListener(_changed);
    _b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = calDay(thaiNow());
    final tomorrow = today.add(const Duration(days: 1));
    // Only people from modules this user may open (Lead / Contact / Account).
    final session = context.select((AppConfig c) => c.session);
    bool ok(CalBirthday b) => MenuAccess.allow(session, b.module);
    final now = _b.on(today).where(ok).toList();
    final next = _b.on(tomorrow).where(ok).toList();
    if (now.isEmpty && next.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shown = _showAll ? now : now.take(4).toList();
    Widget row(CalBirthday b, DateTime day) => Builder(
          builder: (c) => CalBirthdayTile(
            b: b,
            day: day,
            onTap: () {
              final box = c.findRenderObject() as RenderBox?;
              openCalBirthday(context, b, day, anchor: box == null ? null : box.localToGlobal(Offset.zero) & box.size);
            },
          ),
        );
    return Padding(
      key: const ValueKey('home-birthdays'),
      padding: const EdgeInsets.only(top: kHomeWidgetGap),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: homeCardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: calBirthdayColor.withValues(alpha: 0.14), shape: BoxShape.circle),
                  child: Icon(now.isNotEmpty ? NxI.partyPopper : NxI.cake, size: 18, color: calBirthdayColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('วันเกิดลูกค้าวันนี้'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      [
                        now.isEmpty ? tr('วันนี้ไม่มี') : tr('${now.length} คน'),
                        if (next.isNotEmpty) tr('พรุ่งนี้ ${next.length} คน'),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ]),
                ),
                TextButton(
                  onPressed: () => context.push(AppRoutes.calendar),
                  child: Text(tr('ปฏิทิน')),
                ),
              ]),
            ),
            for (final b in shown) row(b, today),
            if (now.length > shown.length)
              TextButton(
                onPressed: () => setState(() => _showAll = true),
                child: Text(tr('ดูทั้งหมด (${now.length})')),
              ),
            if (next.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                child: Text(
                  tr('พรุ่งนี้'),
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800),
                ),
              ),
              for (final b in next.take(3)) row(b, tomorrow),
              if (next.length > 3)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(tr('และอีก ${next.length - 3} คน'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ),
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

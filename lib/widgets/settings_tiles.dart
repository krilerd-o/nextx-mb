import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/effects.dart';
import '../core/i18n.dart';
import '../screens/calendar/cal/cal_birthdays.dart';
import '../services/app_lock.dart';
import '../services/birthday_reminders.dart';
import 'nx_icons.dart';

/// Fades + slides a hub section in, one after another, the first time it shows.
class SettingsAppear extends StatelessWidget {
  const SettingsAppear({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Effects.animate(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + 45 * index.clamp(0, 8)),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        // Each section starts a little later than the previous one.
        final start = (index.clamp(0, 8) * 0.08).clamp(0.0, 0.6);
        final v = ((t - start) / (1 - start)).clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
        );
      },
      child: child,
    );
  }
}

/// Grey section label + rounded card holding the rows, hairline-separated.
/// [caption] is a short line under the label; [action] sits at its right
/// (e.g. a per-group "เปิดทั้งหมด" shortcut).
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.children, this.caption, this.action});
  final String title;
  final String? caption;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(title).toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 0.8),
                    ),
                    if (caption != null && caption!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(tr(caption!), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.85))),
                      ),
                  ],
                ),
              ),
              ?action,
            ],
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 0.5, thickness: 0.5, indent: 60, color: cs.outlineVariant.withValues(alpha: 0.6)),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Settings row: tinted icon tile, title/subtitle, trailing or chevron, and an
/// optional control underneath (segmented picker, colour palette, preview).
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.tint,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.below,
    this.enabled = true,
  });
  final IconData icon;
  final Color tint;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? below;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: tint.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 19, color: tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(title), style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        tr(subtitle!),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                Icon(NxI.caretRight, size: 18, color: cs.onSurfaceVariant),
            ],
          ),
          if (below != null) ...[const SizedBox(height: 12), below!],
        ],
      ),
    );
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(onTap: enabled ? onTap : null, child: row),
    );
  }
}

/// Accent colours in the web's two groups: standard tones, then pastels.
class AccentPalette extends StatelessWidget {
  const AccentPalette({super.key, required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget swatch(int i) => Semantics(
          button: true,
          selected: i == selected,
          label: tr(AppConfig.accentNames[i]),
          child: GestureDetector(
            key: ValueKey('accent-${AppConfig.accentKeys[i]}'),
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              // Not easeOutBack: an overshoot would make the padding negative.
              curve: Curves.easeOutCubic,
              width: 34,
              height: 34,
              padding: EdgeInsets.all(i == selected ? 3 : 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: i == selected ? AppConfig.accentOptions[i] : Colors.transparent, width: 2),
              ),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                scale: i == selected ? 1 : 0.86,
                child: DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppConfig.accentOptions[i]),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: i == selected
                        ? Icon(NxI.check, key: const ValueKey(true), size: 16, color: cs.surface)
                        : const SizedBox.shrink(key: ValueKey(false)),
                  ),
                ),
              ),
            ),
          ),
        );
    Widget group(String title, int from, int to) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Text(tr(title), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
            Wrap(spacing: 10, runSpacing: 10, children: [for (var i = from; i < to; i++) swatch(i)]),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        group('โทนมาตรฐาน', 0, AppConfig.accentPastelStart),
        const SizedBox(height: 10),
        group('โทนพาสเทล', AppConfig.accentPastelStart, AppConfig.accentOptions.length),
      ],
    );
  }
}

/// "ล็อกแอปด้วยลายนิ้วมือ / ใบหน้า" — greyed out on devices without it.
class AppLockTile extends StatefulWidget {
  const AppLockTile({super.key});

  @override
  State<AppLockTile> createState() => _AppLockTileState();
}

class _AppLockTileState extends State<AppLockTile> {
  bool _supported = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AppLock.instance.isSupported().then((v) {
      if (mounted) setState(() => _supported = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lock = AppLock.instance;
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) => SettingsTile(
        key: const ValueKey('settings-app-lock'),
        icon: NxI.fingerprint,
        tint: const Color(0xFF0EA5E9),
        title: 'ล็อกแอปด้วยลายนิ้วมือ / ใบหน้า',
        subtitle: _supported ? 'ขอสแกนเมื่อเปิดแอป หรือกลับมาหลังพักเกิน 5 นาที' : 'เครื่องนี้ไม่รองรับ',
        trailing: Switch(
          value: lock.enabled,
          onChanged: _busy || !_supported
              ? null
              : (v) async {
                  setState(() => _busy = true);
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await lock.setEnabled(v);
                  if (!ok) messenger.showSnackBar(SnackBar(content: Text(tr('ยืนยันตัวตนไม่สำเร็จ'))));
                  if (mounted) setState(() => _busy = false);
                },
        ),
      ),
    );
  }
}

/// "เตือนวันเกิดลูกค้าล่วงหน้า 1 วัน" (09:00 the day before), on by default.
class BirthdayReminderTile extends StatefulWidget {
  const BirthdayReminderTile({super.key});

  @override
  State<BirthdayReminderTile> createState() => _BirthdayReminderTileState();
}

class _BirthdayReminderTileState extends State<BirthdayReminderTile> {
  bool? _on;

  @override
  void initState() {
    super.initState();
    BirthdayReminders.isEnabled(context.read<AppConfig>().prefsScope).then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: NxI.cake,
      tint: const Color(0xFFEC4899),
      title: 'เตือนวันเกิดลูกค้าล่วงหน้า 1 วัน',
      subtitle: 'Lead / Contact / Account · แจ้งเวลา 09:00 ของวันก่อนวันเกิด',
      trailing: Switch(
        key: const ValueKey('settings-bday-remind'),
        value: _on ?? true,
        onChanged: _on == null
            ? null
            : (v) async {
                setState(() => _on = v);
                final config = context.read<AppConfig>();
                List<CalBirthday>? all;
                if (v) {
                  final b = CalBirthdays(config.apiClient);
                  await b.load();
                  all = b.all;
                  b.dispose();
                }
                await BirthdayReminders.setEnabled(config.prefsScope, v, birthdays: all);
              },
      ),
    );
  }
}

/// Soft tinted note (info / "server needs an update" / warnings) — never a
/// blank page.
class NxSoftNote extends StatelessWidget {
  const NxSoftNote({super.key, required this.text, this.icon = NxI.info, this.color, this.title, this.action});
  final String text;
  final String? title;
  final IconData icon;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = color ?? cs.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: theme.brightness == Brightness.dark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 20, color: c)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) Text(tr(title!), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(tr(text), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.45)),
                if (action != null) Padding(padding: const EdgeInsets.only(top: 6), child: action!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

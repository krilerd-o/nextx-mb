import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/effects.dart';
import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../core/ui_font.dart';
import '../../widgets/nx_appearance_controls.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_sliding_segmented.dart';
import '../../widgets/settings_tiles.dart';
import 'profile_ui.dart';

/// Date / time patterns the app offers (same as the old settings picker).
const kDateFormatOptions = ['dd/MM/yyyy HH:mm', 'yyyy-MM-dd HH:mm', 'MM/dd/yyyy h:mm a'];

/// [pattern] applied to [d] (only the tokens in [kDateFormatOptions]).
String formatDatePattern(String pattern, DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return pattern
      .replaceAll('yyyy', '${uiYear(d.year)}')
      .replaceAll('dd', two(d.day))
      .replaceAll('MM', two(d.month))
      .replaceAll('HH', two(d.hour))
      .replaceAll('mm', two(d.minute))
      .replaceAll(RegExp(r'\bh\b'), '$h12')
      .replaceAll(RegExp(r'\ba\b'), d.hour < 12 ? 'AM' : 'PM');
}

/// Short labels for the effects levels (the long ones are the subtitle).
String effectsShortLabel(EffectsPreference p) => switch (p) {
      EffectsPreference.auto => 'อัตโนมัติ',
      EffectsPreference.full => 'เต็ม',
      EffectsPreference.lite => 'เบา',
      EffectsPreference.off => 'ปิด',
    };

/// "จัดการธีม" — the one home for every look-and-feel setting: light / dark,
/// accent colour, language, date format, font, screen size, tablet menu
/// position and effects. All apply live; the preview card shows the result.
class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    final cs = Theme.of(context).colorScheme;
    var i = 0;
    return ProfileSubPage(
      title: 'จัดการธีม',
      children: [
        SettingsAppear(index: i++, child: const _LivePreview()),

        // ── Mode & colour
        SettingsAppear(
          index: i++,
          child: SettingsGroup(
            title: 'โหมดและสี',
            caption: 'สว่าง มืด หรือตามเครื่อง และสีหลักของแอป',
            children: [
              SettingsTile(
                key: const ValueKey('theme-mode'),
                icon: NxI.sunMoon,
                tint: const Color(0xFF8B5CF6),
                title: 'โหมดการแสดงผล',
                below: NxSlidingSegmented<ThemeMode>(
                  value: config.themeMode,
                  options: const [
                    (ThemeMode.light, 'สว่าง', NxI.sun),
                    (ThemeMode.dark, 'มืด', NxI.moon),
                    (ThemeMode.system, 'ตามเครื่อง', NxI.deviceMobile),
                  ],
                  onChanged: config.setThemeMode,
                ),
              ),
              SettingsTile(
                key: const ValueKey('theme-accent'),
                icon: NxI.palette,
                tint: config.accentColor,
                title: 'สีธีม',
                subtitle: AppConfig.accentNames[config.accentIndex.clamp(0, AppConfig.accentNames.length - 1)],
                below: AccentPalette(
                  selected: config.accentIndex,
                  onSelect: (i) {
                    HapticFeedback.selectionClick();
                    config.setAccentIndex(i);
                  },
                ),
              ),
            ],
          ),
        ),

        // ── Language & format
        SettingsAppear(
          index: i++,
          child: SettingsGroup(
            title: 'ภาษาและรูปแบบ',
            caption: 'ภาษาของแอปและรูปแบบวันที่ (เวลาประเทศไทยเสมอ)',
            children: [
              SettingsTile(
                key: const ValueKey('theme-language'),
                icon: NxI.languages,
                tint: const Color(0xFFF97316),
                title: 'ภาษา',
                subtitle: 'มีผลทั้งแอปทันที',
                below: NxSlidingSegmented<String>(
                  value: config.uiLocaleCode,
                  options: const [('th', 'ไทย', null), ('en', 'English', null)],
                  translate: false,
                  onChanged: config.setUiLocaleCode,
                ),
              ),
              SettingsTile(
                key: const ValueKey('theme-date-format'),
                icon: NxI.calendarClock,
                tint: const Color(0xFF14B8A6),
                title: 'รูปแบบวันที่/เวลา',
                subtitle: '${formatDatePattern(config.dateFormatPattern, thaiNow())} · ${tr('เวลาประเทศไทย')}',
                below: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in kDateFormatOptions)
                      ChoiceChip(
                        key: ValueKey('date-format-$o'),
                        label: Text(o),
                        selected: o == config.dateFormatPattern,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          config.setDateFormatPattern(o);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Text & size
        SettingsAppear(
          index: i++,
          child: SettingsGroup(
            title: 'ตัวอักษรและขนาด',
            caption: 'ฟอนต์และขนาดของตัวอักษร ปุ่ม และไอคอน',
            children: [
              SettingsTile(
                key: const ValueKey('theme-font'),
                icon: NxI.textT,
                tint: const Color(0xFF0EA5E9),
                title: 'ฟอนต์',
                subtitle: uiFontById(config.uiFontId).label,
                trailing: TextButton(onPressed: () => showUiFontPicker(context), child: Text(tr('ทั้งหมด'))),
                below: const _FontStrip(),
              ),
              const SettingsTile(
                key: ValueKey('theme-ui-scale'),
                icon: NxI.monitorSmartphone,
                tint: Color(0xFF22C55E),
                title: 'ขนาดหน้าจอ',
                subtitle: 'ตัวอักษร ปุ่ม และไอคอนทั้งแอป',
                below: NxUiScaleControl(),
              ),
            ],
          ),
        ),

        // ── Layout & effects
        SettingsAppear(
          index: i++,
          child: SettingsGroup(
            title: 'การจัดวางและเอฟเฟกต์',
            caption: 'ตำแหน่งเมนูบนแท็บเล็ต และความลื่นของภาพเคลื่อนไหว',
            children: [
              SettingsTile(
                key: const ValueKey('theme-nav-dock'),
                icon: NxI.tablet,
                tint: const Color(0xFF8B5CF6),
                title: 'ตำแหน่งเมนู (แท็บเล็ต)',
                subtitle: config.navDock.label,
                onTap: () => showNavDockPicker(context),
              ),
              ValueListenableBuilder<EffectsPreference>(
                valueListenable: Effects.preference,
                builder: (context, pref, _) => SettingsTile(
                  key: const ValueKey('theme-effects'),
                  icon: NxI.sparkle,
                  tint: const Color(0xFFEC4899),
                  title: 'เอฟเฟกต์และความลื่น',
                  subtitle: pref.label,
                  below: NxSlidingSegmented<EffectsPreference>(
                    value: pref,
                    options: [for (final p in EffectsPreference.values) (p, effectsShortLabel(p), null)],
                    onChanged: (p) async {
                      await Effects.setPreference(p);
                      config.refreshUi();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          tr('ตั้งค่าเหล่านี้เก็บไว้ในเครื่องนี้'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// A small "screen" in the current theme, accent, font and size.
class _LivePreview extends StatelessWidget {
  const _LivePreview();

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Container(
      key: const ValueKey('theme-preview'),
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.alphaBlend(cs.primary.withValues(alpha: dark ? 0.22 : 0.14), cs.surfaceContainerHighest), cs.surfaceContainerHighest],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(NxI.swatchBook, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('ตัวอย่าง'), style: theme.textTheme.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w800))),
            Text(
              '${uiFontById(config.uiFontId).label} · ${NxUiScaleControl.label(config.uiScale)}',
              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              CircleAvatar(radius: 20, backgroundColor: cs.primary.withValues(alpha: 0.15), child: Icon(NxI.calendarCheck, size: 20, color: cs.primary)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('นัดลูกค้า · บริษัท ตัวอย่าง'), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text(formatDatePattern(config.dateFormatPattern, thaiNow()), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(999)),
                child: Text(tr('เปิด'), style: theme.textTheme.labelMedium?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Fonts side by side, each previewed in itself; tap to apply.
class _FontStrip extends StatelessWidget {
  const _FontStrip();

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kUiFonts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = kUiFonts[i];
          final sel = f.id == config.uiFontId;
          return Material(
            color: sel ? cs.primary.withValues(alpha: 0.14) : cs.surface.withValues(alpha: 0.7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: sel ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5), width: sel ? 1.5 : 1),
            ),
            child: InkWell(
              key: ValueKey('theme-font-${f.id}'),
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                HapticFeedback.selectionClick();
                config.setUiFont(f.id);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aa กข', style: TextStyle(fontFamily: f.family, fontFamilyFallback: uiFontFallback(f.family), fontSize: 18, fontWeight: FontWeight.w600, color: sel ? cs.primary : cs.onSurface)),
                    Text(f.label, maxLines: 1, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

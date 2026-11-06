import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/nx_motion.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_select_tile.dart';
import '../../widgets/nx_icons.dart';

class GettingStartedScreen extends StatefulWidget {
  const GettingStartedScreen({super.key});

  @override
  State<GettingStartedScreen> createState() => _GettingStartedScreenState();
}

class _GettingStartedScreenState extends State<GettingStartedScreen> {
  int _step = 0;

  Future<void> _finish() async {
    await context.read<AppConfig>().completeGettingStarted();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = context.watch<AppConfig>();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProgressBar(step: _step, total: 3),
              const SizedBox(height: 24),
              Expanded(
                child: AnimatedSwitcher(
                  duration: nxMotion(context, 400),
                  switchInCurve: NxMotion.settleCurve,
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: _step == 0
                        ? _WelcomeStep(theme: theme)
                        : _step == 1
                            ? _ThemeStep(config: config)
                            : _ProfileStep(config: config),
                  ),
                ),
              ),
              if (_step == 0)
                NxHeroCta(label: 'ถัดไป', onPressed: () => setState(() => _step = 1))
              else if (_step == 1)
                NxHeroCta(label: 'ถัดไป', onPressed: () => setState(() => _step = 2))
              else ...[
                NxHeroCta(label: 'เข้าสู่แอป', onPressed: _finish),
                TextButton(
                  onPressed: _finish,
                  child: const Text('ข้าม'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.step, required this.total});
  final int step;
  final int total;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController.unbounded(vsync: this, value: (widget.step + 1) / widget.total);
  }

  @override
  void didUpdateWidget(covariant _ProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = (widget.step + 1) / widget.total;
    if (NxMotion.reduced(context)) {
      _c.value = next;
      return;
    }
    _c.animateWith(SpringSimulation(NxMotion.settle, _c.value, next, _c.velocity));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        return Stack(
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                return Container(
                  width: c.maxWidth * _c.value.clamp(0.0, 1.0),
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ยินดีต้อนรับ', style: theme.textTheme.displayMedium),
          const SizedBox(height: 12),
          Text(
            'ตั้งค่าโทนสีและโปรไฟล์สั้นๆ แล้วเข้าใช้งานได้เลย',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeStep extends StatelessWidget {
  const _ThemeStep({required this.config});
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Text('โทนและการเน้นสี', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 16),
        NxSelectTile(
          title: 'สว่าง',
          subtitle: 'พื้นล้างสี ตัวอักษรหมึก',
          selected: config.themeMode == ThemeMode.light,
          onTap: () => config.setThemeMode(ThemeMode.light),
        ),
        const SizedBox(height: 10),
        NxSelectTile(
          title: 'มืด',
          subtitle: 'พื้นเข้ม มีรั่ว indigo',
          selected: config.themeMode == ThemeMode.dark,
          onTap: () => config.setThemeMode(ThemeMode.dark),
        ),
        const SizedBox(height: 10),
        NxSelectTile(
          title: 'ตามระบบ',
          selected: config.themeMode == ThemeMode.system,
          onTap: () => config.setThemeMode(ThemeMode.system),
        ),
        const SizedBox(height: 24),
        Text('สีเน้น', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          children: [
            for (var i = 0; i < AppConfig.accentOptions.length; i++)
              GestureDetector(
                onTap: () => config.setAccentIndex(i),
                child: AnimatedContainer(
                  duration: nxMotion(context, 400),
                  curve: NxMotion.settleCurve,
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppConfig.accentOptions[i],
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: config.accentIndex == i ? theme.colorScheme.onSurface : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ProfileStep extends StatelessWidget {
  const _ProfileStep({required this.config});
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Text('โปรไฟล์', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'ใส่รูปได้ตอนนี้ หรือข้ามแล้วไปตั้งในภายหลัง',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        NxSelectTile(
          title: 'เลือกรูปโปรไฟล์',
          subtitle: config.profileAvatarBase64 == null ? 'ยังไม่มีรูป' : 'อัปโหลดแล้ว',
          leading: Icon(NxI.image, color: theme.colorScheme.primary),
          selected: config.profileAvatarBase64 != null,
          onTap: () async {
            try {
              await config.uploadProfileAvatarToServer();
            } catch (_) {}
          },
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/home_layout.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';

/// "ปรับแต่งหน้าหลัก": drag sections up/down, switch them on/off. Per user.
class HomeLayoutEditorScreen extends StatefulWidget {
  const HomeLayoutEditorScreen({super.key});

  @override
  State<HomeLayoutEditorScreen> createState() => _HomeLayoutEditorScreenState();
}

class _HomeLayoutEditorScreenState extends State<HomeLayoutEditorScreen> {
  late List<String> _order = List.of(HomeLayout.instance.order);
  late Set<String> _hidden = Set.of(HomeLayout.instance.hidden);

  static const _icons = {
    'today': NxI.sun,
    'pending': NxI.warningCircle,
    'birthdays': NxI.cake,
    'quick': NxI.lightning,
    'ai': NxI.sparkle,
    'work': NxI.kanban,
    'upcoming': NxI.calendarBlank,
    'recent': NxI.clockCounterClockwise,
    'stats': NxI.chartBar,
    'sales': NxI.trendUp,
    'cases': NxI.briefcase,
  };

  void _move(int i, int d) {
    final j = i + d;
    if (j < 0 || j >= _order.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      final k = _order.removeAt(i);
      _order.insert(j, k);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: const NxAppHeader(title: 'ปรับแต่งหน้าหลัก', subtitle: 'ลากเพื่อเรียง แตะสวิตช์เพื่อซ่อน/แสดง'),
      body: Column(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: _order.length,
              onReorder: (a, b) {
                HapticFeedback.selectionClick();
                setState(() {
                  if (b > a) b -= 1;
                  final k = _order.removeAt(a);
                  _order.insert(b, k);
                });
              },
              proxyDecorator: (child, _, anim) => AnimatedBuilder(
                animation: anim,
                builder: (_, c) => Transform.scale(scale: 1 + 0.03 * anim.value, child: Material(elevation: 6 * anim.value, borderRadius: BorderRadius.circular(18), child: c)),
                child: child,
              ),
              itemBuilder: (context, i) {
                final k = _order[i];
                final (label, hint) = HomeLayout.sections[k]!;
                final on = !_hidden.contains(k);
                return Container(
                  key: ValueKey(k),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: on ? 0.6 : 0.3),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.only(left: 6, right: 4),
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(NxI.dotsSixVertical, color: cs.onSurfaceVariant),
                      ),
                    ),
                    title: Row(
                      children: [
                        Icon(_icons[k] ?? NxI.squaresFour, size: 18, color: on ? cs.primary : cs.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Flexible(child: Text(tr(label), style: theme.textTheme.titleSmall)),
                      ],
                    ),
                    subtitle: Text(tr(hint), style: theme.textTheme.bodySmall),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: tr('ขึ้น'),
                          visualDensity: VisualDensity.compact,
                          onPressed: i == 0 ? null : () => _move(i, -1),
                          icon: const Icon(NxI.caretUp, size: 18),
                        ),
                        IconButton(
                          tooltip: tr('ลง'),
                          visualDensity: VisualDensity.compact,
                          onPressed: i == _order.length - 1 ? null : () => _move(i, 1),
                          icon: const Icon(NxI.caretDown, size: 18),
                        ),
                        Switch(
                          value: on,
                          onChanged: (v) => setState(() => v ? _hidden.remove(k) : _hidden.add(k)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        _order = List.of(HomeLayout.defaultOrder);
                        _hidden = {};
                      }),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
                      child: Text(tr('ค่าเริ่มต้น')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () async {
                        await HomeLayout.instance.save(context.read<AppConfig>().prefsScope, _order, _hidden);
                        if (context.mounted) Navigator.pop(context, true);
                      },
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
                      child: Text(tr('บันทึก')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

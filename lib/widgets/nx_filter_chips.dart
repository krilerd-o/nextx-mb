import 'package:flutter/material.dart';

enum NxEntityFilter { all, mine, recent }

class NxFilterChips extends StatelessWidget {
  const NxFilterChips({
    super.key,
    required this.value,
    required this.onChanged,
    this.showMine = true,
  });

  final NxEntityFilter value;
  final ValueChanged<NxEntityFilter> onChanged;
  final bool showMine;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget chip(NxEntityFilter f, String label) {
      final selected = value == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => onChanged(f),
          labelStyle: TextStyle(
            color: selected ? Colors.white : cs.onSurface,
            fontWeight: FontWeight.w500,
          ),
          selectedColor: cs.primary,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(NxEntityFilter.all, 'ทั้งหมด'),
          if (showMine) chip(NxEntityFilter.mine, 'ของฉัน'),
          chip(NxEntityFilter.recent, 'ล่าสุด'),
        ],
      ),
    );
  }
}

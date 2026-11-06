import 'package:flutter/material.dart';

import '../core/entity_display.dart';

const _palette = <Color>[
  Color(0xFF6366F1),
  Color(0xFF0EA5E9),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFEC4899),
  Color(0xFF8B5CF6),
  Color(0xFF14B8A6),
  Color(0xFFF97316),
];

Color nxAvatarColor(String seed) {
  var hash = 0;
  for (final u in seed.codeUnits) {
    hash = 0x1fffffff & (hash + u);
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    hash ^= hash >> 6;
  }
  return _palette[hash.abs() % _palette.length];
}

class NxAvatar extends StatelessWidget {
  const NxAvatar({
    super.key,
    required this.label,
    this.size = 44,
  });

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = nxAvatarColor(label);
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: bg.withOpacity(0.18),
      child: Text(
        entityInitials(label),
        style: TextStyle(
          color: bg,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.34,
        ),
      ),
    );
  }
}

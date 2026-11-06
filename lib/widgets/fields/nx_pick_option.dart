import 'package:flutter/material.dart';

class NxPickOption {
  const NxPickOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.color,
    this.emoji,
  });

  final String value;
  final String label;
  final String? subtitle;
  final Color? color;
  final String? emoji;

  factory NxPickOption.fromMap(Map<String, dynamic> map) {
    final value = (map['value'] ??
            map['id'] ??
            map['value_th'] ??
            map['name'] ??
            map['code'] ??
            '')
        .toString();
    final label = (map['value_th'] ??
            map['label_th'] ??
            map['label'] ??
            map['name'] ??
            map['value'] ??
            map['user_name'] ??
            value)
        .toString();
    final first = map['first_name']?.toString() ?? '';
    final last = map['last_name']?.toString() ?? '';
    final full = '$first $last'.trim();
    final colorRaw = map['color'] ?? map['cal_color'];
    return NxPickOption(
      value: value,
      label: full.isNotEmpty && label == value ? full : (label.isEmpty ? value : label),
      subtitle: map['email1']?.toString() ??
          map['email']?.toString() ??
          map['user_name']?.toString(),
      color: _parseColor(colorRaw),
      emoji: map['emoji']?.toString(),
    );
  }

  static Color? _parseColor(dynamic raw) {
    if (raw == null) return null;
    if (raw is Color) return raw;
    final s = raw.toString().trim().toLowerCase();
    const named = {
      'sky': Color(0xFF0EA5E9),
      'amber': Color(0xFFF59E0B),
      'emerald': Color(0xFF10B981),
      'red': Color(0xFFEF4444),
      'violet': Color(0xFF8B5CF6),
      'orange': Color(0xFFF97316),
      'pink': Color(0xFFEC4899),
      'slate': Color(0xFF64748B),
    };
    if (named.containsKey(s)) return named[s];
    var hex = s;
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 6) {
      final n = int.tryParse(hex, radix: 16);
      if (n != null) return Color(0xFF000000 | n);
    }
    return null;
  }
}

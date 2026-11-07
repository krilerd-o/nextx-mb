import 'package:flutter/material.dart';
import '../core/i18n.dart';

/// หัวข้อย่อยสำหรับกลุ่มการ์ด (mobile-first)
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.padding = const EdgeInsets.only(bottom: 8)});
  final String title;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        tr(title),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

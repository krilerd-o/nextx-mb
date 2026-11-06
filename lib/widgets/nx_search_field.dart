import 'package:flutter/material.dart';
import 'nx_icons.dart';

class NxSearchField extends StatelessWidget {
  const NxSearchField({
    super.key,
    required this.controller,
    this.hint = 'ค้นหา',
    this.onSubmitted,
    this.suffix,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(NxI.magnifyingGlass),
        suffixIcon: suffix,
        isDense: true,
      ),
    );
  }
}

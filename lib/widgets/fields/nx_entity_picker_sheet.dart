import 'dart:async';

import 'package:flutter/material.dart';

import '../nx_avatar.dart';
import 'nx_field_chrome.dart';
import 'nx_lift_sheet.dart';
import 'nx_pick_option.dart';
import '../nx_icons.dart';

Future<NxPickOption?> showNxEntityPickerSheet({
  required BuildContext context,
  required String title,
  required Future<List<NxPickOption>> Function(String query) search,
  NxPickOption? current,
  bool users = false,
}) {
  return showNxLiftSheet<NxPickOption>(
    context: context,
    builder: (ctx, scroll) => _NxEntityPickerBody(
      title: title,
      search: search,
      current: current,
      users: users,
      scroll: scroll,
    ),
  );
}

class _NxEntityPickerBody extends StatefulWidget {
  const _NxEntityPickerBody({
    required this.title,
    required this.search,
    required this.scroll,
    this.current,
    this.users = false,
  });

  final String title;
  final Future<List<NxPickOption>> Function(String query) search;
  final ScrollController scroll;
  final NxPickOption? current;
  final bool users;

  @override
  State<_NxEntityPickerBody> createState() => _NxEntityPickerBodyState();
}

class _NxEntityPickerBodyState extends State<_NxEntityPickerBody> {
  final _q = TextEditingController();
  List<NxPickOption> _options = [];
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    setState(() => _loading = true);
    try {
      final rows = await widget.search(q);
      if (mounted) {
        setState(() {
          _options = rows;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () => _load(q));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: [
              Expanded(child: Text(widget.title, style: theme.textTheme.titleMedium)),
              if (widget.current != null)
                TextButton(
                  onPressed: () => Navigator.pop(context, const NxPickOption(value: '', label: '')),
                  child: const Text('ล้าง'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _q,
            onChanged: _onQuery,
            decoration: NxFieldStyle.decoration(
              context,
              hint: 'ค้นหา',
              prefixIcon: const Icon(NxI.magnifyingGlass),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView.builder(
            controller: widget.scroll,
            itemCount: _options.length,
            itemBuilder: (context, i) {
              final opt = _options[i];
              final selected = widget.current?.value == opt.value;
              return ListTile(
                leading: NxAvatar(label: opt.label, size: 40),
                title: Text(opt.label),
                subtitle: opt.subtitle == null ? null : Text(opt.subtitle!),
                trailing: selected ? const Icon(NxI.check) : null,
                onTap: () => Navigator.pop(context, opt),
              );
            },
          ),
        ),
      ],
    );
  }
}

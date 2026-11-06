import 'package:flutter/material.dart';

import '../nx_avatar.dart';
import 'nx_field_chrome.dart';
import 'nx_lift_sheet.dart';
import 'nx_pick_option.dart';
import '../nx_icons.dart';

Future<String?> showNxPickerSheet({
  required BuildContext context,
  required String title,
  required List<NxPickOption> options,
  String? value,
  bool radio = false,
  Future<List<NxPickOption>> Function(String query)? onSearch,
}) {
  return showNxLiftSheet<String>(
    context: context,
    builder: (ctx, scroll) => _NxPickerBody(
      title: title,
      options: options,
      value: value,
      radio: radio,
      onSearch: onSearch,
      scroll: scroll,
    ),
  );
}

Future<Set<String>?> showNxMultiPickerSheet({
  required BuildContext context,
  required String title,
  required List<NxPickOption> options,
  required Set<String> values,
  Future<List<NxPickOption>> Function(String query)? onSearch,
  bool users = false,
}) {
  return showNxLiftSheet<Set<String>>(
    context: context,
    builder: (ctx, scroll) => _NxMultiPickerBody(
      title: title,
      options: options,
      values: values,
      onSearch: onSearch,
      users: users,
      scroll: scroll,
    ),
  );
}

class _NxPickerBody extends StatefulWidget {
  const _NxPickerBody({
    required this.title,
    required this.options,
    required this.scroll,
    this.value,
    this.radio = false,
    this.onSearch,
  });

  final String title;
  final List<NxPickOption> options;
  final ScrollController scroll;
  final String? value;
  final bool radio;
  final Future<List<NxPickOption>> Function(String query)? onSearch;

  @override
  State<_NxPickerBody> createState() => _NxPickerBodyState();
}

class _NxPickerBodyState extends State<_NxPickerBody> {
  final _q = TextEditingController();
  late List<NxPickOption> _options;

  @override
  void initState() {
    super.initState();
    _options = widget.options;
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (widget.onSearch != null) {
      final next = await widget.onSearch!(q);
      if (mounted) setState(() => _options = next);
      return;
    }
    final lower = q.trim().toLowerCase();
    setState(() {
      _options = lower.isEmpty
          ? widget.options
          : widget.options
              .where((o) =>
                  o.label.toLowerCase().contains(lower) ||
                  o.value.toLowerCase().contains(lower) ||
                  (o.subtitle ?? '').toLowerCase().contains(lower))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(widget.title, style: theme.textTheme.titleMedium),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _q,
            onChanged: _search,
            decoration: NxFieldStyle.decoration(
              context,
              hint: 'ค้นหา',
              prefixIcon: const Icon(NxI.magnifyingGlass),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            controller: widget.scroll,
            itemCount: _options.length,
            itemBuilder: (context, i) {
              final opt = _options[i];
              final selected = opt.value == widget.value;
              return ListTile(
                leading: widget.radio
                    ? Icon(
                        selected ? NxI.radioButton : NxI.circle,
                        color: selected ? Theme.of(context).colorScheme.primary : null,
                      )
                    : (opt.color != null
                        ? Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: opt.color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          )
                        : null),
                title: Text('${opt.emoji ?? ''}${opt.emoji != null ? ' ' : ''}${opt.label}'),
                subtitle: opt.subtitle == null ? null : Text(opt.subtitle!),
                trailing: selected ? const Icon(NxI.check) : null,
                selected: selected,
                onTap: () => Navigator.pop(context, opt.value),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NxMultiPickerBody extends StatefulWidget {
  const _NxMultiPickerBody({
    required this.title,
    required this.options,
    required this.values,
    required this.scroll,
    this.onSearch,
    this.users = false,
  });

  final String title;
  final List<NxPickOption> options;
  final Set<String> values;
  final ScrollController scroll;
  final Future<List<NxPickOption>> Function(String query)? onSearch;
  final bool users;

  @override
  State<_NxMultiPickerBody> createState() => _NxMultiPickerBodyState();
}

class _NxMultiPickerBodyState extends State<_NxMultiPickerBody> {
  final _q = TextEditingController();
  late List<NxPickOption> _options;
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _options = widget.options;
    _selected = {...widget.values};
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (widget.onSearch != null) {
      final next = await widget.onSearch!(q);
      if (mounted) setState(() => _options = next);
      return;
    }
    final lower = q.trim().toLowerCase();
    setState(() {
      _options = lower.isEmpty
          ? widget.options
          : widget.options.where((o) => o.label.toLowerCase().contains(lower)).toList();
    });
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
              TextButton(
                onPressed: () => Navigator.pop(context, _selected),
                child: const Text('ตกลง'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _q,
            onChanged: _search,
            decoration: NxFieldStyle.decoration(
              context,
              hint: 'ค้นหา',
              prefixIcon: const Icon(NxI.magnifyingGlass),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            controller: widget.scroll,
            itemCount: _options.length,
            itemBuilder: (context, i) {
              final opt = _options[i];
              final on = _selected.contains(opt.value);
              return CheckboxListTile(
                value: on,
                secondary: widget.users ? NxAvatar(label: opt.label, size: 36) : null,
                title: Text(opt.label),
                subtitle: opt.subtitle == null ? null : Text(opt.subtitle!),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selected.add(opt.value);
                    } else {
                      _selected.remove(opt.value);
                    }
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/entity_modules.dart';
import '../../core/html_display.dart';
import '../../widgets/nx_html_view.dart';
import 'field_format.dart';
import 'field_ui_type.dart';
import 'nx_field_chrome.dart';
import 'nx_pick_option.dart';
import '../../core/i18n.dart';

class NxFieldValueView extends StatelessWidget {
  const NxFieldValueView({
    super.key,
    required this.uiType,
    required this.label,
    this.value,
    this.options = const [],
    this.onOpen,
    this.relatedModule,
  });

  final FieldUiType uiType;
  final String label;
  final dynamic value;
  final List<NxPickOption> options;
  final VoidCallback? onOpen;
  final String? relatedModule;

  String _displayRaw() {
    final v = value;
    if (v is Map) {
      final l = (v['label'] ?? v['name'] ?? '').toString();
      if (l.isNotEmpty) return l;
      return (v['id'] ?? v['value'] ?? '').toString();
    }
    return v?.toString() ?? '';
  }

  String _labelFor(String raw) {
    for (final o in options) {
      if (o.value == raw) return o.label;
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              tr(label),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: _value(context)),
        ],
      ),
    );
  }

  Widget _value(BuildContext context) {
    final theme = Theme.of(context);
    if (value == null || value.toString().trim().isEmpty) {
      return Text(tr('—'), style: theme.textTheme.bodyMedium);
    }
    switch (uiType) {
      case FieldUiType.yesNo:
        return Align(
          alignment: Alignment.centerLeft,
          child: _chip(context, isTruthyFieldValue(value) ? 'ใช่' : 'ไม่'),
        );
      case FieldUiType.enumeration:
      case FieldUiType.picklist:
      case FieldUiType.radioGroup:
      case FieldUiType.emotionalEmoji:
      case FieldUiType.picklistUser:
      case FieldUiType.owner:
      case FieldUiType.assignTo:
      case FieldUiType.leadSelect:
      case FieldUiType.accountSelect:
      case FieldUiType.contactSelect:
      case FieldUiType.productSelect:
      case FieldUiType.serviceSelect:
      case FieldUiType.quotationSelect:
      case FieldUiType.assetSelect:
      case FieldUiType.jobSelect:
      case FieldUiType.locationSelect:
      case FieldUiType.caseSelect:
      case FieldUiType.contractSelect:
      case FieldUiType.inspectionSelect:
      case FieldUiType.skillSelect:
        final raw = _displayRaw();
        NxPickOption? opt;
        for (final o in options) {
          if (o.value == raw || o.label == raw) opt = o;
        }
        final module = relatedModule ?? uiType.entityModule;
        final recId = lookupRecordId(value);
        final label = opt?.label ?? _labelFor(raw);
        final shouldLookup = module != null &&
            recId.isNotEmpty &&
            (opt == null || opt.label == raw || lookLikeId(label));
        final Widget chip;
        if (module != null && shouldLookup) {
          chip = _LookupChip(
            module: module,
            id: recId,
            fallback: lookLikeId(label) ? '${EntityModules.titleOf(module)} #$recId' : label,
            color: opt?.color,
            onOpen: onOpen,
          );
        } else {
          chip = _chip(context, label, color: opt?.color);
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: onOpen == null || shouldLookup
              ? chip
              : InkWell(
                  onTap: onOpen,
                  borderRadius: BorderRadius.circular(20),
                  child: chip,
                ),
        );
      case FieldUiType.multiSelect:
      case FieldUiType.tag:
      case FieldUiType.multiPicklistUser:
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final v in splitMulti(value)) _chip(context, _labelFor(v)),
          ],
        );
      case FieldUiType.color:
        final hex = displayHexColor(value);
        Color? parsed;
        if (hex.length == 7 && hex.startsWith('#')) {
          parsed = Color(int.parse('FF${hex.substring(1)}', radix: 16));
        }
        return Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: parsed,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.4)),
              ),
            ),
            const SizedBox(width: 8),
            Text(tr(hex), style: theme.textTheme.bodyMedium),
          ],
        );
      case FieldUiType.percent:
      case FieldUiType.progress:
        final p = clampPercent(value);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('${p.round()}%'), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: p / 100, minHeight: 6),
            ),
          ],
        );
      case FieldUiType.richText:
      case FieldUiType.longText:
        final raw = _displayRaw();
        if (looksLikeHtmlString(raw) || uiType == FieldUiType.richText) {
          return NxHtmlView(html: raw, style: theme.textTheme.bodyMedium);
        }
        return SelectableText(tr(_labelFor(raw)), style: theme.textTheme.bodyMedium);
      default:
        final raw = _displayRaw();
        if (looksLikeHtmlString(raw)) {
          return NxHtmlView(html: raw, style: theme.textTheme.bodyMedium);
        }
        return SelectableText(tr(_labelFor(raw)), style: theme.textTheme.bodyMedium);
    }
  }

  Widget _chip(BuildContext context, String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? Theme.of(context).colorScheme.surfaceContainerHighest).withValues(alpha: color == null ? 1 : 0.18),
        borderRadius: BorderRadius.circular(NxFieldStyle.radius),
      ),
      child: Text(
        tr(text),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
      ),
    );
  }
}

bool lookLikeId(String s) => RegExp(r'^\d+$').hasMatch(s.trim());

class _LookupChip extends StatefulWidget {
  const _LookupChip({
    required this.module,
    required this.id,
    required this.fallback,
    this.color,
    this.onOpen,
  });

  final String module;
  final String id;
  final String fallback;
  final Color? color;
  final VoidCallback? onOpen;

  @override
  State<_LookupChip> createState() => _LookupChipState();
}

class _LookupChipState extends State<_LookupChip> {
  String? _label;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.read<AppConfig>().apiClient;
      if (api.accessToken == null || api.accessToken!.isEmpty) return;
      final row = await api.getEntity(widget.module, widget.id);
      if (!mounted) return;
      final title = entityTitle(row, module: widget.module);
      if (title.isNotEmpty && title != 'ID ${widget.id}' && title != '${widget.module} #${widget.id}') {
        setState(() => _label = title);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (widget.color ?? Theme.of(context).colorScheme.surfaceContainerHighest)
            .withValues(alpha: widget.color == null ? 1 : 0.18),
        borderRadius: BorderRadius.circular(NxFieldStyle.radius),
      ),
      child: Text(
        tr(_label ?? widget.fallback),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: widget.color),
      ),
    );
    if (widget.onOpen == null) return chip;
    return InkWell(
      onTap: widget.onOpen,
      borderRadius: BorderRadius.circular(20),
      child: chip,
    );
  }
}

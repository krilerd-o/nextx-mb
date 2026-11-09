import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/html_display.dart';
import '../../core/nx_breakpoint.dart';
import '../nx_avatar.dart';
import '../nx_html_view.dart';
import 'field_format.dart';
import 'field_ui_type.dart';
import 'nx_canvas_field.dart';
import 'nx_entity_picker_sheet.dart';
import 'nx_field_chrome.dart';
import 'nx_lift_sheet.dart';
import 'nx_pick_option.dart';
import 'nx_picker_sheet.dart';
import '../nx_icons.dart';
import '../../core/thai_time.dart';
import '../../core/i18n.dart';

const kFieldLocale = Locale('th', 'TH');

enum NxMediaKind { file, image, video }

class NxFieldHost {
  const NxFieldHost({
    this.loadUsers,
    this.loadEntities,
    this.loadTags,
    this.loadPackages,
    this.loadPicklist,
    this.pickMedia,
    this.uploadBytes,
    this.captureGps,
  });

  final Future<List<NxPickOption>> Function(String query)? loadUsers;
  final Future<List<NxPickOption>> Function(String module, String query)? loadEntities;
  final Future<List<NxPickOption>> Function(String query)? loadTags;
  final Future<List<NxPickOption>> Function()? loadPackages;
  final Future<List<NxPickOption>> Function(String name)? loadPicklist;
  final Future<String?> Function(NxMediaKind kind)? pickMedia;
  final Future<String?> Function(List<int> bytes, String filename)? uploadBytes;
  final Future<({double lat, double lng})?> Function()? captureGps;
}

class NxFormField extends StatelessWidget {
  const NxFormField({
    super.key,
    required this.uiType,
    required this.label,
    this.value,
    this.onChanged,
    this.options = const [],
    this.required = false,
    this.enabled = true,
    this.readOnly = false,
    this.errorText,
    this.hint,
    this.host,
    this.canonicalName,
    this.name,
  });

  final FieldUiType uiType;
  final String label;
  final dynamic value;
  final ValueChanged<dynamic>? onChanged;
  final List<NxPickOption> options;
  final bool required;
  final bool enabled;
  final bool readOnly;
  final String? errorText;
  final String? hint;
  final NxFieldHost? host;
  final String? canonicalName;
  final String? name;

  String get _wire => canonicalName ?? uiType.wireName;
  bool get _on => enabled && !readOnly;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey('nx-field-${name ?? _wire}'),
      child: _control(context),
    );
  }

  Widget _text({
    required String text,
    ValueChanged<String>? onChanged,
    String? hint,
    TextInputType? keyboard,
    int maxLines = 1,
    TextAlign align = TextAlign.start,
    Widget? prefix,
    Widget? suffix,
    List<TextInputFormatter>? inputFormatters,
    bool enabled = true,
  }) {
    return _TextBox(
      text: text,
      onChanged: onChanged,
      hint: hint,
      keyboard: keyboard,
      maxLines: maxLines,
      align: align,
      prefix: prefix,
      suffix: suffix,
      inputFormatters: inputFormatters,
      enabled: enabled,
      label: label,
      required: required,
      errorText: trn(errorText),
    );
  }

  Widget _wrap(BuildContext context, {required Widget child, required bool isEmpty}) {
    return InputDecorator(
      isEmpty: isEmpty,
      decoration: NxFieldStyle.decoration(
        context,
        label: label,
        required: required,
        errorText: trn(errorText),
        floatLabel: !isEmpty,
      ),
      child: child,
    );
  }

  Widget _control(BuildContext context) {
    switch (uiType) {
      case FieldUiType.longText:
      case FieldUiType.address:
        return _text(
          text: value?.toString() ?? '',
          onChanged: _on ? (v) => onChanged?.call(v) : null,
          hint: hint,
          maxLines: uiType == FieldUiType.address ? 4 : 5,
          enabled: _on,
        );
      case FieldUiType.richText:
        return _wrap(
          context,
          isEmpty: (value?.toString() ?? '').isEmpty,
          child: _RichTextBox(
            html: value?.toString() ?? '',
            onChanged: _on ? (v) => onChanged?.call(v) : null,
            enabled: _on,
          ),
        );
      case FieldUiType.email:
        return _text(
          text: value?.toString() ?? '',
          onChanged: _on ? (v) => onChanged?.call(v) : null,
          hint: hint ?? 'name@email.com',
          keyboard: TextInputType.emailAddress,
          prefix: IconButton(
            tooltip: tr('ส่งอีเมล'),
            onPressed: () => _launchAction(FieldUiType.email, value?.toString()),
            icon: Icon(nxTypeIcon(IconDataSpec.email), size: 20, color: _muted(context)),
          ),
          enabled: _on,
        );
      case FieldUiType.phone:
        return _text(
          text: formatPhoneDisplay(value),
          onChanged: _on ? (v) => onChanged?.call(digitsOnly(v, 10)) : null,
          hint: hint ?? '0xx-xxx-xxxx',
          keyboard: TextInputType.phone,
          prefix: IconButton(
            tooltip: tr('โทร'),
            onPressed: () => _launchAction(FieldUiType.phone, digitsOnly(value, 10)),
            icon: Icon(nxTypeIcon(IconDataSpec.phone), size: 20, color: _muted(context)),
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
          enabled: _on,
        );
      case FieldUiType.link:
        return _text(
          text: value?.toString() ?? '',
          onChanged: _on ? (v) => onChanged?.call(v) : null,
          hint: hint ?? 'https://',
          keyboard: TextInputType.url,
          prefix: IconButton(
            tooltip: tr('เปิดลิงก์'),
            onPressed: () => _launchAction(FieldUiType.link, value?.toString()),
            icon: Icon(nxTypeIcon(IconDataSpec.link), size: 20, color: _muted(context)),
          ),
          enabled: _on,
        );
      case FieldUiType.taxId:
        return _text(
          text: formatTaxIdDisplay(value),
          onChanged: _on ? (v) => onChanged?.call(digitsOnly(v, 13)) : null,
          hint: 'x-xxxx-xxxxx-xx-x',
          keyboard: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(13)],
          enabled: _on,
        );
      case FieldUiType.number:
      case FieldUiType.counter:
        return _text(
          text: value?.toString() ?? '',
          onChanged: _on && !readOnly ? (v) => onChanged?.call(v) : null,
          keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true),
          align: TextAlign.right,
          enabled: _on && !readOnly,
        );
      case FieldUiType.currency:
        return _text(
          text: value?.toString() ?? '',
          onChanged: _on ? (v) => onChanged?.call(v) : null,
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          align: TextAlign.right,
          prefix: Padding(
            padding: EdgeInsets.only(left: 12, top: 12),
            child: Text(tr('฿')),
          ),
          enabled: _on,
        );
      case FieldUiType.duration:
        return _text(
          text: value?.toString() ?? '',
          onChanged: _on ? (v) => onChanged?.call(v) : null,
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          align: TextAlign.right,
          suffix: Padding(
            padding: const EdgeInsets.only(right: 12, top: 12),
            child: Text(tr('กม.'), style: TextStyle(color: _muted(context))),
          ),
          enabled: _on,
        );
      case FieldUiType.percent:
      case FieldUiType.progress:
        return _wrap(
          context,
          isEmpty: false,
          child: _SliderBox(
            value: clampPercent(value),
            onChanged: _on ? (v) => onChanged?.call(v.round().toString()) : null,
            progress: uiType == FieldUiType.progress,
          ),
        );
      case FieldUiType.yesNo:
        return _wrap(
          context,
          isEmpty: false,
          child: _YesNoBox(
            value: isTruthyFieldValue(value),
            onChanged: _on ? (v) => onChanged?.call(yesNoStored(v)) : null,
            label: label,
          ),
        );
      case FieldUiType.date:
        return _DateTrigger(
          fieldLabel: label,
          required: required,
          errorText: trn(errorText),
          text: _dateLabel(value),
          icon: NxI.calendarBlank,
          enabled: _on,
          onTap: () => _pickDate(context),
        );
      case FieldUiType.time:
        return _DateTrigger(
          fieldLabel: label,
          required: required,
          errorText: trn(errorText),
          text: _timeLabel(value),
          icon: NxI.clock,
          enabled: _on,
          onTap: () => _pickTime(context),
        );
      case FieldUiType.dateTime:
        return _DateTrigger(
          fieldLabel: label,
          required: required,
          errorText: trn(errorText),
          text: _dateTimeLabel(value),
          icon: NxI.calendarCheck,
          enabled: _on,
          onTap: () => _pickDateTime(context),
        );
      case FieldUiType.dateRange:
        return _DateTrigger(
          fieldLabel: label,
          required: required,
          errorText: trn(errorText),
          text: _rangeLabel(value, 10, 'เลือกช่วงวันที่'),
          icon: NxI.calendarBlank,
          enabled: _on,
          onTap: () => _pickDateRange(context),
        );
      case FieldUiType.monthRange:
        return _DateTrigger(
          fieldLabel: label,
          required: required,
          errorText: trn(errorText),
          text: _rangeLabel(value, 7, 'เลือกช่วงเดือน'),
          icon: NxI.calendarBlank,
          enabled: _on,
          onTap: () => _pickMonthRange(context),
        );
      case FieldUiType.yearRange:
        return _DateTrigger(
          fieldLabel: label,
          required: required,
          errorText: trn(errorText),
          text: _rangeLabel(value, 4, 'เลือกช่วงปี'),
          icon: NxI.calendarBlank,
          enabled: _on,
          onTap: () => _pickYearRange(context),
        );
      case FieldUiType.monthPicker:
        return _DateTrigger(
          fieldLabel: label,
          required: required,
          errorText: trn(errorText),
          text: value?.toString().isNotEmpty == true ? value.toString() : 'เลือกเดือน',
          icon: NxI.calendarBlank,
          enabled: _on,
          onTap: () => _pickMonth(context),
        );
      case FieldUiType.yearPicker:
        return _DateTrigger(
          fieldLabel: label,
          required: required,
          errorText: trn(errorText),
          text: value?.toString().isNotEmpty == true ? value.toString() : 'เลือกปี',
          icon: NxI.calendarBlank,
          enabled: _on,
          onTap: () => _pickYear(context),
        );
      case FieldUiType.enumeration:
      case FieldUiType.picklist:
      case FieldUiType.radioGroup:
      case FieldUiType.app:
        return _SelectTrigger(
          fieldLabel: label,
          required: required,
          errorText: trn(errorText),
          label: _selectedLabel() ?? hint ?? 'เลือก',
          color: _selectedColor(),
          radio: uiType == FieldUiType.radioGroup,
          enabled: _on,
          onTap: () => _openSelect(context),
          onClear: _lookupId().isNotEmpty && _on ? () => onChanged?.call('') : null,
        );
      case FieldUiType.multiSelect:
        return _ChipTrigger(
          fieldLabel: label,
          required: required,
          errorText: trn(errorText),
          values: splitMulti(value),
          options: options,
          hint: 'เลือกหลายค่า',
          enabled: _on,
          onTap: () => _openMulti(context, users: false),
        );
      case FieldUiType.tag:
        return _ChipTrigger(
          fieldLabel: label,
          required: required,
          errorText: trn(errorText),
          values: splitMulti(value),
          options: options,
          hint: 'เลือกแท็ก',
          enabled: _on,
          onTap: () => _openTags(context),
        );
      case FieldUiType.emotionalEmoji:
        return _wrap(
          context,
          isEmpty: value == null || value.toString().isEmpty,
          child: _EmojiRow(
            value: value?.toString(),
            options: options.isEmpty ? _defaultEmojis : options,
            onChanged: _on ? (v) => onChanged?.call(v) : null,
          ),
        );
      case FieldUiType.picklistUser:
      case FieldUiType.owner:
      case FieldUiType.assignTo:
        return _PersonTrigger(
          fieldLabel: label,
          required: required,
          errorText: trn(errorText),
          label: _selectedLabel() ?? hint ?? 'เลือกผู้ใช้',
          enabled: _on,
          onTap: () => _openUsers(context, multi: false),
          onClear: _lookupId().isNotEmpty && _on ? () => onChanged?.call('') : null,
        );
      case FieldUiType.multiPicklistUser:
        return _ChipTrigger(
          fieldLabel: label,
          required: required,
          errorText: trn(errorText),
          values: splitMulti(value),
          options: options,
          hint: 'เลือกผู้ใช้หลายคน',
          enabled: _on,
          avatars: true,
          onTap: () => _openUsers(context, multi: true),
        );
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
        return _PersonTrigger(
          fieldLabel: label,
          required: required,
          errorText: trn(errorText),
          label: _selectedLabel() ?? hint ?? 'ค้นหาและเลือก',
          enabled: _on,
          onTap: () => _openEntity(context),
          onClear: _lookupId().isNotEmpty && _on ? () => onChanged?.call('') : null,
        );
      case FieldUiType.color:
        return _ColorTrigger(
          fieldLabel: label,
          required: required,
          errorText: trn(errorText),
          hex: displayHexColor(value),
          enabled: _on,
          onTap: () => _pickColor(context),
        );
      case FieldUiType.file:
      case FieldUiType.image:
      case FieldUiType.video:
        return _wrap(
          context,
          isEmpty: value == null || value.toString().isEmpty,
          child: _MediaBox(
            kind: uiType == FieldUiType.image
                ? NxMediaKind.image
                : uiType == FieldUiType.video
                    ? NxMediaKind.video
                    : NxMediaKind.file,
            value: value?.toString(),
            enabled: _on,
            onPick: () => _pickMedia(context),
          ),
        );
      case FieldUiType.drawing:
        return _wrap(
          context,
          isEmpty: value == null || value.toString().isEmpty,
          child: NxCanvasField(
            value: value?.toString(),
            onChanged: _on ? onChanged : null,
            uploadPng: host?.uploadBytes,
          ),
        );
      case FieldUiType.licenseArea:
        return _wrap(
          context,
          isEmpty: value == null || value.toString().isEmpty,
          child: NxCanvasField(
            value: value?.toString(),
            onChanged: _on ? onChanged : null,
            signature: true,
            uploadPng: host?.uploadBytes,
          ),
        );
      case FieldUiType.latLong:
        return _wrap(
          context,
          isEmpty: parseLatLong(value).lat.isEmpty && parseLatLong(value).lng.isEmpty,
          child: _LatLongBox(
            value: value,
            enabled: _on,
            onChanged: onChanged,
            onGps: host?.captureGps,
          ),
        );
      case FieldUiType.addressMap:
        return _wrap(
          context,
          isEmpty: _addressFromMap(value).isEmpty,
          child: Column(
            children: [
              _TextBox(
                text: _addressFromMap(value),
                onChanged: _on
                    ? (v) => onChanged?.call(_mergeAddressMap(value, address: v))
                    : null,
                maxLines: 3,
                hint: 'ที่อยู่',
                enabled: _on,
                bare: true,
              ),
              const SizedBox(height: 8),
              _LatLongBox(
                value: value,
                enabled: _on,
                onChanged: (v) => onChanged?.call(_mergeAddressMap(value, latlng: v?.toString())),
                onGps: host?.captureGps,
              ),
            ],
          ),
        );
      case FieldUiType.xy:
        return _wrap(
          context,
          isEmpty: parseXy(value).x == null,
          child: _XyPad(
            value: value,
            enabled: _on,
            onChanged: onChanged,
          ),
        );
      case FieldUiType.post:
        return _wrap(
          context,
          isEmpty: (parsePost(value)['body']?.toString() ?? '').isEmpty,
          child: _PostBox(
            value: value,
            enabled: _on,
            onChanged: onChanged,
          ),
        );
      case FieldUiType.text:
        return _text(
          text: value?.toString() ?? '',
          onChanged: _on ? (v) => onChanged?.call(v) : null,
          hint: hint,
          enabled: _on,
        );
    }
  }

  Color _muted(BuildContext context) => Theme.of(context).colorScheme.onSurfaceVariant;

  String _lookupId() {
    final v = value;
    if (v is Map) return (v['id'] ?? v['value'] ?? '').toString();
    return v?.toString() ?? '';
  }

  String? _selectedLabel() {
    final v = value;
    if (v is Map) {
      final l = (v['label'] ?? v['name'] ?? '').toString();
      if (l.isNotEmpty) return l;
    }
    final id = _lookupId();
    if (id.isEmpty) return null;
    for (final o in options) {
      if (o.value == id) return o.label;
    }
    if (RegExp(r'^\d+$').hasMatch(id)) return null;
    return id;
  }

  void _storeLookup(NxPickOption picked) {
    if (picked.value.isEmpty) {
      onChanged?.call('');
      return;
    }
    onChanged?.call({'id': picked.value, 'label': picked.label});
  }

  Future<void> _launchAction(FieldUiType type, String? raw) async {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return;
    Uri? uri;
    if (type == FieldUiType.email) {
      uri = Uri.parse('mailto:$s');
    } else if (type == FieldUiType.phone) {
      uri = Uri.parse('tel:$s');
    } else if (type == FieldUiType.link) {
      uri = Uri.parse(s.startsWith('http') ? s : 'https://$s');
    }
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Color? _selectedColor() {
    final v = value?.toString() ?? '';
    for (final o in options) {
      if (o.value == v) return o.color;
    }
    return null;
  }

  String _dateLabel(dynamic raw) {
    final d = parseThaiDate(raw);
    if (d == null) return 'เลือกวันที่';
    return thaiDate(formatYmd(d), year: uiYear);
  }

  /// Date-time as Thai time (`04/11/2569 17:54`), never the raw ISO/UTC text.
  DateTime? _dateTime(dynamic raw) => parseThaiField(raw, name);

  String _dateTimeLabel(dynamic raw) {
    final d = _dateTime(raw);
    if (d == null) return 'เลือกวันและเวลา';
    return '${two(d.day)}/${two(d.month)}/${uiYear(d.year)} ${two(d.hour)}:${two(d.minute)}';
  }

  /// `17:54:00` → `17:54`.
  static String _timeLabel(dynamic raw) {
    final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch('${raw ?? ''}');
    if (m == null) return 'เลือกเวลา';
    return '${m.group(1)!.padLeft(2, '0')}:${m.group(2)}';
  }

  String _rangeLabel(dynamic raw, int slice, String placeholder) {
    final r = parseRange(raw, slice: slice);
    if (r['start']!.isEmpty && r['end']!.isEmpty) return placeholder;
    return '${r['start']} – ${r['end']}';
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = thaiNow();
    final birthday = isBirthdayFieldName(name);
    final saved = parseThaiDate(value);
    // Birthdays: any year since 1900 up to today, opened on a year 30 years
    // back (pick the year first) when empty.
    final first = birthday ? DateTime(1900) : DateTime(now.year - 30);
    final last = birthday ? DateTime(now.year, now.month, now.day) : DateTime(now.year + 15);
    var initial = saved ?? (birthday ? DateTime(now.year - 30, now.month, now.day) : now);
    initial = DateTime(initial.year, initial.month, initial.day);
    final picked = await showDatePicker(
        switchToInputEntryModeIcon: const Icon(NxI.pencilSimple),
        switchToCalendarEntryModeIcon: const Icon(NxI.calendarBlank),
      context: context,
      locale: kFieldLocale,
      initialDate: initial,
      firstDate: _minDay(first, initial),
      lastDate: _maxDay(last, initial),
      initialDatePickerMode: birthday && saved == null ? DatePickerMode.year : DatePickerMode.day,
    );
    if (picked != null) onChanged?.call(formatYmd(picked));
  }

  static DateTime _minDay(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  static DateTime _maxDay(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

  Future<void> _pickTime(BuildContext context) async {
    final parsed = parseDate('1970-01-01T${_timeLabel(value) == 'เลือกเวลา' ? '00:00' : _timeLabel(value)}');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: parsed?.hour ?? 9, minute: parsed?.minute ?? 0),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      onChanged?.call('${two(picked.hour)}:${two(picked.minute)}');
    }
  }

  Future<void> _pickDateTime(BuildContext context) async {
    final now = thaiNow();
    final initial = _dateTime(value) ?? now;
    final day0 = DateTime(initial.year, initial.month, initial.day);
    final day = await showDatePicker(
        switchToInputEntryModeIcon: const Icon(NxI.pencilSimple),
        switchToCalendarEntryModeIcon: const Icon(NxI.calendarBlank),
      context: context,
      locale: kFieldLocale,
      initialDate: day0,
      // Older/newer saved values still open (the picker throws otherwise).
      firstDate: _minDay(DateTime(now.year - 30), day0),
      lastDate: _maxDay(DateTime(now.year + 15), day0),
    );
    if (day == null || !context.mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null) return;
    onChanged?.call('${formatYmd(day)}T${two(t.hour)}:${two(t.minute)}:00');
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final r = parseRange(value);
    final start = parseDate(r['start']) ?? thaiNow();
    final a = await showDatePicker(
        switchToInputEntryModeIcon: const Icon(NxI.pencilSimple),
        switchToCalendarEntryModeIcon: const Icon(NxI.calendarBlank),
      context: context,
      locale: kFieldLocale,
      initialDate: start,
      firstDate: DateTime(thaiNow().year - 30),
      lastDate: DateTime(thaiNow().year + 15),
      helpText: 'วันเริ่ม',
    );
    if (a == null || !context.mounted) return;
    final b = await showDatePicker(
        switchToInputEntryModeIcon: const Icon(NxI.pencilSimple),
        switchToCalendarEntryModeIcon: const Icon(NxI.calendarBlank),
      context: context,
      locale: kFieldLocale,
      initialDate: parseDate(r['end']) ?? a,
      firstDate: a,
      lastDate: DateTime(thaiNow().year + 15),
      helpText: 'วันสิ้นสุด',
    );
    if (b == null) return;
    onChanged?.call(formatRange(formatYmd(a), formatYmd(b)));
  }

  Future<void> _pickMonth(BuildContext context) async {
    final now = thaiNow();
    final cur = parseDate('${value ?? now.year}-${two(now.month)}-01') ?? now;
    final picked = await showDatePicker(
        switchToInputEntryModeIcon: const Icon(NxI.pencilSimple),
        switchToCalendarEntryModeIcon: const Icon(NxI.calendarBlank),
      context: context,
      locale: kFieldLocale,
      initialDate: cur,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 10),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) onChanged?.call('${picked.year}-${two(picked.month)}');
  }

  Future<void> _pickYear(BuildContext context) async {
    final years = [for (var y = thaiNow().year + 5; y >= thaiNow().year - 30; y--) y.toString()];
    final picked = await showNxPickerSheet(
      context: context,
      title: label,
      options: [for (final y in years) NxPickOption(value: y, label: y)],
      value: value?.toString(),
    );
    if (picked != null) onChanged?.call(picked);
  }

  Future<void> _pickMonthRange(BuildContext context) async {
    final r = parseRange(value, slice: 7);
    final a = await showDatePicker(
        switchToInputEntryModeIcon: const Icon(NxI.pencilSimple),
        switchToCalendarEntryModeIcon: const Icon(NxI.calendarBlank),
      context: context,
      locale: kFieldLocale,
      initialDate: parseDate('${r['start']}-01') ?? thaiNow(),
      firstDate: DateTime(thaiNow().year - 20),
      lastDate: DateTime(thaiNow().year + 10),
      helpText: 'เดือนเริ่ม',
    );
    if (a == null || !context.mounted) return;
    final b = await showDatePicker(
        switchToInputEntryModeIcon: const Icon(NxI.pencilSimple),
        switchToCalendarEntryModeIcon: const Icon(NxI.calendarBlank),
      context: context,
      locale: kFieldLocale,
      initialDate: parseDate('${r['end']}-01') ?? a,
      firstDate: a,
      lastDate: DateTime(thaiNow().year + 10),
      helpText: 'เดือนสิ้นสุด',
    );
    if (b == null) return;
    onChanged?.call(formatRange('${a.year}-${two(a.month)}', '${b.year}-${two(b.month)}'));
  }

  Future<void> _pickYearRange(BuildContext context) async {
    final r = parseRange(value, slice: 4);
    final years = [for (var y = thaiNow().year + 5; y >= thaiNow().year - 30; y--) y.toString()];
    final opts = [for (final y in years) NxPickOption(value: y, label: y)];
    final a = await showNxPickerSheet(context: context, title: 'ปีเริ่ม', options: opts, value: r['start']);
    if (a == null || !context.mounted) return;
    final b = await showNxPickerSheet(context: context, title: 'ปีสิ้นสุด', options: opts, value: r['end']);
    if (b == null) return;
    onChanged?.call(formatRange(a, b));
  }

  Future<void> _openSelect(BuildContext context) async {
    var opts = options;
    if (uiType == FieldUiType.app && host?.loadPackages != null) {
      opts = await host!.loadPackages!();
    }
    final pickName = name ?? canonicalName;
    if (opts.isEmpty && host?.loadPicklist != null && pickName != null && pickName.isNotEmpty) {
      opts = await host!.loadPicklist!(pickName);
    }
    if (!context.mounted) return;
    final picked = await showNxPickerSheet(
      context: context,
      title: label,
      options: opts,
      value: _lookupId(),
      radio: uiType == FieldUiType.radioGroup,
    );
    if (picked != null) onChanged?.call(picked);
  }

  Future<void> _openMulti(BuildContext context, {required bool users}) async {
    final picked = await showNxMultiPickerSheet(
      context: context,
      title: label,
      options: options,
      values: splitMulti(value).toSet(),
      users: users,
    );
    if (picked != null) onChanged?.call(joinMulti(picked));
  }

  Future<void> _openTags(BuildContext context) async {
    var opts = options;
    if (host?.loadTags != null) {
      opts = await host!.loadTags!('');
    }
    if (!context.mounted) return;
    final picked = await showNxMultiPickerSheet(
      context: context,
      title: label,
      options: opts,
      values: splitMulti(value).toSet(),
      onSearch: host?.loadTags,
    );
    if (picked != null) onChanged?.call(joinMulti(picked));
  }

  Future<void> _openUsers(BuildContext context, {required bool multi}) async {
    if (multi) {
      var opts = options;
      if (host?.loadUsers != null) opts = await host!.loadUsers!('');
      if (!context.mounted) return;
      final picked = await showNxMultiPickerSheet(
        context: context,
        title: label,
        options: opts,
        values: splitMulti(value).toSet(),
        onSearch: host?.loadUsers,
        users: true,
      );
      if (picked != null) onChanged?.call(joinMulti(picked));
      return;
    }
    if (host?.loadUsers != null) {
      final picked = await showNxEntityPickerSheet(
        context: context,
        title: label,
        search: host!.loadUsers!,
        current: _lookupId().isEmpty
            ? null
            : NxPickOption(value: _lookupId(), label: _selectedLabel() ?? _lookupId()),
        users: true,
      );
      if (picked != null) _storeLookup(picked);
      return;
    }
    final picked = await showNxPickerSheet(
      context: context,
      title: label,
      options: options,
      value: _lookupId(),
    );
    if (picked != null) onChanged?.call(picked);
  }

  Future<void> _openEntity(BuildContext context) async {
    final module = uiType.entityModule;
    if (module == null) return;
    if (host?.loadEntities != null) {
      final picked = await showNxEntityPickerSheet(
        context: context,
        title: label,
        search: (q) => host!.loadEntities!(module, q),
        current: _lookupId().isEmpty
            ? null
            : NxPickOption(value: _lookupId(), label: _selectedLabel() ?? _lookupId()),
      );
      if (picked != null) _storeLookup(picked);
      return;
    }
    final picked = await showNxPickerSheet(
      context: context,
      title: label,
      options: options,
      value: _lookupId(),
    );
    if (picked != null) onChanged?.call(picked);
  }

  Future<void> _pickColor(BuildContext context) async {
    const swatches = [
      '#EF4444',
      '#F97316',
      '#F59E0B',
      '#10B981',
      '#0EA5E9',
      '#6366F1',
      '#8B5CF6',
      '#EC4899',
      '#111827',
      '#6B7280',
    ];
    final picked = await showNxLiftSheet<String>(
      context: context,
      builder: (ctx, scroll) {
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text(tr(label), style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final hex in swatches)
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx, hex),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(int.parse('FF${hex.substring(1)}', radix: 16)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
    if (picked != null) onChanged?.call(picked);
  }

  Future<void> _pickMedia(BuildContext context) async {
    final kind = uiType == FieldUiType.image
        ? NxMediaKind.image
        : uiType == FieldUiType.video
            ? NxMediaKind.video
            : NxMediaKind.file;
    final stored = await host?.pickMedia?.call(kind);
    if (stored != null) onChanged?.call(stored);
  }

  String _addressFromMap(dynamic raw) {
    if (raw is Map) return (raw['address'] ?? raw['value'] ?? '').toString();
    final s = raw?.toString() ?? '';
    if (s.startsWith('{')) {
      try {
        // ignore: avoid_dynamic_calls
        return parseRange(s)['start'] ?? s;
      } catch (_) {}
    }
    return s.contains(',') ? '' : s;
  }

  String _mergeAddressMap(dynamic raw, {String? address, String? latlng}) {
    final ll = parseLatLong(latlng ?? raw);
    final addr = address ?? _addressFromMap(raw);
    return formatRange(addr, formatLatLong(ll.lat, ll.lng));
  }
}

const _defaultEmojis = [
  NxPickOption(value: 'happy', label: 'ยิ้ม', emoji: '😀'),
  NxPickOption(value: 'neutral', label: 'เฉย', emoji: '😐'),
  NxPickOption(value: 'sad', label: 'เศร้า', emoji: '😞'),
  NxPickOption(value: 'angry', label: 'โกรธ', emoji: '😡'),
  NxPickOption(value: 'love', label: 'ชอบ', emoji: '😍'),
];

class _TextBox extends StatefulWidget {
  const _TextBox({
    required this.text,
    this.onChanged,
    this.hint,
    this.keyboard,
    this.maxLines = 1,
    this.align = TextAlign.start,
    this.prefix,
    this.suffix,
    this.inputFormatters,
    this.enabled = true,
    this.label,
    this.required = false,
    this.errorText,
    this.bare = false,
  });

  final String text;
  final ValueChanged<String>? onChanged;
  final String? hint;
  final TextInputType? keyboard;
  final int maxLines;
  final TextAlign align;
  final Widget? prefix;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final String? label;
  final bool required;
  final String? errorText;
  final bool bare;

  @override
  State<_TextBox> createState() => _TextBoxState();
}

class _TextBoxState extends State<_TextBox> {
  late final TextEditingController _c;
  var _focused = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.text);
  }

  @override
  void didUpdateWidget(covariant _TextBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != _c.text) {
      _c.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (has) {
        setState(() => _focused = has);
        if (!has) return;
        Future.delayed(const Duration(milliseconds: 280), () {
          if (!context.mounted) return;
          Scrollable.ensureVisible(
            context,
            alignment: 0.15,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        });
      },
      child: AnimatedScale(
        scale: _focused ? 1.015 : 1,
        duration: nxMotion(context, 200),
        curve: NxMotion.settleCurve,
        child: TextField(
          controller: _c,
          enabled: widget.enabled,
          maxLines: widget.maxLines,
          minLines: widget.maxLines > 1 ? widget.maxLines : null,
          keyboardType: widget.keyboard,
          textAlign: widget.align,
          textAlignVertical: widget.maxLines > 1 ? TextAlignVertical.top : TextAlignVertical.center,
          inputFormatters: widget.inputFormatters,
          onChanged: widget.onChanged,
          decoration: widget.bare
              ? InputDecoration(
                  hintText: trn(widget.hint),
                  border: InputBorder.none,
                  isDense: true,
                  prefixIcon: widget.prefix,
                  suffixIcon: widget.suffix,
                )
              : NxFieldStyle.decoration(
                  context,
                  label: widget.label,
                  required: widget.required,
                  hint: widget.hint,
                  prefixIcon: widget.prefix,
                  suffixIcon: widget.suffix,
                  errorText: trn(widget.errorText),
                  maxLines: widget.maxLines,
                  floatLabel: _focused || widget.text.trim().isNotEmpty,
                ),
        ),
      ),
    );
  }
}

class _RichTextBox extends StatelessWidget {
  const _RichTextBox({required this.html, this.onChanged, this.enabled = true});
  final String html;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  String get _plain {
    return stripHtmlPreview(html, maxLen: 8000);
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return NxHtmlView(html: html);
    }
    return Column(
      children: [
        if (looksLikeHtmlString(html)) ...[
          Align(alignment: Alignment.centerLeft, child: NxHtmlView(html: html)),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            IconButton(
              tooltip: tr('ตัวหนา'),
              onPressed: () => onChanged?.call('<b>$_plain</b>'),
              icon: const Icon(NxI.textB, size: 20),
            ),
            IconButton(
              tooltip: tr('รายการ'),
              onPressed: () => onChanged?.call('<ul><li>$_plain</li></ul>'),
              icon: const Icon(NxI.listBullets, size: 20),
            ),
          ],
        ),
        _TextBox(
          text: _plain,
          onChanged: onChanged,
          maxLines: 5,
          enabled: enabled,
          bare: true,
        ),
      ],
    );
  }
}

class _SliderBox extends StatelessWidget {
  const _SliderBox({required this.value, this.onChanged, this.progress = false});
  final double value;
  final ValueChanged<double>? onChanged;
  final bool progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (progress)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: value / 100, minHeight: 8),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: value,
                min: 0,
                max: 100,
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(tr('${value.round()}%'), textAlign: TextAlign.end),
            ),
          ],
        ),
      ],
    );
  }
}

class _YesNoBox extends StatelessWidget {
  const _YesNoBox({required this.value, this.onChanged, required this.label});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(tr(value ? 'ใช่' : 'ไม่'), style: Theme.of(context).textTheme.bodyLarge)),
        Switch.adaptive(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _DateTrigger extends StatelessWidget {
  const _DateTrigger({
    required this.fieldLabel,
    required this.text,
    required this.icon,
    required this.onTap,
    this.required = false,
    this.errorText,
    this.enabled = true,
  });
  final String fieldLabel;
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final bool required;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final empty = text.startsWith('เลือก');
    return NxOutlinedTapField(
      label: fieldLabel,
      required: required,
      errorText: trn(errorText),
      isEmpty: empty,
      enabled: enabled,
      onTap: onTap,
      prefixIcon: Icon(icon, size: 20, color: muted),
      child: empty ? const SizedBox(height: NxFieldStyle.lineHeight) : Text(tr(text)),
    );
  }
}

class _SelectTrigger extends StatelessWidget {
  const _SelectTrigger({
    required this.fieldLabel,
    required this.label,
    required this.onTap,
    this.required = false,
    this.errorText,
    this.color,
    this.radio = false,
    this.enabled = true,
    this.onClear,
  });
  final String fieldLabel;
  final String label;
  final VoidCallback onTap;
  final bool required;
  final String? errorText;
  final Color? color;
  final bool radio;
  final bool enabled;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final empty = label.startsWith('เลือก') || label.isEmpty;
    return NxOutlinedTapField(
      label: fieldLabel,
      required: required,
      errorText: trn(errorText),
      isEmpty: empty,
      enabled: enabled,
      onTap: onTap,
      prefixIcon: Icon(NxI.listBullets, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
      suffixIcon: Icon(NxI.caretDown, color: Theme.of(context).colorScheme.onSurfaceVariant),
      child: empty
          ? const SizedBox(height: NxFieldStyle.lineHeight)
          : Row(
              children: [
                if (radio)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(NxI.radioButton, size: 16, color: Theme.of(context).colorScheme.primary),
                  )
                else if (color != null)
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                  ),
                Expanded(child: Text(tr(label), overflow: TextOverflow.ellipsis)),
                if (onClear != null)
                  IconButton(
                    icon: const Icon(NxI.x, size: 18),
                    onPressed: onClear,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
    );
  }
}

class _PersonTrigger extends StatelessWidget {
  const _PersonTrigger({
    required this.fieldLabel,
    required this.label,
    required this.onTap,
    this.required = false,
    this.errorText,
    this.enabled = true,
    this.onClear,
  });
  final String fieldLabel;
  final String label;
  final VoidCallback onTap;
  final bool required;
  final String? errorText;
  final bool enabled;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final empty = label.startsWith('เลือก') || label.startsWith('ค้นหา');
    return NxOutlinedTapField(
      label: fieldLabel,
      required: required,
      errorText: trn(errorText),
      isEmpty: empty,
      enabled: enabled,
      onTap: onTap,
      // Filled: the avatar is the icon.
      prefixIcon: empty ? Icon(NxI.user, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant) : null,
      suffixIcon: Icon(NxI.caretDown, color: Theme.of(context).colorScheme.onSurfaceVariant),
      child: empty
          ? const SizedBox(height: NxFieldStyle.lineHeight)
          : Row(
              children: [
                NxAvatar(label: label, size: 28),
                const SizedBox(width: 10),
                Expanded(child: Text(tr(label), overflow: TextOverflow.ellipsis)),
                if (onClear != null)
                  IconButton(
                    icon: const Icon(NxI.x, size: 18),
                    onPressed: onClear,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
    );
  }
}

class _ChipTrigger extends StatelessWidget {
  const _ChipTrigger({
    required this.fieldLabel,
    required this.values,
    required this.options,
    required this.hint,
    required this.onTap,
    this.required = false,
    this.errorText,
    this.enabled = true,
    this.avatars = false,
  });
  final String fieldLabel;
  final List<String> values;
  final List<NxPickOption> options;
  final String hint;
  final VoidCallback onTap;
  final bool required;
  final String? errorText;
  final bool enabled;
  final bool avatars;

  @override
  Widget build(BuildContext context) {
    String lab(String v) {
      for (final o in options) {
        if (o.value == v) return o.label;
      }
      return v;
    }

    return NxOutlinedTapField(
      label: fieldLabel,
      required: required,
      errorText: trn(errorText),
      isEmpty: values.isEmpty,
      enabled: enabled,
      onTap: onTap,
      prefixIcon: Icon(NxI.tag, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
      suffixIcon: Icon(NxI.caretDown, color: Theme.of(context).colorScheme.onSurfaceVariant),
      child: values.isEmpty
          ? const SizedBox(height: NxFieldStyle.lineHeight)
          : Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final v in values)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (avatars) ...[
                          NxAvatar(label: lab(v), size: 18),
                          const SizedBox(width: 4),
                        ],
                        Text(tr(lab(v)), style: Theme.of(context).textTheme.labelLarge),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _EmojiRow extends StatelessWidget {
  const _EmojiRow({this.value, required this.options, this.onChanged});
  final String? value;
  final List<NxPickOption> options;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(tr('${o.emoji ?? ''} ${o.label}'.trim())),
            selected: o.value == value,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: onChanged == null ? null : (_) => onChanged!(o.value),
          ),
      ],
    );
  }
}

class _ColorTrigger extends StatelessWidget {
  const _ColorTrigger({
    required this.fieldLabel,
    required this.hex,
    required this.onTap,
    this.required = false,
    this.errorText,
    this.enabled = true,
  });
  final String fieldLabel;
  final String hex;
  final VoidCallback onTap;
  final bool required;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Color? parsed;
    if (hex.length == 7 && hex.startsWith('#')) {
      parsed = Color(int.parse('FF${hex.substring(1)}', radix: 16));
    }
    final empty = hex.isEmpty;
    return NxOutlinedTapField(
      label: fieldLabel,
      required: required,
      errorText: trn(errorText),
      isEmpty: empty,
      enabled: enabled,
      onTap: onTap,
      prefixIcon: Icon(NxI.palette, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
      suffixIcon: Icon(NxI.caretDown, color: Theme.of(context).colorScheme.onSurfaceVariant),
      child: empty
          ? const SizedBox(height: NxFieldStyle.lineHeight)
          : Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: parsed ?? Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4)),
                  ),
                ),
                const SizedBox(width: 10),
                Text(tr(hex)),
              ],
            ),
    );
  }
}

class _MediaBox extends StatelessWidget {
  const _MediaBox({
    required this.kind,
    this.value,
    this.onPick,
    this.enabled = true,
  });
  final NxMediaKind kind;
  final String? value;
  final VoidCallback? onPick;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final media = parseMedia(value);
    final has = media.url.isNotEmpty;
    final icon = kind == NxMediaKind.image
        ? NxI.image
        : kind == NxMediaKind.video
            ? NxI.videoCamera
            : NxI.paperclip;
    final caption = kind == NxMediaKind.image
        ? 'กล้องหรือแกลเลอรี'
        : kind == NxMediaKind.video
            ? 'เลือกคลิป'
            : 'เลือกไฟล์';
    final url = media.url;
    final showThumb = kind == NxMediaKind.image && has && (url.startsWith('http') || url.startsWith('/'));
    return NxDashedDropzone(
      label: has ? url : caption,
      icon: icon,
      onTap: enabled ? onPick : null,
      child: has
          ? Row(
              children: [
                if (showThumb)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      url,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(icon),
                    ),
                  )
                else
                  Icon(icon),
                const SizedBox(width: 10),
                Expanded(child: Text(tr(url), overflow: TextOverflow.ellipsis)),
              ],
            )
          : null,
    );
  }
}

class _LatLongBox extends StatelessWidget {
  const _LatLongBox({
    this.value,
    this.onChanged,
    this.onGps,
    this.enabled = true,
  });
  final dynamic value;
  final ValueChanged<dynamic>? onChanged;
  final Future<({double lat, double lng})?> Function()? onGps;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ll = parseLatLong(value);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _TextBox(
                text: ll.lat,
                hint: 'ละติจูด',
                keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true),
                onChanged: enabled
                    ? (v) => onChanged?.call(formatLatLong(v, ll.lng))
                    : null,
                enabled: enabled,
                bare: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TextBox(
                text: ll.lng,
                hint: 'ลองจิจูด',
                keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true),
                onChanged: enabled
                    ? (v) => onChanged?.call(formatLatLong(ll.lat, v))
                    : null,
                enabled: enabled,
                bare: true,
              ),
            ),
            IconButton(
              tooltip: tr('GPS'),
              onPressed: !enabled || onGps == null
                  ? null
                  : () async {
                      final fix = await onGps!();
                      if (fix != null) {
                        onChanged?.call(formatLatLong('${fix.lat}', '${fix.lng}'));
                      }
                    },
              icon: const Icon(NxI.navigationArrow),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _MiniMap(lat: double.tryParse(ll.lat), lng: double.tryParse(ll.lng)),
      ],
    );
  }
}

class _MiniMap extends StatelessWidget {
  const _MiniMap({this.lat, this.lng});
  final double? lat;
  final double? lng;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 120,
      decoration: NxFieldStyle.box(context),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _MapPainter(
          grid: scheme.outline.withValues(alpha: 0.25),
          pin: scheme.primary,
          hasFix: lat != null && lng != null,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({required this.grid, required this.pin, required this.hasFix});
  final Color grid;
  final Color pin;
  final bool hasFix;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 18) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 0.0; y < size.height; y += 18) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    if (hasFix) {
      final c = Offset(size.width / 2, size.height / 2);
      canvas.drawCircle(c, 6, Paint()..color = pin);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) =>
      oldDelegate.hasFix != hasFix || oldDelegate.pin != pin;
}

class _XyPad extends StatelessWidget {
  const _XyPad({this.value, this.onChanged, this.enabled = true});
  final dynamic value;
  final ValueChanged<dynamic>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final xy = parseXy(value);
    return GestureDetector(
      onTapDown: !enabled
          ? null
          : (d) {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final local = d.localPosition;
              final x = (local.dx / box.size.width).clamp(0.0, 1.0);
              final y = (local.dy / box.size.height).clamp(0.0, 1.0);
              onChanged?.call(formatXy(x, 1 - y));
            },
      child: Container(
        height: 160,
        decoration: NxFieldStyle.box(context),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: _XyPainter(
            x: xy.x,
            y: xy.y,
            grid: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
            pin: Theme.of(context).colorScheme.primary,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _XyPainter extends CustomPainter {
  _XyPainter({this.x, this.y, required this.grid, required this.pin});
  final double? x;
  final double? y;
  final Color grid;
  final Color pin;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0.0; i < size.width; i += 16) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), p);
    }
    for (var i = 0.0; i < size.height; i += 16) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), p);
    }
    if (x != null && y != null) {
      final c = Offset(x! * size.width, (1 - y!) * size.height);
      canvas.drawCircle(c, 7, Paint()..color = pin);
    }
  }

  @override
  bool shouldRepaint(covariant _XyPainter oldDelegate) => oldDelegate.x != x || oldDelegate.y != y;
}

class _PostBox extends StatelessWidget {
  const _PostBox({this.value, this.onChanged, this.enabled = true});
  final dynamic value;
  final ValueChanged<dynamic>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final post = parsePost(value);
    final rating = (post['rating'] as num?)?.toInt() ?? 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                onPressed: enabled
                    ? () => onChanged?.call(formatPost({...post, 'rating': i}))
                    : null,
                icon: Icon(
                  i <= rating ? NxI.starFill : NxI.star,
                  color: const Color(0xFFF59E0B),
                ),
              ),
          ],
        ),
        _TextBox(
          text: post['body']?.toString() ?? '',
          hint: 'ข้อความรีวิว',
          maxLines: 4,
          enabled: enabled,
          bare: true,
          onChanged: enabled ? (v) => onChanged?.call(formatPost({...post, 'body': v})) : null,
        ),
      ],
    );
  }
}

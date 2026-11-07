import 'field_format.dart';
import 'field_ui_type.dart';

bool _isEmpty(dynamic value) {
  if (value == null) return true;
  if (value is String) return value.trim().isEmpty;
  if (value is Iterable) return value.isEmpty;
  if (value is Map) {
    if (value.isEmpty) return true;
    final id = value['id'] ?? value['value'] ?? value['start'] ?? value['url'];
    return value.containsKey('id') || value.containsKey('value') || value.containsKey('start') || value.containsKey('url')
        ? _isEmpty(id)
        : false;
  }
  return value.toString().trim().isEmpty;
}

String? validateFieldValue(
  FieldUiType type,
  dynamic value, {
  required bool required,
}) {
  final empty = _isEmpty(value);
  if (required && empty && type != FieldUiType.yesNo) {
    return 'จำเป็นต้องกรอก';
  }
  if (empty) return null;
  final s = value.toString().trim();
  switch (type) {
    case FieldUiType.email:
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
        return 'อีเมลไม่ถูกต้อง';
      }
      return null;
    case FieldUiType.phone:
      if (digitsOnly(s, 10).length != 10) return 'เบอร์โทร 10 หลัก';
      return null;
    case FieldUiType.taxId:
      if (digitsOnly(s, 13).length != 13) return 'เลขภาษี 13 หลัก';
      return null;
    case FieldUiType.link:
      final lower = s.toLowerCase();
      if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
        return 'ลิงก์ต้องขึ้นต้นด้วย http';
      }
      return null;
    default:
      return null;
  }
}

dynamic fieldDefaultValue(Map<String, dynamic> field) {
  return field['defaultvalue'] ?? field['default_value'] ?? field['default'];
}

int fieldSequence(Map<String, dynamic> field) {
  final raw = field['sequence'] ?? field['seq'] ?? field['sort_order'] ?? field['fieldid'];
  return int.tryParse(raw?.toString() ?? '') ?? 0;
}

String? fieldBlockLabel(Map<String, dynamic> field) {
  final b = field['block_label'] ??
      field['blockname'] ??
      field['block_name'] ??
      field['block'];
  final s = b?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

dynamic unwrapFieldValue(dynamic value) {
  if (value is Map && value['id'] != null && value['label'] != null) {
    return value['id'];
  }
  return value;
}

import '../../core/i18n.dart';
import '../../services/api_exceptions.dart';
import '../../services/comm_ai_export_jobs.dart';

/// Whole numbers stay whole; minutes keep one decimal ("12.5").
String _num(dynamic v) {
  final n = v is num ? v : num.tryParse('${v ?? ''}');
  if (n == null) return '0';
  return n == n.roundToDouble() ? '${n.toInt()}' : n.toStringAsFixed(1);
}

/// "This month's quota is used up" for a quota kind (`stt_minutes` | `summaries` | `translations`) with the numbers.
String commAiQuotaText(String? kind, dynamic used, dynamic limit) {
  final u = _num(used is num ? used.floor() : used);
  final l = _num(limit);
  return switch (kind) {
    'stt_minutes' || 'stt' => tr('ใช้นาทีถอดเสียงครบโควตาของเดือนนี้แล้ว ($u/$l นาที) — ติดต่อผู้ดูแลเพื่อเพิ่มแพ็กเกจ'),
    'translations' => tr('ใช้การแปลคำบรรยายครบโควตาของเดือนนี้แล้ว ($u/$l ครั้ง) — ติดต่อผู้ดูแลเพื่อเพิ่มแพ็กเกจ'),
    _ => tr('ใช้การสรุปของไอแซคครบโควตาของเดือนนี้แล้ว ($u/$l ครั้ง) — ติดต่อผู้ดูแลเพื่อเพิ่มแพ็กเกจ'),
  };
}

/// The month's quota was used up (HTTP 429 `QUOTA_EXCEEDED`)?
bool isCommAiQuotaError(Object e) => e is ApiEnvelopeException && (e.errorCode == 'QUOTA_EXCEEDED' || (e.statusCode == 429 && e.details?['kind'] != null));

/// Readable text for an ISAAC Communication AI error: the quota with its numbers, known codes, else the server text.
String commAiErrorText(Object e) {
  if (e is ApiEnvelopeException) {
    if (isCommAiQuotaError(e)) {
      final d = e.details ?? const <String, dynamic>{};
      return commAiQuotaText(d['kind']?.toString(), d['used'], d['limit']);
    }
    switch (e.errorCode) {
      case 'COMM_AI_NOT_IN_PACKAGE':
        return tr('แพ็กเกจของธุรกิจนี้ยังไม่มีไอแซคเอไอ การสื่อสาร');
      case 'smtp_not_configured':
        return tr('ยังไม่ได้ตั้งค่าการส่งอีเมล (ตั้งค่า → อีเมล)');
      case 'EXPORT_EXPIRED':
        return tr('ไฟล์หมดอายุแล้ว — ส่งออกใหม่อีกครั้ง');
    }
  }
  if (e is CommAiExportJobFailed) {
    if (e.errorCode == 'smtp_not_configured') return tr('ยังไม่ได้ตั้งค่าการส่งอีเมล (ตั้งค่า → อีเมล)');
    return '${tr('งานส่งออกไม่สำเร็จ')}: ${e.message}';
  }
  return formatApiError(e);
}

/// Live captions could not start (`stt:start` ack error) → Thai text; `quota_exceeded` shows the minutes.
String commAiSttErrorText(String error, {Map<String, dynamic>? quota}) => switch (error) {
      'stt_not_configured' => tr('ยังไม่ได้ตั้งค่า OpenAI API key สำหรับถอดเสียง'),
      'stt_disabled' => tr('ผู้ดูแลปิดการถอดเสียงไว้'),
      'mic' => tr('เครื่องนี้แบ่งไมค์ให้ระบบถอดเสียงไม่ได้ — สายยังคุยต่อได้ตามปกติ'),
      'quota_exceeded' => quota != null && quota['limit'] != null
          ? tr('ใช้นาทีถอดเสียงของแพ็กเกจครบแล้วในเดือนนี้ (${_num((quota['used'] as num?)?.floor() ?? quota['used'])}/${_num(quota['limit'])} นาที) — สายยังคุยต่อได้ตามปกติ')
          : tr('ใช้นาทีถอดเสียงของแพ็กเกจครบแล้วในเดือนนี้ — สายยังคุยต่อได้ตามปกติ'),
      'not_in_package' => tr('แพ็กเกจของธุรกิจนี้ยังไม่มีไอแซคเอไอ การสื่อสาร'),
      'stt_busy' => tr('ระบบถอดเสียงไม่ว่างชั่วคราว ลองใหม่อีกครั้ง'),
      _ => tr('เริ่มถอดข้อความไม่สำเร็จ — สายยังคุยต่อได้ตามปกติ'),
    };

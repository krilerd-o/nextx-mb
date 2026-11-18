/// Why NEXTX signed this device out — shown in a dialog (same wording as the web).
///
/// Sources (NEXTX access policy):
/// - response header `X-Session-Revoked: replaced | limit | idle | admin | logout` (older servers send `1`)
///   + `X-Session-Revoked-Info` = URL-encoded JSON `{ reason, at, by_device?, limit?, client?, idle_minutes? }`
/// - socket `auth:session_ended` (same payload) and `auth:force_logout` (`{ reason }`)
/// - 403 with error_code `IP_NOT_ALLOWED` / `OUTSIDE_ALLOWED_HOURS` / `TWO_FA_REQUIRED` / `PASSWORD_EXPIRED`
library;

import 'dart:convert';

/// Business security rules that block every request (sign out and explain).
const kPolicyBlockCodes = {'IP_NOT_ALLOWED', 'OUTSIDE_ALLOWED_HOURS', 'TWO_FA_REQUIRED', 'PASSWORD_EXPIRED'};

class SessionEnded {
  const SessionEnded({required this.reason, this.at, this.byDevice, this.limit, this.client, this.idleMinutes, this.message});

  /// replaced | limit | idle | admin | logout | expired | policy:<CODE>
  final String reason;
  final DateTime? at;
  final String? byDevice;
  final int? limit;
  final String? client;
  final int? idleMinutes;

  /// Server message (policy blocks).
  final String? message;

  bool get isPolicyBlock => reason.startsWith('policy:');

  static int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

  static SessionEnded fromMap(Map<String, dynamic> m, {String fallbackReason = 'admin'}) {
    final r = (m['reason']?.toString() ?? '').trim();
    final reason = switch (r) {
      'replaced' || 'limit' || 'idle' || 'admin' || 'logout' => r,
      'suspended' || 'account_deactivated' => 'admin',
      _ => fallbackReason,
    };
    return SessionEnded(
      reason: reason,
      at: DateTime.tryParse(m['at']?.toString() ?? '')?.toLocal(),
      byDevice: (m['by_device']?.toString() ?? '').trim().isEmpty ? null : m['by_device'].toString(),
      limit: _int(m['limit']),
      client: m['client']?.toString(),
      idleMinutes: _int(m['idle_minutes']),
    );
  }

  /// From the revoked headers; `null` when the response is not a sign-out.
  static SessionEnded? fromHeaders(String? revoked, String? info) {
    final r = (revoked ?? '').trim();
    if (r.isEmpty) return null;
    Map<String, dynamic> m = {};
    if (info != null && info.isNotEmpty) {
      try {
        final d = jsonDecode(Uri.decodeComponent(info));
        if (d is Map) m = Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    if (r != '1') m['reason'] ??= r;
    return fromMap(m);
  }

  static SessionEnded policyBlock(String code, String? message) =>
      SessionEnded(reason: 'policy:$code', message: message, at: DateTime.now());
}

String _two(int v) => v.toString().padLeft(2, '0');

String _when(DateTime? at) {
  if (at == null) return '';
  return '${_two(at.day)}/${_two(at.month)}/${at.year + 543} ${_two(at.hour)}:${_two(at.minute)} น.';
}

/// "6 ชั่วโมง" / "30 นาที" / "90 วัน"
String idleDurationTh(int? minutes) {
  final m = minutes ?? 0;
  if (m >= 1440 && m % 1440 == 0) return '${m ~/ 1440} วัน';
  if (m >= 60 && m % 60 == 0) return '${m ~/ 60} ชั่วโมง';
  return '$m นาที';
}

/// Title + body for the dialog (Thai, same as the web SessionEndedModal).
({String title, String body}) sessionEndedText(SessionEnded e) {
  final when = _when(e.at);
  if (e.isPolicyBlock) {
    final code = e.reason.substring(7);
    final title = switch (code) {
      'IP_NOT_ALLOWED' => 'เข้าใช้งานจากเครือข่ายนี้ไม่ได้',
      'OUTSIDE_ALLOWED_HOURS' => 'อยู่นอกเวลาใช้งาน',
      'TWO_FA_REQUIRED' => 'ต้องเปิดยืนยันตัวตน 2 ขั้นตอน',
      'PASSWORD_EXPIRED' => 'รหัสผ่านหมดอายุ',
      _ => 'ใช้งานไม่ได้ตามนโยบายของธุรกิจ',
    };
    final fix = switch (code) {
      'TWO_FA_REQUIRED' => ' — เปิดใช้งานที่เว็บ (โปรไฟล์ › ความปลอดภัย) แล้วเข้าสู่ระบบในแอปอีกครั้ง',
      'PASSWORD_EXPIRED' => ' — ตั้งรหัสผ่านใหม่ที่เว็บ แล้วเข้าสู่ระบบในแอปอีกครั้ง',
      _ => ' — หากคิดว่าไม่ถูกต้อง กรุณาติดต่อผู้ดูแลของธุรกิจ',
    };
    return (title: title, body: '${e.message ?? 'ธุรกิจนี้จำกัดการใช้งาน'}$fix');
  }
  switch (e.reason) {
    case 'replaced':
      return (
        title: 'มีการเข้าสู่ระบบจากอุปกรณ์อื่น',
        body: e.byDevice != null
            ? 'บัญชีของคุณเข้าสู่ระบบบน ${e.byDevice}${when.isEmpty ? '' : ' เมื่อ $when'} — ธุรกิจนี้ใช้ได้ทีละ 1 เครื่อง เครื่องนี้จึงออกจากระบบแล้ว หากไม่ใช่คุณ กรุณาเปลี่ยนรหัสผ่านทันที'
            : 'ธุรกิจนี้ใช้ได้ทีละ 1 เครื่อง — ระบบคงไว้เฉพาะเครื่องที่ใช้งานล่าสุด',
      );
    case 'limit':
      final kind = e.client == 'mobile' ? 'แอปมือถือ' : 'เว็บ';
      return (
        title: 'มีผู้ใช้งานพร้อมกันครบจำนวนแล้ว',
        body: 'ธุรกิจนี้กำหนดจำนวนผู้ใช้$kindพร้อมกัน${e.limit != null ? ' ${e.limit} คน' : ''} ระบบให้สิทธิ์ผู้ที่เข้าใช้ล่าสุด คุณจึงออกจากระบบ${when.isEmpty ? '' : 'เมื่อ $when'} — เข้าสู่ระบบใหม่ได้เมื่อมีที่ว่าง',
      );
    case 'idle':
      return (
        title: 'ออกจากระบบอัตโนมัติ',
        body: 'ไม่มีการใช้งานเกิน ${idleDurationTh(e.idleMinutes)} ระบบจึงออกจากระบบเพื่อความปลอดภัย — เข้าสู่ระบบใหม่เพื่อใช้งานต่อ',
      );
    case 'logout':
      return (title: 'ออกจากระบบแล้ว', body: 'อุปกรณ์นี้ออกจากระบบแล้ว');
    case 'expired':
      return (title: 'เซสชันหมดอายุ', body: 'กรุณาเข้าสู่ระบบใหม่');
    default:
      return (
        title: 'ออกจากระบบแล้ว',
        body: 'อุปกรณ์นี้ถูกให้ออกจากระบบ${when.isEmpty ? '' : ' เมื่อ $when'} โดยผู้ดูแลหรือจากหน้าอุปกรณ์ที่เข้าใช้งาน',
      );
  }
}

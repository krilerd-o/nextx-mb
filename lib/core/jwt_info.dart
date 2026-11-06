import 'dart:convert';

/// `iat` / `exp` read from a JWT payload (no signature check — the server does that).
class JwtTimes {
  const JwtTimes({this.issuedAt, this.expiresAt});
  final DateTime? issuedAt;
  final DateTime? expiresAt;
}

JwtTimes? decodeJwtTimes(String? token) {
  if (token == null) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    if (json is! Map) return null;
    DateTime? at(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch((v * 1000).round(), isUtc: true) : null;
    return JwtTimes(issuedAt: at(json['iat']), expiresAt: at(json['exp']));
  } catch (_) {
    return null;
  }
}

/// Renew once the token is a day old (or close to expiry), while it is still valid.
bool shouldRenewToken(String? token, DateTime now, {Duration minAge = const Duration(days: 1)}) {
  final t = decodeJwtTimes(token);
  if (t == null) return false;
  final exp = t.expiresAt;
  if (exp != null && !exp.isAfter(now)) return false; // already expired → only a new login helps
  if (exp != null && exp.difference(now) < const Duration(days: 3)) return true;
  final iat = t.issuedAt;
  return iat != null && now.difference(iat) >= minAge;
}

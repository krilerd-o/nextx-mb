import 'dart:convert';

/// Ordered approver user ids for a quotation, mirroring NEXTX
/// `parseApprovalChain` (backend/src/routes/quotation.js): `approval_chain`
/// first, else `approver_1_user_id` / `approver_2_user_id`.
List<String> quotationApprovalChain(Map<String, dynamic> row) {
  var raw = row['approval_chain'];
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      raw = jsonDecode(raw);
    } catch (_) {
      raw = null;
    }
  }
  if (raw is List && raw.isNotEmpty) {
    return raw
        .map((e) => int.tryParse(e.toString()))
        .whereType<int>()
        .map((e) => '$e')
        .toList();
  }
  return [
    for (final key in const ['approver_1_user_id', 'approver_2_user_id'])
      if (int.tryParse(row[key]?.toString() ?? '') != null) '${int.parse(row[key].toString())}',
  ];
}

/// True when [row] is pending and [userId] is the approver for its current level.
bool isAwaitingMyApproval(Map<String, dynamic> row, String? userId) {
  if (userId == null || userId.isEmpty) return false;
  if ((row['approval_state']?.toString() ?? '').toLowerCase() != 'pending') return false;
  final chain = quotationApprovalChain(row);
  if (chain.isEmpty) return false;
  final level = int.tryParse(row['approval_level']?.toString() ?? '') ?? 1;
  final idx = (level < 1 ? 1 : level) - 1;
  if (idx >= chain.length) return false;
  return chain[idx] == userId;
}

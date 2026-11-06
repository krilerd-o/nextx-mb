/// Pure helpers to apply realtime chat events to a loaded message list.
library;

int _order(Map<String, dynamic> m) => int.tryParse(m['id']?.toString() ?? '') ?? 0;

/// Inserts or replaces [msg] (by id), keeping ascending id order.
/// Existing sender fields are kept when the event omits them.
List<Map<String, dynamic>> upsertChatMessage(List<Map<String, dynamic>> list, Map<String, dynamic> msg) {
  final id = msg['id']?.toString();
  if (id == null || id.isEmpty) return list;
  final out = [...list];
  final i = out.indexWhere((m) => m['id']?.toString() == id);
  if (i >= 0) {
    out[i] = {...out[i], ...msg};
  } else {
    out.add(msg);
    out.sort((a, b) => _order(a).compareTo(_order(b)));
  }
  return out;
}

List<Map<String, dynamic>> removeChatMessage(List<Map<String, dynamic>> list, String? id) {
  if (id == null) return list;
  return list.where((m) => m['id']?.toString() != id).toList();
}

/// Adds sender names to a realtime message by reusing what earlier messages from the same user carry.
Map<String, dynamic> fillChatSender(Map<String, dynamic> msg, List<Map<String, dynamic>> known) {
  if ((msg['first_name'] ?? msg['last_name']) != null) return msg;
  final uid = msg['user_id']?.toString();
  for (final m in known.reversed) {
    if (m['user_id']?.toString() == uid && (m['first_name'] ?? m['last_name']) != null) {
      return {...msg, 'first_name': m['first_name'], 'last_name': m['last_name']};
    }
  }
  return msg;
}

/// Applies a `read_receipt` socket event: user [userId] has read up to [messageId].
Map<String, List<String>> applyReadReceipt(
  Map<String, List<String>> readers,
  List<Map<String, dynamic>> messages,
  String userId,
  String messageId,
) {
  final upTo = int.tryParse(messageId) ?? 0;
  final out = {for (final e in readers.entries) e.key: [...e.value]};
  for (final m in messages) {
    final id = m['id']?.toString();
    if (id == null || (int.tryParse(id) ?? 0) > upTo) continue;
    final list = out[id] ??= [];
    if (!list.contains(userId)) list.add(userId);
  }
  return out;
}

/// How many other people have read my latest message (shown under it).
int readCountForLastOwn(List<Map<String, dynamic>> messages, Map<String, List<String>> readers, String? me) {
  for (final m in messages.reversed) {
    if (isOwnChatMessage(m, me)) {
      final ids = readers[m['id']?.toString()] ?? const [];
      return ids.where((u) => u != me).length;
    }
  }
  return 0;
}

/// Reactions in either the `reaction_summary` (Mongo chat) or `reactions` shape.
List<Map<String, dynamic>> chatReactions(Map<String, dynamic> m) {
  final raw = m['reaction_summary'] ?? m['reactions'];
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

bool isOwnChatMessage(Map<String, dynamic> m, String? myUserId) =>
    myUserId != null && myUserId.isNotEmpty && m['user_id']?.toString() == myUserId;

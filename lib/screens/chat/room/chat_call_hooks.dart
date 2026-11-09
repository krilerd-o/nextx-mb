import 'package:flutter/widgets.dart';

/// Chat ↔ calls bridge. The call service registers [start] at app start; when it is null
/// (no WebRTC on this platform / tests) the chat hides its call buttons.
class ChatCallHooks {
  ChatCallHooks._();

  /// Start a voice ([video] false) or video call in [room]. [userIds] limits who rings (group > 4).
  static Future<void> Function(BuildContext context, Map<String, dynamic> room, {required bool video, List<String>? userIds})? start;

  static bool get available => start != null;
}

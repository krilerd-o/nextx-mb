import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/chat_format.dart';
import '../../core/i18n.dart';
import '../../screens/chat/room/chat_call_hooks.dart';
import '../../screens/chat/room/chat_message_bubble.dart' show chatSenderName;
import '../../widgets/nx_avatar.dart';
import 'call_media_webrtc.dart';
import 'call_service.dart';
import 'call_system_ui.dart';
import 'live_transcription.dart';

/// Calls need WebRTC (Android / iOS); `flutter test` runs without the plugins.
bool get callsSupported {
  if (kIsWeb) return false;
  if (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS) return false;
  try {
    return !Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return true;
  }
}

/// Created once at app start (main.dart).
void initCalls() {
  if (!callsSupported || CallService.instance != null) return;
  CallService.instance = CallService(media: WebRtcCallMedia.new, systemUi: CallKitSystemUi());
}

/// After sign-in / switching Space: who I am, the chat call buttons, CallKit events, iOS VoIP token.
void bindCalls(AppConfig config) {
  final service = CallService.instance;
  if (service == null) return;
  service.myUserId = config.session.userId;
  ChatCallHooks.start = (context, room, {required video, userIds}) async {
    final code = await service.start(roomId: '${room['id']}', roomTitle: chatRoomTitle(room), video: video, userIds: userIds);
    if (code == 'too_many' && context.mounted) {
      final picked = await _pickPeople(context, config, '${room['id']}');
      if (picked.isNotEmpty && context.mounted) {
        await ChatCallHooks.start!(context, room, video: video, userIds: picked);
      }
    }
  };
  CallKitBridge.start(service: service, api: () => config.apiClient);
  CallKitBridge.registerVoipToken(config.apiClient);
  // AI การสื่อสาร: live captions follow this call service; settings are re-read for the new Space.
  final lt = LiveTranscription.instance
    ..api = config.apiClient
    ..myUserId = config.session.userId
    ..businessId = config.session.businessId
    ..settings = null;
  lt.attach(service);
  lt.ensureSettings();
}

/// Group rooms with more than 4 people: choose up to 3 to call.
Future<List<String>> _pickPeople(BuildContext context, AppConfig config, String roomId) async {
  List<Map<String, dynamic>> members;
  try {
    members = await config.apiClient.getChatRoomMembers(roomId);
  } catch (_) {
    return const [];
  }
  final me = config.session.userId;
  members = members.where((m) => '${m['user_id']}' != me).toList();
  if (!context.mounted) return const [];
  final out = await showModalBottomSheet<List<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (ctx) {
      final picked = <String>{};
      return StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.7,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(tr('เลือกคนที่จะโทรหา (สูงสุด 3 คน)'), style: Theme.of(ctx).textTheme.titleMedium),
              ),
              Expanded(
                child: ListView(children: [
                  for (final m in members)
                    CheckboxListTile(
                      value: picked.contains('${m['user_id']}'),
                      secondary: NxAvatar(label: chatSenderName(m), size: 34),
                      title: Text(chatSenderName(m)),
                      onChanged: (v) => set(() {
                        final id = '${m['user_id']}';
                        if (v == true && picked.length < 3) picked.add(id);
                        if (v != true) picked.remove(id);
                      }),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: picked.isEmpty ? null : () => Navigator.pop(ctx, picked.toList()), child: Text(tr('โทร (${picked.length} คน)'))),
                ),
              ),
            ]),
          ),
        ),
      );
    },
  );
  return out ?? const [];
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../api_client.dart';
import 'call_service.dart';

bool get callKitSupported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Push payload / `rtc:ring` call → CallKit (iOS) / full-screen incoming call (Android).
CallKitParams callKitParamsFrom(Map<String, dynamic> d) {
  final id = (d['call_id'] ?? '').toString();
  final video = (d['media'] ?? '').toString() == 'video';
  final group = d['group'] == true || d['group'] == '1';
  final from = (d['from_name'] ?? d['caller_name'] ?? 'สายเรียกเข้า').toString();
  final room = (d['room_name'] ?? '').toString();
  return CallKitParams(
    id: id,
    nameCaller: group && room.isNotEmpty ? room : from,
    appName: 'MOAI NEXT',
    handle: group ? from : (video ? 'วิดีโอคอล' : 'โทรด้วยเสียง'),
    type: video ? 1 : 0,
    duration: 45000,
    missedCallNotification: const NotificationParams(showNotification: true, isShowCallback: false, subtitle: 'สายที่ไม่ได้รับ'),
    extra: {
      'call_id': id,
      'chat_room_id': '${d['chat_room_id'] ?? ''}',
      'media': video ? 'video' : 'audio',
      'from_name': from,
      'room_name': room,
      'group': group ? '1' : '0',
    },
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      backgroundColor: '#0F172A',
      actionColor: '#22C55E',
      textColor: '#FFFFFF',
      incomingCallNotificationChannelName: 'สายเรียกเข้า',
      missedCallNotificationChannelName: 'สายที่ไม่ได้รับ',
      isShowFullLockedScreen: true,
      isImportant: true,
      textAccept: 'รับสาย',
      textDecline: 'ปฏิเสธ',
    ),
    ios: const IOSParams(handleType: 'generic', supportsVideo: true, maximumCallGroups: 1, maximumCallsPerCallGroup: 1, configureAudioSession: true, supportsHolding: false, supportsDTMF: false),
  );
}

/// FCM data message while the app is in the background / closed (Android; iOS uses PushKit natively).
Future<void> handleCallPush(Map<String, dynamic> data) async {
  if (!callKitSupported) return;
  final type = data['type']?.toString();
  final id = data['call_id']?.toString() ?? '';
  if (id.isEmpty) return;
  try {
    if (type == 'call_incoming') {
      await FlutterCallkitIncoming.showCallkitIncoming(callKitParamsFrom(data));
    } else if (type == 'call_cancel') {
      await FlutterCallkitIncoming.endCall(id);
    }
  } catch (e) {
    debugPrint('[call] push: $e');
  }
}

bool isCallPush(Map<String, dynamic> data) {
  final t = data['type']?.toString();
  return t == 'call_incoming' || t == 'call_cancel';
}

/// Phone call screens through flutter_callkit_incoming. While the app is open the in-app
/// call screens are used instead (no double ringing).
class CallKitSystemUi implements CallSystemUi {
  bool get _foreground => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  Future<void> showIncoming(Map<String, dynamic> call) async {
    if (!callKitSupported || _foreground) return;
    await FlutterCallkitIncoming.showCallkitIncoming(callKitParamsFrom(call)).catchError((_) {});
  }

  @override
  Future<void> startOutgoing(Map<String, dynamic> call) async {
    // iOS: an outgoing CallKit call keeps the audio session alive in the background.
    if (defaultTargetPlatform != TargetPlatform.iOS || kIsWeb) return;
    await FlutterCallkitIncoming.startCall(callKitParamsFrom(call)).catchError((_) {});
  }

  @override
  Future<void> connected(String callId) async {
    if (!callKitSupported) return;
    await FlutterCallkitIncoming.setCallConnected(callId).catchError((_) {});
  }

  @override
  Future<void> end(String callId) async {
    if (!callKitSupported) return;
    await FlutterCallkitIncoming.endCall(callId).catchError((_) {});
  }
}

/// Accept / decline / hang up from the phone's call screen, and the iOS VoIP token.
class CallKitBridge {
  CallKitBridge._();
  static StreamSubscription<CallEvent?>? _sub;

  static void start({required CallService service, required ApiClient Function() api}) {
    if (!callKitSupported) return;
    _sub?.cancel();
    _sub = FlutterCallkitIncoming.onEvent.listen((event) async {
      switch (event) {
        case CallEventActionCallAccept(:final callKitParams):
          final extra = Map<String, dynamic>.from(callKitParams.extra ?? const {});
          final id = extra['call_id']?.toString() ?? callKitParams.id;
          await service.acceptById(id, hint: {
            'call_id': id,
            'media': extra['media'],
            'room_name': extra['room_name'],
            'caller_name': extra['from_name'],
            'chat_room_id': extra['chat_room_id'],
            'group': extra['group'] == '1',
          });
        case CallEventActionCallDecline(:final callKitParams):
          final id = callKitParams.extra?['call_id']?.toString() ?? callKitParams.id;
          if (service.incoming?['call_id'] == id) {
            await service.decline();
          } else {
            await api().declineCall(id).catchError((_) {});
          }
        case CallEventActionCallEnded(:final callKitParams):
          final id = callKitParams.extra?['call_id']?.toString() ?? callKitParams.id;
          if (service.callId == id && service.phase != CallPhase.idle && service.phase != CallPhase.incoming) await service.hangUp();
        case CallEventActionCallToggleMute():
          await service.toggleMute();
        case CallEventActionDidUpdateDevicePushTokenVoip():
          await registerVoipToken(api());
        default:
          break;
      }
    }, onError: (Object e) => debugPrint('[call] callkit events: $e'));
  }

  /// iOS: send the PushKit token (platform `ios_voip`) so the server can ring this phone.
  static Future<void> registerVoipToken(ApiClient api) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      if (token != null && token.isNotEmpty) {
        await api.registerDeviceToken(token: token, platform: 'ios_voip', deviceName: 'iOS VoIP');
      }
    } catch (e) {
      debugPrint('[call] voip token: $e');
    }
  }
}

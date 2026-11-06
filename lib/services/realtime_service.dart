import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// One Socket.IO event from the NEXTX backend (`backend/src/socket/index.js`).
class RealtimeEvent {
  const RealtimeEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;

  /// `room_id` for chat events, when the server includes it.
  String? get roomId => data['room_id']?.toString();
}

class RealtimeService extends ChangeNotifier {
  RealtimeService._();
  static final RealtimeService instance = RealtimeService._();

  /// Server → client events forwarded to [events].
  static const forwardedEvents = [
    'notification',
    'new_message',
    'message_edited',
    'message_deleted',
    'message_reaction',
    'read_receipt',
    'user_typing',
    'user_stopped_typing',
    'calendar:activity_upsert',
    'mail:new',
    'mail:updated',
  ];

  io.Socket? _socket;
  final _events = StreamController<RealtimeEvent>.broadcast();
  String? _currentRoomId;

  /// Every event, in order — unlike [lastNotification] nothing is dropped in a burst.
  Stream<RealtimeEvent> get events => _events.stream;

  Stream<RealtimeEvent> on(String type) => events.where((e) => e.type == type);

  Map<String, dynamic>? lastNotification;
  Map<String, dynamic>? lastChatMessage;
  bool connected = false;

  void connect({
    required String baseUrl,
    required String token,
    String? businessId,
  }) {
    disconnect();
    final origin = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final socket = io.io(
      origin,
      io.OptionBuilder()
          .setPath('/api/socket.io')
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': token})
          .enableReconnection()
          .disableAutoConnect()
          .build(),
    );
    socket.onConnect((_) {
      connected = true;
      final bid = int.tryParse(businessId ?? '');
      if (bid != null) {
        socket.emit('calendar:join', {'business_id': bid});
      }
      // The server forgets room membership on reconnect.
      final room = _currentRoomId;
      if (room != null) socket.emit('join_room', room);
      notifyListeners();
    });
    socket.onDisconnect((_) {
      connected = false;
      notifyListeners();
    });
    for (final type in forwardedEvents) {
      socket.on(type, (data) => _dispatch(type, data));
    }
    _socket = socket;
    socket.connect();
  }

  @visibleForTesting
  void dispatchForTest(String type, dynamic data) => _dispatch(type, data);

  void _dispatch(String type, dynamic data) {
    if (data is! Map) return;
    final map = Map<String, dynamic>.from(data);
    if (type == 'notification') lastNotification = map;
    if (type == 'new_message') lastChatMessage = map;
    if (!_events.isClosed) _events.add(RealtimeEvent(type, map));
    if (type == 'notification' || type == 'new_message') notifyListeners();
  }

  void joinChatRoom(String roomId) {
    _currentRoomId = roomId;
    _socket?.emit('join_room', roomId);
  }

  void leaveChatRoom(String roomId) {
    if (_currentRoomId == roomId) _currentRoomId = null;
    _socket?.emit('leave_room', roomId);
  }

  void typing(String roomId, {required bool active}) {
    _socket?.emit(active ? 'typing_start' : 'typing_stop', {'room_id': int.tryParse(roomId) ?? roomId});
  }

  void markRead(String roomId, String messageId) {
    _socket?.emit('mark_read', {
      'room_id': int.tryParse(roomId) ?? roomId,
      'message_id': int.tryParse(messageId) ?? messageId,
    });
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    connected = false;
  }
}

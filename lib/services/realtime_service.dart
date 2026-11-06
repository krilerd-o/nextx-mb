import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class RealtimeService extends ChangeNotifier {
  RealtimeService._();
  static final RealtimeService instance = RealtimeService._();

  io.Socket? _socket;
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
          .build(),
    );
    socket.onConnect((_) {
      connected = true;
      final bid = int.tryParse(businessId ?? '');
      if (bid != null) {
        socket.emit('calendar:join', {'business_id': bid});
      }
      notifyListeners();
    });
    socket.onDisconnect((_) {
      connected = false;
      notifyListeners();
    });
    socket.on('notification', (data) {
      if (data is Map) {
        lastNotification = Map<String, dynamic>.from(data);
        notifyListeners();
      }
    });
    socket.on('new_message', (data) {
      if (data is Map) {
        lastChatMessage = Map<String, dynamic>.from(data);
        notifyListeners();
      }
    });
    _socket = socket;
  }

  void joinChatRoom(String roomId) {
    _socket?.emit('join_room', roomId);
  }

  void leaveChatRoom(String roomId) {
    _socket?.emit('leave_room', roomId);
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    connected = false;
  }
}

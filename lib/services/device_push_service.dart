import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';
import 'api_client.dart';
import '../core/navigation/notification_deep_link.dart';
import '../core/push_navigation.dart';

const _tokenKey = 'staff_device_push_token';
const _androidChannelId = 'high_importance_channel';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}
  final loc = notificationDeepLinkFromData(Map<String, dynamic>.from(message.data));
  PushNavigation.instance.remember(loc);
}

Future<void> _ensureLocalNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings();
  await _localNotifications.initialize(
    const InitializationSettings(android: android, iOS: ios),
    onDidReceiveNotificationResponse: (response) {
      final payload = response.payload;
      if (payload != null && payload.isNotEmpty) {
        PushNavigation.instance.remember(payload);
      }
    },
  );
  final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      _androidChannelId,
      'MOAI NEXT',
      description: 'แจ้งเตือนงานและแชท',
      importance: Importance.high,
    ),
  );
}

Future<void> _showForegroundNotification(RemoteMessage message) async {
  final n = message.notification;
  final title = n?.title ?? message.data['title']?.toString() ?? 'MOAI NEXT';
  final body = n?.body ?? message.data['body']?.toString() ?? '';
  final loc = notificationDeepLinkFromData(Map<String, dynamic>.from(message.data));
  await _localNotifications.show(
    message.hashCode,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannelId,
        'MOAI NEXT',
        channelDescription: 'แจ้งเตือนงานและแชท',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    ),
    payload: loc,
  );
}

Future<void> initFirebasePush() async {
  if (kIsWeb) return;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    await _ensureLocalNotifications();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      PushNavigation.instance.remember(
        notificationDeepLinkFromData(Map<String, dynamic>.from(initial.data)),
      );
    }
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      PushNavigation.instance.remember(
        notificationDeepLinkFromData(Map<String, dynamic>.from(message.data)),
      );
    });
    FirebaseMessaging.onMessage.listen((message) {
      _showForegroundNotification(message);
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((value) {
      DevicePushService.instance.onTokenRefreshed(value);
    });
  } catch (e) {
    debugPrint('[push] Firebase init skipped: $e');
  }
}

/// Registers this device with `/api/notifications/device-token` after FCM is ready.
class DevicePushService {
  DevicePushService._();
  static final DevicePushService instance = DevicePushService._();

  String? lastToken;
  bool get isReady => lastToken != null && lastToken!.isNotEmpty;

  /// Session the token was last registered for; used to re-register on rotation.
  AppConfig? _boundConfig;

  Future<void> sync(AppConfig config) async {
    _boundConfig = config;
    try {
      await _refreshFcmToken();
    } catch (e) {
      debugPrint('[push] token: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    final token = lastToken ?? prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) return;
    lastToken = token;
    try {
      await config.apiClient.registerDeviceToken(
        token: token,
        platform: config.devicePlatform,
        deviceName: defaultTargetPlatform.name,
      );
    } catch (e) {
      debugPrint('[push] register: $e');
    }
  }

  /// FCM rotated the token: persist it and tell the server, otherwise pushes stop arriving.
  Future<void> onTokenRefreshed(String token) async {
    await saveToken(token);
    final config = _boundConfig;
    if (config == null || !config.isLoggedIn) return;
    try {
      await config.apiClient.registerDeviceToken(
        token: token,
        platform: config.devicePlatform,
        deviceName: defaultTargetPlatform.name,
      );
    } catch (e) {
      debugPrint('[push] re-register: $e');
    }
  }

  /// Removes this device's push registration from one server only (signing
  /// out of a Space) — the FCM token stays valid for the other Spaces.
  Future<void> unregisterFrom(ApiClient api) async {
    final prefs = await SharedPreferences.getInstance();
    final token = lastToken ?? prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) return;
    await api.unregisterDeviceToken(token);
  }

  Future<void> unregister(AppConfig config) async {
    _boundConfig = null;
    final prefs = await SharedPreferences.getInstance();
    final token = lastToken ?? prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) return;
    try {
      await config.apiClient.unregisterDeviceToken(token);
    } catch (_) {}
    await prefs.remove(_tokenKey);
    lastToken = null;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  Future<void> saveToken(String token) async {
    lastToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> _refreshFcmToken() async {
    if (kIsWeb || Firebase.apps.isEmpty) return;
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Permission.notification.request();
    }
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await saveToken(token);
      debugPrint('[push] FCM token $token');
    }
  }
}

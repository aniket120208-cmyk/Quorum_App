import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/notification_router.dart';
import 'package:quorum_app/api/socket_service.dart';

const String quorumChatChannelId = 'quorum_chat_messages';

Future<void> _showLocal(
  FlutterLocalNotificationsPlugin plugin,
  RemoteMessage message,
) async {
  final data = message.data;
  final title = (message.notification?.title ?? data['title'] ?? data['senderName'] ?? 'Quorum').toString();
  final body = (message.notification?.body ?? data['body'] ?? data['content'] ?? data['message'] ?? '').toString();
  if (body.isEmpty) return;
  await plugin.show(
    DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        quorumChatChannelId,
        'Quorum Chat Messages',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
    payload: jsonEncode(data),
  );
}

@pragma('vm:entry-point')
Future<void> quorumFirebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  if (message.notification != null || !Platform.isAndroid) return;
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/launcher_icon'),
      ),
    );
    await _showLocal(plugin, message);
  } catch (_) {}
}

@pragma('vm:entry-point')
void quorumNotificationBackgroundResponse(NotificationResponse response) {
  PushService.handleResponse(response);
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _available = false;
  bool _started = false;
  bool _ready = false;
  String? _token;
  Map<String, dynamic>? _pendingOpen;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<RemoteMessage>? _messageSub;

  Future<void> init() async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(quorumFirebaseBackgroundHandler);
      _available = true;
    } catch (e) {
      debugPrint('Push init failed: $e');
      return;
    }
    try {
      await _local.initialize(
        InitializationSettings(
          android: const AndroidInitializationSettings('@mipmap/launcher_icon'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
            notificationCategories: [
              DarwinNotificationCategory(
                'MESSAGE_REPLY',
                actions: [
                  DarwinNotificationAction.text(
                    'reply',
                    'Reply',
                    buttonTitle: 'Send',
                    placeholder: 'Type your reply...',
                  ),
                  DarwinNotificationAction.plain('mark_as_read', 'Mark as Read'),
                ],
                options: {DarwinNotificationCategoryOption.customDismissAction},
              ),
            ],
          ),
        ),
        onDidReceiveNotificationResponse: handleResponse,
        onDidReceiveBackgroundNotificationResponse: quorumNotificationBackgroundResponse,
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              quorumChatChannelId,
              'Quorum Chat Messages',
              description: 'Direct messages, mentions, and community alerts',
              importance: Importance.high,
              playSound: true,
              enableVibration: true,
              enableLights: true,
            ),
          );
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );
      _messageSub = FirebaseMessaging.onMessage.listen((message) {
        debugPrint('Push received in foreground: ${message.notification?.title ?? message.data}');
      });
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_enqueueOpen);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _enqueueOpen(initial);
      } else {
        final launch = await _local.getNotificationAppLaunchDetails();
        final response = launch?.notificationResponse;
        if (launch?.didNotificationLaunchApp == true && response != null) {
          final data = _decodePayload(response.payload);
          if (data.isNotEmpty) _enqueueData(data);
        }
      }
    } catch (e) {
      debugPrint('Push setup failed: $e');
    }
    debugPrint('Push init finished: available=$_available');
  }

  Future<void> start() async {
    debugPrint('Push start: available=$_available started=$_started');
    if (!_available || _started) return;
    _started = true;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Push permission denied');
        return;
      }
      _refreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(_register);
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('FCM token: $token');
      if (token != null) await _register(token);
    } catch (e) {
      debugPrint('Push start failed: $e');
    }
  }

  Future<void> _register(String token) async {
    _token = token;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await ApiClient.instance.dio.post('/api/devices', data: {
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        });
        debugPrint('Push token registered');
        return;
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        debugPrint('Push token registration failed: $code ${e.response?.data}');
        if (code == 400 || code == 404 || code == 422) return;
      } catch (e) {
        debugPrint('Push token registration failed: $e');
      }
      await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
    }
  }

  Future<void> unregister() async {
    _ready = false;
    _pendingOpen = null;
    if (!_available) return;
    String? token = _token;
    try {
      token ??= await FirebaseMessaging.instance.getToken();
    } catch (_) {}
    if (token != null) {
      try {
        await ApiClient.instance.dio.delete('/api/devices', data: {'token': token});
      } catch (_) {}
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    await _refreshSub?.cancel();
    _refreshSub = null;
    _token = null;
    _started = false;
  }

  void markReady() {
    _ready = true;
    _flushOpen();
  }

  void _enqueueOpen(RemoteMessage message) => _enqueueData(Map<String, dynamic>.from(message.data));

  void _enqueueData(Map<String, dynamic> data) {
    _pendingOpen = data;
    if (_ready) _flushOpen();
  }

  static Map<String, dynamic> _decodePayload(String? raw) {
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<void> _flushOpen() async {
    final data = _pendingOpen;
    if (data == null) return;
    _pendingOpen = null;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    try {
      await NotificationRouter.openPayload(data);
    } catch (e) {
      debugPrint('Push open failed: $e');
    }
  }

  static Future<void> handleResponse(NotificationResponse response) async {
    final actionId = response.actionId;
    final data = _decodePayload(response.payload);
    if (actionId == null || actionId.isEmpty) {
      if (data.isNotEmpty) instance._enqueueData(data);
      return;
    }
    final conversationId = (data['conversationId'] ?? '').toString();
    final messageId = (data['messageId'] ?? '').toString();
    if (conversationId.isEmpty) return;
    try {
      await SocketService.instance.ensureConnected();
      if (actionId == 'reply') {
        final text = (response.input ?? '').trim();
        if (text.isEmpty) return;
        SocketService.instance.emitAck('message:send', {
          'conversationId': conversationId,
          'clientMessageId': 'tmp_${DateTime.now().microsecondsSinceEpoch}',
          'content': text,
        }, (_) {});
      } else if (actionId == 'mark_as_read' && messageId.isNotEmpty) {
        SocketService.instance.emit('message:read', {
          'conversationId': conversationId,
          'messageId': messageId,
        });
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _refreshSub?.cancel();
    await _openedSub?.cancel();
    await _messageSub?.cancel();
  }
}
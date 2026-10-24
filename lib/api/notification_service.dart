import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:quorum_app/api/notification_repository.dart';
import 'package:quorum_app/api/socket_service.dart';
import 'package:quorum_app/models/notification_models.dart';
import 'package:quorum_app/screens/notification_screen/notification_banner.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();
  static const String _event = 'notification:new';
  static const String _mentionEvent = 'chat_mention';

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);
  final StreamController<NotificationItem> _incoming = StreamController<NotificationItem>.broadcast();

  Stream<NotificationItem> get incoming => _incoming.stream;

  bool _started = false;
  Timer? _poll;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    SocketService.instance.on(_event, _onSocket);
    SocketService.instance.on(_mentionEvent, _onMention);
    await SocketService.instance.ensureConnected();
    await refreshUnread();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => refreshUnread());
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _poll?.cancel();
    _poll = null;
    SocketService.instance.off(_event, _onSocket);
    SocketService.instance.off(_mentionEvent, _onMention);
    unreadCount.value = 0;
  }

  void _onSocket(dynamic raw) {
    final map = asMap(raw);
    if (map == null) return;
    final item = NotificationItem.fromJson(map);
    unreadCount.value = unreadCount.value + 1;
    _incoming.add(item);
    NotificationBanner.show(item);
  }

  void _onMention(dynamic raw) {
    final map = asMap(raw);
    if (map == null) return;
    final conversationId = (map['conversationId'] ?? '').toString();
    if (conversationId.isEmpty) return;
    if (SocketService.instance.activeConversationId == conversationId) return;
    final sender = map['sender'] is Map ? Map<String, dynamic>.from(map['sender']) : <String, dynamic>{};
    final name = (sender['name'] ?? '').toString();
    final avatar = (sender['avatarUrl'] ?? sender['avatar'])?.toString();
    final item = NotificationItem(
      id: 'mention-${map['messageId'] ?? DateTime.now().microsecondsSinceEpoch}',
      recipientId: '',
      type: NotificationType.directMessage,
      title: name.isEmpty ? 'You were mentioned' : '$name mentioned you',
      body: (map['content'] ?? '').toString(),
      data: {'conversationId': conversationId},
      isRead: true,
      createdAt: DateTime.now(),
      actor: NotificationActor(
        id: (sender['id'] ?? '').toString(),
        name: name,
        avatar: (avatar == null || avatar.isEmpty) ? null : avatar,
      ),
    );
    NotificationBanner.show(item);
  }

  Future<void> refreshUnread() async {
    try {
      unreadCount.value = await NotificationRepository.instance.unreadCount();
    } catch (_) {}
  }

  Future<void> markRead(NotificationItem n) async {
    if (n.isRead) return;
    unreadCount.value = max(0, unreadCount.value - 1);
    try {
      await NotificationRepository.instance.markRead(n.id);
    } catch (_) {
      await refreshUnread();
    }
  }

  void setUnread(int value) => unreadCount.value = max(0, value);
}
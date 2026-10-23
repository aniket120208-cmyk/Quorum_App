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

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);
  final StreamController<NotificationItem> _incoming = StreamController<NotificationItem>.broadcast();

  Stream<NotificationItem> get incoming => _incoming.stream;

  bool _started = false;
  Timer? _poll;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    SocketService.instance.on(_event, _onSocket);
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
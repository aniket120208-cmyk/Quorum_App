import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/presence_repository.dart';
import 'package:quorum_app/api/socket_service.dart';
import 'package:quorum_app/models/presence_models.dart';

class PresenceService extends ChangeNotifier with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  static const String _event = 'presence:status-updated';

  final PresenceRepository _repo = PresenceRepository.instance;
  final Map<String, UserPresence> _presences = {};
  final Set<String> _requested = {};
  final Set<String> _queue = {};
  Timer? _flushTimer;
  bool _started = false;
  String _lifecycle = 'active';

  UserPresence? of(String userId) => _presences[userId];

  UserPresence? get mine => _presences[CurrentUser.id];

  bool get isDnd => mine?.isDnd == true;

  int onlineCount(Iterable<String> userIds) {
    var n = 0;
    for (final id in userIds) {
      final p = _presences[id];
      if (p != null && p.effective != PresenceStatus.offline) n++;
    }
    return n;
  }

  void start() {
    if (_started) return;
    _started = true;
    SocketService.instance.on(_event, _onUpdate);
    SocketService.instance.addConnectionListener(_onConnection);
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = 'active';
    _emitLifecycle();
    watch(CurrentUser.id);
  }

  void stop() {
    if (!_started) return;
    _started = false;
    SocketService.instance.off(_event, _onUpdate);
    SocketService.instance.removeConnectionListener(_onConnection);
    WidgetsBinding.instance.removeObserver(this);
    _flushTimer?.cancel();
    _flushTimer = null;
    _presences.clear();
    _requested.clear();
    _queue.clear();
    notifyListeners();
  }

  void watch(String userId) {
    if (userId.isEmpty || _requested.contains(userId)) return;
    _requested.add(userId);
    _queue.add(userId);
    _flushTimer ??= Timer(const Duration(milliseconds: 200), _drain);
  }

  void watchAll(Iterable<String> userIds) {
    for (final id in userIds) {
      watch(id);
    }
  }

  Future<void> _drain() async {
    _flushTimer = null;
    if (_queue.isEmpty) return;
    final ids = _queue.toList();
    _queue.clear();
    for (var i = 0; i < ids.length; i += 100) {
      final chunk = ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100);
      try {
        final result = await _repo.batch(chunk);
        _presences.addAll(result);
        for (final id in chunk) {
          if (!result.containsKey(id)) _presences.putIfAbsent(id, () => UserPresence.fromJson({'isOnline': false}));
        }
        notifyListeners();
      } catch (_) {
        _requested.removeAll(chunk);
      }
    }
  }

  void _onUpdate(dynamic raw) {
    final map = asMap(raw);
    if (map == null) return;
    final id = (map['userId'] ?? '').toString();
    if (id.isEmpty) return;
    _presences[id] = UserPresence.fromJson(map);
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lifecycle = 'active';
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _lifecycle = 'background';
    } else {
      return;
    }
    _emitLifecycle();
  }

  void _emitLifecycle() {
    SocketService.instance.emit('client:lifecycle', {'state': _lifecycle});
  }

  void _onConnection(bool connected) {
    if (connected) _emitLifecycle();
    if (!connected || _presences.isEmpty) return;
    final ids = _presences.keys.toList();
    _requested.removeAll(ids);
    watchAll(ids);
  }

  Future<String?> setStatus({
    required PresenceStatus status,
    String? message,
    int? clearAfterMinutes,
  }) async {
    try {
      final result = await _repo.setStatus(status: status, message: message, clearAfterMinutes: clearAfterMinutes);
      if (CurrentUser.id.isNotEmpty) {
        _presences[CurrentUser.id] = result;
        notifyListeners();
      }
      return null;
    } catch (e) {
      return e is ApiException ? e.message : 'Could not update your status';
    }
  }

  Future<String?> reset() async {
    try {
      await _repo.clearStatus();
      if (CurrentUser.id.isNotEmpty) {
        final fresh = await _repo.single(CurrentUser.id);
        _presences[CurrentUser.id] = fresh ?? UserPresence.fromJson({'isOnline': true, 'status': 'AVAILABLE'});
        notifyListeners();
      }
      return null;
    } catch (e) {
      return e is ApiException ? e.message : 'Could not reset your status';
    }
  }
}
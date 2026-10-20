import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:quorum_app/api/api_client.dart';

typedef SocketHandler = void Function(dynamic data);

Map<String, dynamic>? asMap(dynamic d) {
  if (d is List && d.isNotEmpty) d = d.first;
  if (d is Map) return Map<String, dynamic>.from(d);
  return null;
}

class SocketService {
  SocketService._();
  static final SocketService instance = SocketService._();
  static const _url = 'https://api.newquorum.me';

  io.Socket? _s;
  final Set<String> _rooms = {};
  final Map<String, Set<SocketHandler>> _handlers = {};
  bool _refreshing = false;

  bool get isConnected => _s?.connected ?? false;
  Future<void> ensureConnected() async {
    if (_s != null) return;
    final token = await ApiClient.instance.tokenStorage.getAccessToken();
    if (token == null || token.isEmpty) return;
    _create(token);
  }

  void _create(String token) {
    _s?.dispose();
    final sock = io.io(
      _url,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .disableAutoConnect()
          .build(),
    );
    _s = sock;

    _handlers.forEach((event, set) {
      for (final h in set) {
        sock.on(event, h);
      }
    });

    sock.onConnect((_) {
      if (kDebugMode) debugPrint('socket connected ${sock.id}');
      for (final id in _rooms) {
        sock.emitWithAck('conversation:join', {'conversationId': id},
            ack: (_) {});
      }
    });

    sock.onConnectError((e) {
      if (kDebugMode) debugPrint('socket connect error: $e');
      _refreshAndReconnect();
    });
    sock.connect();
  }

  Future<void> _refreshAndReconnect() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final store = ApiClient.instance.tokenStorage;
      final before = await store.getAccessToken();
      await ApiClient.instance.dio.get('/api/auth/me');
      final after = await store.getAccessToken();
      if (after != null && after.isNotEmpty && after != before) {
        _create(after);
      }
    } catch (_) {
    } finally {
      _refreshing = false;
    }
  }

  void on(String event, SocketHandler h) {
    _handlers.putIfAbsent(event, () => {}).add(h);
    _s?.on(event, h);
  }

  void off(String event, SocketHandler h) {
    _handlers[event]?.remove(h);
    _s?.off(event, h);
  }

  void join(String convId) {
    _rooms.add(convId);
    if (isConnected) {
      _s!.emitWithAck('conversation:join', {'conversationId': convId},
          ack: (_) {});
    }
  }

  void leave(String convId) {
    _rooms.remove(convId);
    if (isConnected) {
      _s!.emitWithAck('conversation:leave', {'conversationId': convId},
          ack: (_) {});
    }
  }

  void emit(String event, Map<String, dynamic> data) {
    if (isConnected) _s!.emit(event, data);
  }

  void emitAck(String event, Map<String, dynamic> data,
      void Function(Map<String, dynamic>? res) cb) {
    final sock = _s;
    if (sock == null || !sock.connected) {
      cb(null);
      return;
    }
    var done = false;
    final timer = Timer(const Duration(seconds: 10), () {
      if (done) return;
      done = true;
      cb(null);
    });
    sock.emitWithAck(event, data, ack: (d) {
      if (done) return;
      done = true;
      timer.cancel();
      cb(asMap(d));
    });
  }

  void disconnect() {
    _rooms.clear();
    _s?.dispose();
    _s = null;
  }
}
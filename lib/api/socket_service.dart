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
  final Set<String> _teamRooms = {};
  final Set<String> _communityRooms = {};
  final Set<String> _channelRooms = {};
  final Set<String> _postRooms = {};
  final Map<String, Set<SocketHandler>> _handlers = {};
  bool _refreshing = false;

  String? activeConversationId;

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
      for (final id in _teamRooms) {
        sock.emit('join:conversation', id);
      }
      for (final id in _communityRooms) {
        sock.emit('community:join', {'communityId': id});
      }
      for (final id in _channelRooms) {
        sock.emit('community:channel:join', {'channelId': id});
      }
      for (final id in _postRooms) {
        sock.emit('community:post:join', {'postId': id});
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

  void joinTeamRoom(String conversationId) {
    _teamRooms.add(conversationId);
    if (isConnected) _s!.emit('join:conversation', conversationId);
  }

  void leaveTeamRoom(String conversationId) {
    _teamRooms.remove(conversationId);
  }

  void joinCommunity(String id) {
    _communityRooms.add(id);
    if (isConnected) _s!.emit('community:join', {'communityId': id});
  }

  void leaveCommunity(String id) {
    _communityRooms.remove(id);
    if (isConnected) _s!.emit('community:leave', {'communityId': id});
  }

  void joinChannel(String id) {
    _channelRooms.add(id);
    if (isConnected) _s!.emit('community:channel:join', {'channelId': id});
  }

  void leaveChannel(String id) {
    _channelRooms.remove(id);
    if (isConnected) _s!.emit('community:channel:leave', {'channelId': id});
  }

  void joinPost(String id) {
    _postRooms.add(id);
    if (isConnected) _s!.emit('community:post:join', {'postId': id});
  }

  void leavePost(String id) {
    _postRooms.remove(id);
    if (isConnected) _s!.emit('community:post:leave', {'postId': id});
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
    _teamRooms.clear();
    _communityRooms.clear();
    _channelRooms.clear();
    _postRooms.clear();
    activeConversationId = null;
    _s?.dispose();
    _s = null;
  }
}
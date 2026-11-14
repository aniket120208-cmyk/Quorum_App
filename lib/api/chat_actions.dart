import 'dart:async';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/chat_repository.dart';
import 'package:quorum_app/api/socket_service.dart';

String socketErrorCode(Map<String, dynamic> res) {
  final err = res['error'];
  return (res['code'] ?? (err is Map ? err['code'] : null) ?? '').toString();
}

String socketErrorMessage(Map<String, dynamic> res) {
  final err = res['error'];
  final raw = (res['message'] ?? (err is Map ? err['message'] : null) ?? '').toString().trim();
  switch (socketErrorCode(res)) {
    case 'UNAUTHORIZED':
      return 'Your session expired. Please sign in again.';
    case 'NOT_PARTICIPANT':
      return 'You are not part of this conversation.';
    case 'FORBIDDEN':
      return raw.isNotEmpty ? raw : 'You do not have permission to do that.';
    case 'RATE_LIMITED':
      return 'Slow down a little and try again.';
    case 'INVALID_PAYLOAD':
      return raw.isNotEmpty ? raw : 'That request was not valid.';
    case 'NOT_FOUND':
      return 'This conversation or message no longer exists.';
    case 'SERVER_ERROR':
      return 'Something went wrong on our side. Try again shortly.';
  }
  return raw.isNotEmpty ? raw : 'Something went wrong';
}

class ChatActions {
  ChatActions._();
  static final ChatActions instance = ChatActions._();

  final SocketService _socket = SocketService.instance;
  final ChatRepository _repo = ChatRepository.instance;

  Future<T> _run<T>(
    String event,
    Map<String, dynamic> data,
    T Function(Map<String, dynamic> res) fromAck,
    Future<T> Function() rest,
  ) async {
    final completer = Completer<Map<String, dynamic>?>();
    final started = DateTime.now();
    _socket.emitAck(event, data, completer.complete);
    final res = await completer.future;
    if (res == null) {
      if (DateTime.now().difference(started) > const Duration(seconds: 5)) {
        throw ApiException('The request timed out. Please try again.');
      }
      return rest();
    }
    if (res['success'] != true) throw ApiException(socketErrorMessage(res));
    return fromAck(res);
  }

  Future<DateTime?> mute(String conversationId, {int? durationSeconds}) => _run<DateTime?>(
        'conversation:mute',
        {
          'conversationId': conversationId,
          if (durationSeconds != null && durationSeconds > 0) 'duration': durationSeconds,
        },
        (res) {
          final d = res['data'];
          if (d is! Map) return null;
          return DateTime.tryParse((d['mutedUntil'] ?? '').toString())?.toLocal();
        },
        () => _repo.muteConversation(conversationId, durationSeconds: durationSeconds),
      );

  Future<void> unmute(String conversationId) => _run<void>(
        'conversation:unmute',
        {'conversationId': conversationId},
        (_) {},
        () => _repo.unmuteConversation(conversationId),
      );

  Future<void> block(String conversationId) => _run<void>(
        'conversation:block',
        {'conversationId': conversationId},
        (_) {},
        () => _repo.blockConversation(conversationId),
      );

  Future<void> unblock(String conversationId) => _run<void>(
        'conversation:unblock',
        {'conversationId': conversationId},
        (_) {},
        () => _repo.unblockConversation(conversationId),
      );

  Future<void> clear(String conversationId) => _run<void>(
        'conversation:clear',
        {'conversationId': conversationId},
        (_) {},
        () => _repo.clearConversation(conversationId),
      );

  Future<void> deleteConversation(String conversationId) => _run<void>(
        'conversation:delete',
        {'conversationId': conversationId},
        (_) {},
        () => _repo.deleteConversation(conversationId),
      );
}
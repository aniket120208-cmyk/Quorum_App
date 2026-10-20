import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/chat_models.dart';

class ChatRepository {
  ChatRepository._(this.api);
  static final ChatRepository instance = ChatRepository._(ApiClient.instance);
  final ApiClient api;

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = (data is Map && data['message'] != null) ? data['message'].toString() : 'Cannot reach the server. Try again.';
      throw ApiException(msg, statusCode: e.response?.statusCode);
    }
  }

  List _asList(dynamic d, String key) {
    if (d is List) return d;
    if (d is Map && d[key] is List) return d[key] as List;
    return const [];
  }

  String _idOf(dynamic d) {
    final conv = (d is Map && d['conversation'] is Map) ? d['conversation'] : d;
    return conv['id'].toString();
  }

  Future<List<Conversation>> conversations(String myId) => _guard(() async {
        final r = await api.dio.get('/api/conversations');
        return _asList(r.data['data'], 'conversations')
            .map((j) => Conversation.fromJson(
                Map<String, dynamic>.from(j as Map), myId))
            .toList();
      });

  Future<Conversation?> conversationById(String id, String myId) async {
    final list = await conversations(myId);
    for (final c in list) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<String> startDm(String targetUserId) => _guard(() async {
        final r = await api.dio.post('/api/dm', data: {'targetUserId': targetUserId});
        return _idOf(r.data['data']);
      });

  Future<String> createGroup({
    required String name,
    required List<String> participantIds,
    String? avatar,
  }) =>
      _guard(() async {
        final r = await api.dio.post('/api/conversations/group', data: {
          'name': name,
          if (avatar != null) 'avatar': avatar,
          'participantIds': participantIds,
        });
        return _idOf(r.data['data']);
      });

  Future<void> addParticipants(String convId, List<String> participantIds) =>
      _guard(() async {
        await api.dio.post('/api/conversations/$convId/participants',
            data: {'participantIds': participantIds});
      });

  Future<void> removeParticipant(String convId, String userId) =>
      _guard(() async {
        await api.dio.delete('/api/conversations/$convId/participants/$userId');
      });

  Future<void> updateGroup(
    String convId, {
    String? name,
    String? avatar,
    bool clearAvatar = false,
  }) =>
      _guard(() async {
        await api.dio.patch('/api/conversations/$convId', data: {
          if (name != null) 'name': name,
          if (avatar != null || clearAvatar) 'avatar': avatar,
        });
      });

  Future<void> transferOwnership(String convId, String newOwnerId) =>
      _guard(() async {
        await api.dio.post('/api/conversations/$convId/transfer-ownership',
            data: {'newOwnerId': newOwnerId});
      });

  Future<({List<ChatMessage> items, String? cursor, bool hasMore})> messages(
    String convId, {
    String? cursor,
  }) =>
      _guard(() async {
        final r = await api.dio.get(
          '/api/conversations/$convId/messages',
          queryParameters: {'limit': 30, if (cursor != null) 'cursor': cursor},
        );
        final d = r.data['data'];
        final items = _asList(d, 'messages')
            .map((e) =>
                ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return (
          items: items,
          cursor: d['nextCursor']?.toString(),
          hasMore: d['hasNextPage'] == true,
        );
      });

  Future<List<ChatUser>> searchUsers(String q) => _guard(() async {
        Response r;
        try {
          r = await api.dio.get('/api/users/search', queryParameters: {'q': q});
        } on DioException catch (e) {
          if (e.response?.statusCode != 404) rethrow;
          r = await api.dio.get('/api/user/search', queryParameters: {'q': q});
        }
        return _asList(r.data['data'], 'users')
            .map((e) => ChatUser.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      });
}
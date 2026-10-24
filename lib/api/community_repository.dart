import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'package:quorum_app/models/community_models.dart';

class CommunityRepository {
  CommunityRepository._(this.api);
  static final CommunityRepository instance = CommunityRepository._(ApiClient.instance);
  final ApiClient api;

  Dio get _dio => api.dio;

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      var msg = data is Map ? data['message']?.toString() : null;
      if (msg == null || msg.isEmpty) {
        switch (status) {
          case null:
            msg = 'Cannot reach the server. Try again.';
          case 403:
            msg = 'You do not have permission to do that.';
          case 404:
            msg = 'That item was not found.';
          case 410:
            msg = 'This invitation link has expired.';
          default:
            msg = 'Request failed ($status).';
        }
      }
      throw ApiException(msg, statusCode: status);
    }
  }

  dynamic _data(Response r) => r.data is Map ? r.data['data'] : null;

  Map<String, dynamic> _map(dynamic d) => Map<String, dynamic>.from(d as Map);

  List _list(dynamic d, String key) {
    if (d is List) return d;
    if (d is Map && d[key] is List) return d[key] as List;
    return const [];
  }

  PageResult<T> _page<T>(dynamic d, String key, T Function(Map<String, dynamic>) parse) {
    final items = _list(d, key).map((e) => parse(_map(e))).toList();
    return PageResult<T>(
      items,
      d is Map ? d['nextCursor']?.toString() : null,
      d is Map && d['hasNextPage'] == true,
    );
  }

  Map<String, dynamic> _paging(String? cursor, int limit) =>
      {'limit': limit, if (cursor != null) 'cursor': cursor};

  Future<List<Community>> communities() => _guard(() async {
        final r = await _dio.get('/api/communities');
        return _list(_data(r), 'communities').map((e) => Community.fromJson(_map(e))).toList();
      });

  Future<Community> createCommunity(String name, String description) => _guard(() async {
        final r = await _dio.post('/api/communities', data: {
          'name': name,
          if (description.isNotEmpty) 'description': description,
        });
        return Community.fromJson({..._map(_data(r)), 'role': 'OWNER', 'memberCount': 1});
      });

  Future<CommunityDetail> detail(String id) => _guard(() async {
        final r = await _dio.get('/api/communities/$id');
        return CommunityDetail.fromJson(_map(_data(r)));
      });

  Future<void> updateCommunity(String id, {required String name, required String description}) =>
      _guard(() async {
        await _dio.patch('/api/communities/$id', data: {
          'name': name,
          'description': description,
        });
      });

  Future<void> deleteCommunity(String id) => _guard(() async {
        await _dio.delete('/api/communities/$id');
      });

  Future<PageResult<CommunityMember>> members(String id, {String? cursor, int limit = 20}) =>
      _guard(() async {
        final r = await _dio.get('/api/communities/$id/members', queryParameters: _paging(cursor, limit));
        return _page(_data(r), 'members', CommunityMember.fromJson);
      });

  Future<void> leave(String id) => _guard(() async {
        await _dio.post('/api/communities/$id/leave');
      });

  Future<void> removeMember(String id, String userId) => _guard(() async {
        await _dio.delete('/api/communities/$id/members/$userId');
      });

  Future<InviteLink> createInvite(String id, int expiresInDays) => _guard(() async {
        final r = await _dio.post('/api/communities/$id/invites', data: {'expiresInHours': expiresInDays * 24});
        return InviteLink.fromJson(_map(_data(r)));
      });

  Future<void> inviteUser(String id, String userId) => _guard(() async {
        await _dio.post('/api/communities/$id/invites', data: {'invitedUserId': userId});
      });

  Future<void> acceptInvite(String inviteId) => _guard(() async {
        await _dio.post('/api/communities/invites/$inviteId/accept');
      });

  Future<void> declineInvite(String inviteId) => _guard(() async {
        await _dio.post('/api/communities/invites/$inviteId/decline');
      });

  Future<InvitePreview> previewInvite(String token) => _guard(() async {
        final r = await _dio.get('/api/communities/invites/$token');
        return InvitePreview.fromJson(_map(_data(r)));
      });

  Future<Community> joinInvite(String token) => _guard(() async {
        final r = await _dio.post('/api/communities/join/$token');
        return Community.fromJson(_map(_data(r)));
      });

  Future<PageResult<ChatUser>> searchUsers(String id, String q, {String? cursor, int limit = 20}) =>
      _guard(() async {
        final r = await _dio.get(
          '/api/communities/$id/users/search',
          queryParameters: {'q': q, ..._paging(cursor, limit)},
        );
        return _page(_data(r), 'users', ChatUser.fromJson);
      });

  Future<PageResult<CommunityPost>> posts(String id, {String? cursor, int limit = 20}) =>
      _guard(() async {
        final r = await _dio.get('/api/communities/$id/posts', queryParameters: _paging(cursor, limit));
        return _page(_data(r), 'posts', CommunityPost.fromJson);
      });

  Future<List<CommunityChannel>> channels(String communityId) => _guard(() async {
        final r = await _dio.get('/api/communities/$communityId/channels');
        return _list(_data(r), 'channels').map((e) => CommunityChannel.fromJson(_map(e))).toList();
      });

  Future<CommunityChannel> createChannel(String communityId, String name, String description) =>
      _guard(() async {
        final r = await _dio.post('/api/communities/$communityId/channels', data: {
          'name': name,
          if (description.isNotEmpty) 'description': description,
        });
        return CommunityChannel.fromJson(_map(_data(r)));
      });

  Future<void> updateChannel(String communityId, String channelId,
          {required String name, required String description}) =>
      _guard(() async {
        await _dio.patch('/api/communities/$communityId/channels/$channelId', data: {
          'name': name,
          'description': description,
        });
      });

  Future<void> deleteChannel(String communityId, String channelId) => _guard(() async {
        await _dio.delete('/api/communities/$communityId/channels/$channelId');
      });

  Future<PageResult<CommunityPost>> channelPosts(String communityId, String channelId,
          {String? cursor, int limit = 20}) =>
      _guard(() async {
        final page = int.tryParse(cursor ?? '') ?? 1;
        final r = await _dio.get(
          '/api/communities/$communityId/channels/$channelId/posts',
          queryParameters: {'page': page, 'limit': limit},
        );
        final d = _data(r);
        final items = _list(d, 'posts').map((e) => CommunityPost.fromJson(_map(e))).toList();
        final top = r.data is Map ? r.data as Map : const {};
        final Map meta = top['pagination'] is Map
            ? top['pagination'] as Map
            : (d is Map && d['pagination'] is Map ? d['pagination'] as Map : (d is Map ? d : const {}));
        final totalPages = int.tryParse('${meta['totalPages'] ?? ''}');
        final more = meta['hasNextPage'] == true ||
            meta['hasMore'] == true ||
            (totalPages != null ? page < totalPages : items.length >= limit);
        return PageResult<CommunityPost>(items, more ? '${page + 1}' : null, more);
      });

  Future<CommunityPost> createChannelPost(
    String communityId,
    String channelId,
    String content, {
    String? fileUrl,
    String? fileType,
  }) =>
      _guard(() async {
        final r = await _dio.post('/api/communities/$communityId/channels/$channelId/posts', data: {
          'content': content,
          if (fileUrl != null) 'fileUrl': fileUrl,
          if (fileUrl != null && fileType != null) 'fileType': fileType,
        });
        return CommunityPost.fromJson(_map(_data(r)));
      });

  Future<CommunityPost> createPost(String id, String content,
          {String? fileUrl, String? fileType}) =>
      _guard(() async {
        final r = await _dio.post('/api/communities/$id/posts', data: {
          'content': content,
          if (fileUrl != null) 'fileUrl': fileUrl,
          if (fileUrl != null && fileType != null) 'fileType': fileType,
        });
        return CommunityPost.fromJson(_map(_data(r)));
      });

  Future<void> editPost(String postId, String content) => _guard(() async {
        await _dio.patch('/api/community-posts/$postId', data: {'content': content});
      });

  Future<void> deletePost(String postId) => _guard(() async {
        await _dio.delete('/api/community-posts/$postId');
      });

  Future<PageResult<CommunityComment>> comments(String postId, {String? cursor, int limit = 20}) =>
      _guard(() async {
        final r = await _dio.get('/api/community-posts/$postId/comments', queryParameters: _paging(cursor, limit));
        return _page(_data(r), 'comments', CommunityComment.fromJson);
      });

  Future<CommunityComment> createComment(String postId, String content) => _guard(() async {
        final r = await _dio.post('/api/community-posts/$postId/comments', data: {'content': content});
        return CommunityComment.fromJson(_map(_data(r)));
      });

  Future<void> editComment(String commentId, String content) => _guard(() async {
        await _dio.patch('/api/community-comments/$commentId', data: {'content': content});
      });

  Future<void> deleteComment(String commentId) => _guard(() async {
        await _dio.delete('/api/community-comments/$commentId');
      });
}
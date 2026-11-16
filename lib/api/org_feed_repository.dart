import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/org_feed_models.dart';

class OrgFeedRepository {
  OrgFeedRepository._(this.api);
  static final OrgFeedRepository instance = OrgFeedRepository._(ApiClient.instance);
  final ApiClient api;

  Dio get _dio => api.dio;

  String _base(String orgId) => '/api/v1/organizations/$orgId/feed';

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
          case 400:
            msg = 'That request was not valid.';
          case 401:
            msg = 'Unauthorized, login required.';
          case 403:
            msg = 'You do not have permission to do that.';
          case 404:
            msg = 'This post is no longer available.';
          case 429:
            msg = 'You are doing that too fast. Try again in a minute.';
          default:
            msg = 'Request failed ($status).';
        }
      }
      throw ApiException(msg, statusCode: status);
    }
  }

  dynamic _data(Response r) => r.data is Map ? r.data['data'] : null;
  Map<String, dynamic> _map(dynamic d) => d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};

  List _list(dynamic d, String key) {
    if (d is List) return d;
    if (d is Map && d[key] is List) return d[key] as List;
    return const [];
  }

  Future<OrgFeedPage> feed(
    String orgId, {
    OrgPostCategory? category,
    String? teamId,
    String? search,
    bool pinnedOnly = false,
    String? cursor,
    int limit = 20,
  }) =>
      _guard(() async {
        final r = await _dio.get(_base(orgId), queryParameters: {
          if (category != null) 'category': category.value,
          if (teamId != null && teamId.isNotEmpty) 'teamId': teamId,
          if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
          if (pinnedOnly) 'pinnedOnly': true,
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
          'limit': limit.clamp(1, 50),
        });
        final d = _data(r);
        final posts = _list(d, 'posts').map((e) => OrgFeedPost.fromJson(_map(e))).toList();
        final map = _map(d);
        return OrgFeedPage(
          posts,
          map['nextCursor']?.toString(),
          map['hasNextPage'] == true,
        );
      });

  Future<OrgFeedPost> getPost(String orgId, String postId) => _guard(() async {
        final r = await _dio.get('${_base(orgId)}/$postId');
        return OrgFeedPost.fromJson(_map(_data(r)));
      });

  Future<OrgFeedPost> createPost(
    String orgId, {
    required OrgPostCategory category,
    String? title,
    String? content,
    String? filePath,
    String? fileName,
    String? targetUserId,
    String? targetTeamId,
    List<String> mentionedUserIds = const [],
  }) =>
      _guard(() async {
        final fields = <String, dynamic>{
          'category': category.value,
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
          if (content != null && content.trim().isNotEmpty) 'content': content.trim(),
          if (targetUserId != null && targetUserId.isNotEmpty) 'targetUserId': targetUserId,
          if (targetTeamId != null && targetTeamId.isNotEmpty) 'targetTeamId': targetTeamId,
        };
        final Response r;
        if (filePath != null) {
          final form = FormData.fromMap({
            ...fields,
            if (mentionedUserIds.isNotEmpty) 'mentionedUserIds': jsonEncode(mentionedUserIds),
            'file': await MultipartFile.fromFile(filePath, filename: fileName),
          });
          r = await _dio.post(
            _base(orgId),
            data: form,
            options: Options(contentType: 'multipart/form-data'),
          );
        } else {
          r = await _dio.post(_base(orgId), data: {
            ...fields,
            if (mentionedUserIds.isNotEmpty) 'mentionedUserIds': mentionedUserIds,
          });
        }
        return OrgFeedPost.fromJson(_map(_data(r)));
      });

  Future<OrgFeedPost> editPost(
    String orgId,
    String postId, {
    String? title,
    required String content,
  }) =>
      _guard(() async {
        final r = await _dio.patch('${_base(orgId)}/$postId', data: {
          'title': title?.trim() ?? '',
          'content': content.trim(),
        });
        return OrgFeedPost.fromJson(_map(_data(r)));
      });

  Future<void> deletePost(String orgId, String postId) => _guard(() async {
        await _dio.delete(
          '${_base(orgId)}/$postId',
          data: <String, dynamic>{},
          options: Options(contentType: Headers.jsonContentType),
        );
      });

  Future<bool?> togglePin(String orgId, String postId) => _guard(() async {
        final r = await _dio.post('${_base(orgId)}/$postId/pin', data: <String, dynamic>{});
        final d = _map(_data(r));
        final inner = d['post'] is Map ? _map(d['post']) : d;
        if (inner['isPinned'] is bool) return inner['isPinned'] as bool;
        return null;
      });

  Future<OrgReactResult> react(String orgId, String postId, String emoji) => _guard(() async {
        final r = await _dio.post('${_base(orgId)}/$postId/react', data: {'emoji': emoji});
        final d = _map(_data(r));
        return OrgReactResult(
          (d['action'] ?? '').toString(),
          OrgFeedReaction.listFrom(d['reactions']),
        );
      });

  Future<OrgCommentsPage> comments(
    String orgId,
    String postId, {
    String? cursor,
    int limit = 20,
  }) =>
      _guard(() async {
        final r = await _dio.get('${_base(orgId)}/$postId/comments', queryParameters: {
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
          'limit': limit.clamp(1, 50),
        });
        final d = _data(r);
        final map = _map(d);
        return OrgCommentsPage(
          _list(d, 'comments').map((e) => OrgFeedComment.fromJson(_map(e))).toList(),
          map['nextCursor']?.toString(),
          map['hasNextPage'] == true,
        );
      });

  Future<OrgFeedComment> addComment(
    String orgId,
    String postId, {
    required String content,
    String? parentId,
  }) =>
      _guard(() async {
        final r = await _dio.post('${_base(orgId)}/$postId/comments', data: {
          'content': content.trim(),
          if (parentId != null && parentId.isNotEmpty) 'parentId': parentId,
        });
        return OrgFeedComment.fromJson(_map(_data(r)));
      });

  Future<OrgFeedComment> editComment(
    String orgId,
    String postId,
    String commentId, {
    required String content,
  }) =>
      _guard(() async {
        final r = await _dio.patch(
          '${_base(orgId)}/$postId/comments/$commentId',
          data: {'content': content.trim()},
        );
        return OrgFeedComment.fromJson(_map(_data(r)));
      });

  Future<void> deleteComment(String orgId, String postId, String commentId) => _guard(() async {
        await _dio.delete(
          '${_base(orgId)}/$postId/comments/$commentId',
          data: <String, dynamic>{},
          options: Options(contentType: Headers.jsonContentType),
        );
      });
}
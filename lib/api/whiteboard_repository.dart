import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/whiteboard_models.dart';

class WhiteboardRepository {
  WhiteboardRepository._();
  static final WhiteboardRepository instance = WhiteboardRepository._();

  Dio get _dio => ApiClient.instance.dio;

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
          case 401:
            msg = 'Unauthorized, login required.';
          case 403:
            msg = 'You do not have permission to do that.';
          case 404:
            msg = 'Whiteboard not found.';
          default:
            msg = 'Request failed ($status).';
        }
      }
      throw ApiException(msg, statusCode: status);
    }
  }

  dynamic _data(Response r) => r.data is Map ? r.data['data'] : null;

  Future<WhiteboardPage> list(
    String organizationId, {
    int page = 1,
    int limit = 20,
    String? search,
  }) =>
      _guard(() async {
        final r = await _dio.get('/api/whiteboards', queryParameters: {
          'organizationId': organizationId,
          'page': page,
          'limit': limit,
          if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        });
        return WhiteboardPage.fromJson(_data(r), page: page, limit: limit);
      });

  Future<Whiteboard> get(String id) => _guard(() async {
        final r = await _dio.get('/api/whiteboards/$id');
        return Whiteboard.fromJson(_data(r));
      });

  Future<Whiteboard> create({
    required String name,
    required String organizationId,
    Map<String, dynamic>? content,
  }) =>
      _guard(() async {
        final r = await _dio.post('/api/whiteboards', data: {
          'name': name,
          'organizationId': organizationId,
          'content': content ?? emptyWhiteboardContent(),
        });
        return Whiteboard.fromJson(_data(r));
      });

  Future<void> rename(String id, String name) => _guard(() async {
        await _dio.patch('/api/whiteboards/$id', data: {'name': name});
      });

  Future<void> delete(String id) => _guard(() async {
        await _dio.delete('/api/whiteboards/$id');
      });

  Future<List<Whiteboard>> meetingBoards(String code) => _guard(() async {
        final r = await _dio.get('/api/meetings/$code/whiteboards');
        final d = _data(r);
        final raw = d is List
            ? d
            : d is Map
                ? (d['whiteboards'] ?? d['items'] ?? d['boards'] ?? const [])
                : const [];
        return (raw as List).map(Whiteboard.fromJson).where((b) => b.id.isNotEmpty).toList();
      });

  Future<Whiteboard> createInMeeting(String code, {required String name}) => _guard(() async {
        final r = await _dio.post('/api/meetings/$code/whiteboards', data: {
          'name': name,
          'content': emptyWhiteboardContent(),
        });
        return Whiteboard.fromJson(_data(r));
      });

  Future<OpenedWhiteboard> openInMeeting(String code, String whiteboardId) => _guard(() async {
        final r = await _dio.post(
          '/api/meetings/$code/whiteboards/$whiteboardId/open',
          data: <String, dynamic>{},
        );
        return OpenedWhiteboard.fromJson(_data(r));
      });
}
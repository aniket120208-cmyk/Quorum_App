import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/notification_models.dart';

class NotificationRepository {
  NotificationRepository._(this.api);
  static final NotificationRepository instance = NotificationRepository._(ApiClient.instance);
  final ApiClient api;

  static const String _base = '/api/notifications';

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
          case 401:
            msg = 'Unauthorized, login required.';
          case 404:
            msg = 'Notification not found.';
          default:
            msg = 'Request failed ($status).';
        }
      }
      throw ApiException(msg, statusCode: status);
    }
  }

  Map<String, dynamic> _map(dynamic d) => d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};

  dynamic _data(Response r) => r.data is Map ? r.data['data'] : null;

  Future<NotificationPage> fetch({int page = 1, int limit = 20, bool unreadOnly = false}) => _guard(() async {
        final r = await _dio.get(_base, queryParameters: {
          'page': page,
          'limit': limit,
          if (unreadOnly) 'unreadOnly': 'true',
        });
        final d = _map(_data(r));
        final p = _map(d['pagination']);
        final list = d['notifications'] is List ? d['notifications'] as List : const [];
        return NotificationPage(
          items: list.map((e) => NotificationItem.fromJson(_map(e))).toList(),
          total: int.tryParse('${p['total'] ?? 0}') ?? 0,
          page: int.tryParse('${p['page'] ?? page}') ?? page,
          totalPages: int.tryParse('${p['totalPages'] ?? 1}') ?? 1,
          unreadCount: int.tryParse('${d['unreadCount'] ?? 0}') ?? 0,
        );
      });

  Future<int> unreadCount() => _guard(() async {
        final r = await _dio.get('$_base/unread-count');
        return int.tryParse('${_map(_data(r))['unreadCount'] ?? 0}') ?? 0;
      });

  Future<void> markRead(String id) => _guard(() async {
        await _dio.patch('$_base/$id/read');
      });

  Future<void> markAllRead() => _guard(() async {
        await _dio.patch('$_base/read-all');
      });

  Future<void> delete(String id) => _guard(() async {
        await _dio.delete('$_base/$id');
      });

  Future<List<NotificationPreference>> preferences() => _guard(() async {
        final r = await _dio.get('$_base/preferences');
        final d = _data(r);
        final list = d is List ? d : const [];
        return list.map((e) => NotificationPreference.fromJson(_map(e))).toList();
      });

  Future<NotificationPreference> updatePreference(NotificationPreference p) => _guard(() async {
        final r = await _dio.put('$_base/preferences', data: {
          'notificationType': p.type.value,
          'inApp': p.inApp,
          'push': p.push,
          'email': p.email,
        });
        final d = _data(r);
        return d is Map ? NotificationPreference.fromJson(_map(d)) : p;
      });
}
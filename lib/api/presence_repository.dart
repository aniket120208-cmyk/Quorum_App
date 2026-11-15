import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/presence_models.dart';

class PresenceRepository {
  PresenceRepository._(this.api);
  static final PresenceRepository instance = PresenceRepository._(ApiClient.instance);
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
        msg = status == null ? 'Cannot reach the server. Try again.' : 'Request failed ($status).';
      }
      throw ApiException(msg, statusCode: status);
    }
  }

  Map<String, dynamic> _map(dynamic d) => d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};

  Future<UserPresence> setStatus({
    required PresenceStatus status,
    String? message,
    int? clearAfterMinutes,
  }) =>
      _guard(() async {
        final r = await _dio.patch('/api/users/status', data: {
          'status': status.value,
          if (message != null && message.trim().isNotEmpty) 'statusMessage': message.trim(),
          if (clearAfterMinutes != null) 'clearAfterMinutes': clearAfterMinutes,
        });
        final data = _map(r.data is Map ? r.data['data'] : null);
        return UserPresence.fromJson({...data, 'isOnline': true});
      });

  Future<void> clearStatus() => _guard(() async {
        await _dio.delete('/api/users/status');
      });

  Future<Map<String, UserPresence>> batch(List<String> userIds) => _guard(() async {
        final r = await _dio.post('/api/users/presence/batch', data: {'userIds': userIds});
        final data = _map(r.data is Map ? r.data['data'] : null);
        final presences = _map(data['presences']);
        return {
          for (final e in presences.entries)
            if (e.value is Map) e.key: UserPresence.fromJson(Map<String, dynamic>.from(e.value as Map)),
        };
      });

  Future<UserPresence?> single(String userId) => _guard(() async {
        final r = await _dio.get('/api/users/$userId/presence');
        final data = _map(r.data is Map ? r.data['data'] : null);
        if (data.isEmpty) return null;
        return UserPresence.fromJson(data);
      });
}
import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/office_models.dart';

class OfficeRepository {
  OfficeRepository._(this.api);
  static final OfficeRepository instance = OfficeRepository._(ApiClient.instance);
  final ApiClient api;

  Dio get _dio => api.dio;

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      var msg = data is Map ? (data['message'] ?? data['error'])?.toString() : null;
      if (msg == null || msg.isEmpty) {
        switch (status) {
          case null:
            msg = 'Cannot reach the server. Try again.';
          case 400:
            msg = 'That request was not valid.';
          case 403:
            msg = 'You are not allowed to do that.';
          case 404:
            msg = 'Office not found.';
          case 409:
            msg = 'This desk is already occupied by a teammate';
          case 429:
            msg = 'Please wait a moment before trying again.';
          default:
            msg = 'Request failed ($status).';
        }
      }
      throw ApiException(msg, statusCode: status);
    }
  }

  dynamic _data(Response r) => r.data is Map ? r.data['data'] : null;
  Map<String, dynamic> _map(dynamic d) => d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};

  Future<OfficeState> snapshot(String teamId) => _guard(() async {
        final r = await _dio.get('/api/office/$teamId');
        return OfficeState.fromJson(_map(_data(r)), fallbackTeamId: teamId);
      });

  Future<OfficeState> join(String teamId) => _guard(() async {
        final r = await _dio.post('/api/office/$teamId/join');
        final d = _map(_data(r));
        return OfficeState.fromJson(_map(d['state'] ?? d), fallbackTeamId: teamId);
      });

  Future<void> leave(String teamId) => _guard(() async {
        await _dio.post('/api/office/$teamId/leave', data: <String, dynamic>{});
      });

  Future<void> knock(String teamId, String targetUserId, {String? message}) => _guard(() async {
        await _dio.post('/api/office/$teamId/knock', data: {
          'targetUserId': targetUserId,
          if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
        });
      });

  Future<void> claimDesk(String teamId, String deskId) => _guard(() async {
        await _dio.post('/api/office/$teamId/desk/claim', data: {'deskId': deskId});
      });

  Future<void> changeZone(String teamId, OfficeZone zone, {String? deskId}) => _guard(() async {
        await _dio.post('/api/office/$teamId/zone', data: {'zoneId': zone.apiValue, 'deskId': deskId});
      });

  Future<void> startMeeting(String teamId, String meetingCode) => _guard(() async {
        await _dio.post('/api/office/$teamId/meeting/start', data: {'meetingCode': meetingCode});
      });

  Future<void> endMeeting(String teamId) => _guard(() async {
        await _dio.post('/api/office/$teamId/meeting/end', data: <String, dynamic>{});
      });
}
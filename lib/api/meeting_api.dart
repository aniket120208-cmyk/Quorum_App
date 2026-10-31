import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/meeting_models.dart';

class MeetingApi {
  MeetingApi._();
  static final MeetingApi instance = MeetingApi._();
  static const String _webBase = 'https://newquorum.me/meet';
  static String linkFor(String code) => '$_webBase/$code';
  static final RegExp _codePattern = RegExp(r'^[a-z0-9-]{3,}$');
  static String? codeFromLink(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    final segments = uri == null || !uri.hasScheme ? <String>[] : uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final raw = segments.isNotEmpty ? segments.last : text;
    final code = raw.trim().toLowerCase();
    return _codePattern.hasMatch(code) ? code : null;
  }

  static bool isQuorumLink(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null || !uri.hasScheme) return false;
    final host = uri.host.toLowerCase();
    final quorumHost = host == 'quorum.me' ||
        host == 'newquorum.me' ||
        host == 'quorum.com' ||
        host.endsWith('.quorum.me') ||
        host.endsWith('.newquorum.me') ||
        host.endsWith('.quorum.com');
    return quorumHost && uri.pathSegments.any((s) => s == 'meet');
  }

  Dio get _dio => ApiClient.instance.dio;

  ApiException _toApiException(DioException e) {
    final data = e.response?.data;
    final status = e.response?.statusCode;
    final String fallback;
    switch (status) {
      case null:
        fallback = 'Cannot reach the server. Try again.';
      case 401:
        fallback = 'Please sign in to continue.';
      case 403:
        fallback = 'You do not have access to this meeting.';
      case 404:
        fallback = 'Meeting not found.';
      case 410:
        fallback = 'This meeting has ended or was cancelled.';
      default:
        fallback = 'Request failed ($status).';
    }
    final message = (data is Map && data['message'] != null) ? data['message'].toString() : fallback;
    return ApiException(message, statusCode: status);
  }

  List<ScopedMeeting> _unwrapList(Response response) {
    final body = response.data;
    var data = body is Map ? body['data'] : null;
    if (data is Map && data['meetings'] is List) data = data['meetings'];
    if (data is! List) throw ApiException('Unexpected response from server.');
    return data.whereType<Map>().map((e) => ScopedMeeting.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Map<String, dynamic> _unwrap(Response response) {
    final body = response.data;
    if (body is Map && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    throw ApiException('Unexpected response from server.');
  }

  Future<CreatedMeeting> createMeeting() async {
    try {
      final response = await _dio.post('/api/meetings', data: <String, dynamic>{});
      final data = _unwrap(response);
      final code = data['code'].toString();
      return CreatedMeeting(
        code: code,
        link: (data['link'] ?? linkFor(code)).toString(),
      );
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<ScopedMeeting> createScopedMeeting({
    String? title,
    MeetingScope scope = MeetingScope.personal,
    String? organizationId,
    String? teamId,
    DateTime? scheduledStartTime,
  }) async {
    try {
      final response = await _dio.post('/api/meetings/scoped', data: {
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        'scopeType': scope.value,
        if (scope != MeetingScope.personal && organizationId != null) 'organizationId': organizationId,
        if (scope == MeetingScope.team && teamId != null) 'teamId': teamId,
        if (scheduledStartTime != null) 'scheduledStartTime': scheduledStartTime.toUtc().toIso8601String(),
      });
      return ScopedMeeting.fromJson(_unwrap(response));
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<List<ScopedMeeting>> upcomingMeetings() async {
    try {
      return _unwrapList(await _dio.get('/api/meetings/upcoming'));
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<List<ScopedMeeting>> organizationMeetings(String organizationId) async {
    try {
      return _unwrapList(await _dio.get('/api/meetings/organization/$organizationId'));
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<List<ScopedMeeting>> teamMeetings(String teamId) async {
    try {
      return _unwrapList(await _dio.get('/api/meetings/team/$teamId'));
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<void> cancelMeeting(String code) async {
    try {
      await _dio.patch('/api/meetings/$code/cancel', data: <String, dynamic>{});
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<MeetingInfo> getMeeting(String code) async {
    try {
      final response = await _dio.get('/api/meetings/$code');
      return MeetingInfo.fromJson(_unwrap(response));
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<void> endMeeting(String code) async {
    try {
      await _dio.post('/api/meetings/$code/end', data: <String, dynamic>{});
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }
}
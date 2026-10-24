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
    final quorumHost = host == 'quorum.me' || host == 'newquorum.me' || host.endsWith('.quorum.me') || host.endsWith('.newquorum.me');
    return quorumHost && uri.pathSegments.any((s) => s == 'meet');
  }

  Dio get _dio => ApiClient.instance.dio;

  ApiException _toApiException(DioException e) {
    final data = e.response?.data;
    final message = (data is Map && data['message'] != null) ? data['message'].toString() : 'Cannot reach the server. Try again.';
    return ApiException(message, statusCode: e.response?.statusCode);
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
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/current_user.dart';

class UserService {
  UserService._();
  static final UserService instance = UserService._();
  static const int maxAvatarBytes = 10 * 1024 * 1024;
  static const Map<String, String> _mimeByExt = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'gif': 'image/gif',
  };

  Dio get _dio => ApiClient.instance.dio;

  ApiException _toException(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    var msg = data is Map ? (data['message'] ?? data['error'])?.toString() : null;
    if (msg == null || msg.isEmpty) {
      switch (status) {
        case null:
          msg = 'Cannot reach the server. Try again.';
        case 400:
          msg = 'Invalid profile data.';
        case 401:
          msg = 'Unauthorized, login required.';
        case 413:
          msg = 'File size exceeds allowed limit (10MB)';
        case 429:
          msg = 'Too many attempts. Please try again later.';
        default:
          msg = 'Request failed ($status).';
      }
    }
    return ApiException(msg, statusCode: status);
  }

  Map<String, dynamic> _user(dynamic body) {
    final data = body is Map ? body['data'] : null;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      if (map['user'] is Map) return Map<String, dynamic>.from(map['user']);
      return map;
    }
    if (body is Map && body['user'] is Map) return Map<String, dynamic>.from(body['user']);
    throw ApiException('Unexpected response from server.');
  }

  String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
  }

  Future<Map<String, dynamic>> getProfile() async {
    try {
      final r = await _dio.get('/api/users/profile');
      return _user(r.data);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<Map<String, dynamic>> updateProfile({
    String? name,
    String? avatar,
    List<String>? useCases,
  }) async {
    final trimmed = name?.trim();
    if (name != null && (trimmed == null || trimmed.isEmpty)) {
      throw ApiException('Name cannot be empty', statusCode: 400);
    }
    try {
      final r = await _dio.patch('/api/users/profile', data: {
        if (trimmed != null) 'name': trimmed,
        if (avatar != null) 'avatar': avatar,
        if (useCases != null) 'useCases': useCases,
      });
      final user = _user(r.data);
      CurrentUser.setFromProfile(user);
      return user;
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<Map<String, dynamic>> uploadAvatar({
    required String path,
    String? fileName,
    String? name,
    List<String>? useCases,
    void Function(double progress)? onProgress,
  }) async {
    final resolvedName = (fileName == null || fileName.isEmpty) ? path.split(RegExp(r'[\\/]')).last : fileName;
    final mime = _mimeByExt[_extension(resolvedName)];
    if (mime == null) throw ApiException('File type is not permitted', statusCode: 400);
    if (await File(path).length() > maxAvatarBytes) {
      throw ApiException('File size exceeds allowed limit (10MB)', statusCode: 400);
    }
    final trimmed = name?.trim();
    try {
      final form = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(
          path,
          filename: resolvedName,
          contentType: DioMediaType.parse(mime),
        ),
        if (trimmed != null && trimmed.isNotEmpty) 'name': trimmed,
        if (useCases != null) 'useCases': jsonEncode(useCases),
      });
      final r = await _dio.patch(
        '/api/users/profile',
        data: form,
        options: Options(sendTimeout: const Duration(seconds: 60), receiveTimeout: const Duration(seconds: 60)),
        onSendProgress: (sent, total) {
          if (total > 0) onProgress?.call(sent / total);
        },
      );
      final user = _user(r.data);
      CurrentUser.setFromProfile(user);
      return user;
    } on DioException catch (e) {
      throw _toException(e);
    }
  }
}
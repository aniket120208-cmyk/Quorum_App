import 'dart:io';
import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/upload_service.dart';

enum ProfilePictureTarget { organization, community, group, team }

class ProfilePictureRepository {
  ProfilePictureRepository._();
  static final ProfilePictureRepository instance = ProfilePictureRepository._();
  static const int maxBytes = 5 * 1024 * 1024;
  static const Set<String> allowedExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif'};

  Dio get _dio => ApiClient.instance.dio;

  static String? validate(String fileName, int bytes) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot == -1 ? '' : fileName.substring(dot + 1).toLowerCase();
    if (!allowedExtensions.contains(ext)) return 'Use a JPG, PNG, WEBP or GIF image.';
    if (bytes > maxBytes) return 'Images can be 5 MB at most. Please choose a smaller image.';
    return null;
  }

  static Future<String?> validateFile(String path, String fileName) async {
    return validate(fileName, await File(path).length());
  }

  static String _mimeFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot == -1 ? '' : fileName.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  String _path(ProfilePictureTarget target, String id, {String? parentId}) {
    switch (target) {
      case ProfilePictureTarget.team:
        return '/api/organizations/$parentId/teams/$id/profile-picture';
      case ProfilePictureTarget.organization:
        return '/api/organizations/$id/profile-picture';
      case ProfilePictureTarget.community:
        return '/api/communities/$id/profile-picture';
      case ProfilePictureTarget.group:
        return '/api/groups/$id/profile-picture';
    }
  }

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
          case 401:
            msg = 'Unauthorized, login required.';
          case 403:
            msg = 'You do not have permission to change this picture.';
          case 404:
            msg = 'Not found.';
          case 413:
            msg = 'Images can be 5 MB at most. Please choose a smaller image.';
          default:
            msg = 'Request failed ($status).';
        }
      }
      throw ApiException(msg, statusCode: status);
    }
  }

  String? _avatarFrom(Response r) {
    final body = r.data;
    final data = body is Map ? body['data'] : null;
    if (data is! Map) return null;
    final value = (data['avatarUrl'] ?? data['logo'] ?? data['avatar'])?.toString();
    return value == null || value.isEmpty ? null : value;
  }

  Future<String?> setUrl(ProfilePictureTarget target, String id, String url, {String? parentId}) =>
      _guard(() async {
        final r = await _dio.post(
          _path(target, id, parentId: parentId),
          data: {'avatarUrl': url, 'avatar': url, 'logo': url},
        );
        return _avatarFrom(r) ?? url;
      });

  Future<String?> uploadFile(
    ProfilePictureTarget target,
    String id, {
    required String path,
    required String fileName,
    String? parentId,
    void Function(double progress)? onProgress,
  }) async {
    final problem = await validateFile(path, fileName);
    if (problem != null) throw ApiException(problem);
    if (target != ProfilePictureTarget.group) {
      return _guard(() async {
        final form = FormData.fromMap({
          'file': await MultipartFile.fromFile(
            path,
            filename: fileName,
            contentType: DioMediaType.parse(_mimeFor(fileName)),
          ),
        });
        final r = await _dio.post(
          _path(target, id, parentId: parentId),
          data: form,
          options: Options(sendTimeout: const Duration(seconds: 60), receiveTimeout: const Duration(seconds: 60)),
          onSendProgress: (sent, total) {
            if (total > 0) onProgress?.call(sent / total);
          },
        );
        return _avatarFrom(r);
      });
    }
    final uploaded = await UploadService.instance.upload(
      path: path,
      fileName: fileName,
      onProgress: onProgress,
    );
    return setUrl(target, id, uploaded.url, parentId: parentId);
  }

  Future<String?> fetch(ProfilePictureTarget target, String id, {String? parentId}) => _guard(() async {
        final r = await _dio.get(_path(target, id, parentId: parentId));
        return _avatarFrom(r);
      });

  Future<void> remove(ProfilePictureTarget target, String id, {String? parentId}) => _guard(() async {
        await _dio.delete(_path(target, id, parentId: parentId));
      });
}
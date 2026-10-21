import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';

class UploadResult {
  final String url;
  final String fileType;
  const UploadResult(this.url, this.fileType);
}

class UploadService {
  UploadService._();
  static final UploadService instance = UploadService._();

  static const _imageExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'};
  static const _videoExt = {'mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v', '3gp'};
  static const _audioExt = {'mp3', 'wav', 'm4a', 'aac', 'ogg', 'opus', 'flac'};

  static String fileTypeFor(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
    if (_imageExt.contains(ext)) return 'image';
    if (_videoExt.contains(ext)) return 'video';
    if (_audioExt.contains(ext)) return 'audio';
    return 'file';
  }

  String _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return '';
  }

  String _dioMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final err = data['error'];
      if (err is Map && err['message'] != null) return err['message'].toString();
      if (data['message'] != null) return data['message'].toString();
    }
    return 'Upload failed. Check your connection and try again.';
  }

  Future<UploadResult> upload({
    required String path,
    required String fileName,
    String folder = 'chat_attachments',
    void Function(double progress)? onProgress,
  }) async {
    try {
      final signRes = await ApiClient.instance.dio.post('/api/uploads/sign', data: {'folder': folder});
      final raw = signRes.data['data'] ?? signRes.data;
      final sig = Map<String, dynamic>.from(raw as Map);

      var url = _pick(sig, ['uploadUrl', 'upload_url', 'url']);
      final cloudName = _pick(sig, ['cloudName', 'cloud_name']);
      if (url.isEmpty && cloudName.isNotEmpty) {
        url = 'https://api.cloudinary.com/v1_1/$cloudName/auto/upload';
      }
      final apiKey = _pick(sig, ['apiKey', 'api_key']);
      final timestamp = _pick(sig, ['timestamp']);
      final signature = _pick(sig, ['signature']);
      final signedFolder = _pick(sig, ['folder']);

      if (url.isEmpty || apiKey.isEmpty || timestamp.isEmpty || signature.isEmpty) {
        throw ApiException('Upload signature response is missing fields.');
      }
      url = url.replaceFirstMapped(RegExp(r'/(image|video|raw|auto)/upload'), (_) => '/auto/upload');

      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(path, filename: fileName),
        'api_key': apiKey,
        'timestamp': timestamp,
        'signature': signature,
        if (signedFolder.isNotEmpty) 'folder': signedFolder,
      });

      final res = await Dio().post(
        url,
        data: form,
        onSendProgress: (sent, total) {
          if (total > 0) onProgress?.call(sent / total);
        },
      );

      final body = res.data is String ? jsonDecode(res.data) : res.data;
      final secureUrl = body is Map ? body['secure_url']?.toString() : null;
      if (secureUrl == null || secureUrl.isEmpty) {
        throw ApiException('Upload finished but no file URL was returned.');
      }
      return UploadResult(secureUrl, fileTypeFor(fileName));
    } on DioException catch (e) {
      throw ApiException(_dioMessage(e), statusCode: e.response?.statusCode);
    }
  }
}
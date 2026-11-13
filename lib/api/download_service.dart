import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_saver/file_saver.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadService {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  static const _mimeByExt = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'bmp': 'image/bmp',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'mkv': 'video/x-matroska',
    'webm': 'video/webm',
    'avi': 'video/x-msvideo',
    'm4v': 'video/x-m4v',
    '3gp': 'video/3gpp',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
    'opus': 'audio/opus',
    'flac': 'audio/flac',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'json': 'application/json',
    'zip': 'application/zip',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  };

  static String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static String _baseOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  static String _sanitize(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'download' : cleaned;
  }

  static const _countsKey = 'download_name_counts';

  static Future<Map<String, int>> _readCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_countsKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), v is int ? v : int.tryParse(v.toString()) ?? 0));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeCounts(Map<String, int> counts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_countsKey, jsonEncode(counts));
    } catch (_) {}
  }

  static String _nameFromUrl(String url) {
    final segments = Uri.tryParse(url)?.pathSegments;
    if (segments == null || segments.isEmpty) return '';
    try {
      return Uri.decodeComponent(segments.last);
    } catch (_) {
      return segments.last;
    }
  }

  Future<String?> save({required String url, String? fileName}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw ApiException('This file cannot be downloaded.');
    }

    var name = _sanitize((fileName != null && fileName.trim().isNotEmpty) ? fileName : _nameFromUrl(url));
    try {
      final res = await Dio().get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes, followRedirects: true),
      );
      final data = res.data;
      if (data == null || data.isEmpty) {
        throw ApiException('The downloaded file was empty.');
      }

      var ext = _extensionOf(name);
      if (ext.isEmpty) {
        ext = _extensionOf(_nameFromUrl(url));
        if (ext.isNotEmpty) name = '$name.$ext';
      }

      final counts = await _readCounts();
      final countKey = name.toLowerCase();
      final used = counts[countKey] ?? 0;
      final base = _baseOf(name);
      final finalBase = used == 0 ? base : '$base ($used)';

      final mime = _mimeByExt[ext] ?? res.headers.value(Headers.contentTypeHeader) ?? 'application/octet-stream';
      final path = await FileSaver.instance.saveAs(
        name: finalBase,
        bytes: Uint8List.fromList(data),
        ext: ext,
        mimeType: MimeType.other,
        customMimeType: mime,
      );
      if (path != null && path.isNotEmpty) {
        counts[countKey] = used + 1;
        await _writeCounts(counts);
      }
      return path;
    } on DioException {
      throw ApiException('Download failed. Check your connection and try again.');
    }
  }
}
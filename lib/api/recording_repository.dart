import 'dart:io';
import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/recording_models.dart';

class RecordingRepository {
  RecordingRepository._(this.api);
  static final RecordingRepository instance = RecordingRepository._(ApiClient.instance);
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
          case 401:
            msg = 'Unauthorized, login required.';
          case 403:
            msg = 'You do not have permission to do that.';
          case 404:
            msg = 'Recording not found or it has expired.';
          case 409:
            msg = 'A recording is already in progress.';
          default:
            msg = 'Request failed ($status).';
        }
      }
      throw ApiException(msg, statusCode: status);
    }
  }

  dynamic _data(Response r) => r.data is Map ? r.data['data'] : null;
  Map<String, dynamic> _map(dynamic d) => Map<String, dynamic>.from(d as Map);

  Future<void> stop(String meetingCode) => _guard(() async {
        await _dio.post('/api/v1/recordings/stop', data: {'meetingCode': meetingCode});
      });

  Future<RecordingUploadTarget> uploadUrl(String meetingCode, String fileName) => _guard(() async {
        final r = await _dio.post('/api/v1/recordings/upload-url', data: {
          'meetingCode': meetingCode,
          'fileName': fileName,
        });
        final d = _map(_data(r));
        final upload = (d['uploadUrl'] ?? '').toString();
        final file = (d['fileUrl'] ?? '').toString();
        if (upload.isEmpty || file.isEmpty) {
          throw ApiException('The server did not return an upload location.');
        }
        return RecordingUploadTarget(uploadUrl: upload, fileUrl: file);
      });

  Future<void> putFile(
    String uploadUrl,
    File file, {
    String contentType = 'video/mp4',
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final length = await file.length();
    try {
      await Dio().put(
        uploadUrl,
        data: file.openRead(),
        cancelToken: cancelToken,
        options: Options(
          headers: {
            Headers.contentLengthHeader: length,
            Headers.contentTypeHeader: contentType,
          },
          sendTimeout: const Duration(minutes: 30),
          receiveTimeout: const Duration(minutes: 2),
        ),
        onSendProgress: (sent, total) {
          if (length > 0) onProgress?.call(sent / length);
        },
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) throw ApiException('Upload cancelled.');
      throw ApiException('Upload failed. Check your connection and try again.', statusCode: e.response?.statusCode);
    }
  }

  Future<MeetingRecording> complete(
    String recordingId, {
    required String fileUrl,
    required int durationSeconds,
    required int fileSizeBytes,
  }) =>
      _guard(() async {
        final r = await _dio.post('/api/v1/recordings/$recordingId/complete', data: {
          'fileUrl': fileUrl,
          'durationSeconds': durationSeconds,
          'fileSizeBytes': fileSizeBytes,
        });
        final d = _data(r);
        return d is Map
            ? MeetingRecording.fromJson(_map(d))
            : MeetingRecording(id: recordingId, meetingCode: '', status: RecordingStatus.completed);
      });

  Future<MeetingRecording> get(String recordingId) => _guard(() async {
        final r = await _dio.get('/api/v1/recordings/$recordingId');
        return MeetingRecording.fromJson(_map(_data(r)));
      });

  Future<RecordingPage> list(String meetingCode, {int page = 1, int limit = 20}) => _guard(() async {
        final r = await _dio.get(
          '/api/v1/meetings/$meetingCode/recordings',
          queryParameters: {'page': page, 'limit': limit.clamp(1, 50)},
        );
        final body = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
        final raw = body['data'];
        final items = (raw is List ? raw : const [])
            .whereType<Map>()
            .map((e) => MeetingRecording.fromJson(_map(e)))
            .toList();
        final pg = body['pagination'] is Map ? _map(body['pagination']) : <String, dynamic>{};
        return RecordingPage(
          items: items,
          page: int.tryParse('${pg['page'] ?? page}') ?? page,
          totalPages: int.tryParse('${pg['totalPages'] ?? 1}') ?? 1,
          total: int.tryParse('${pg['total'] ?? items.length}') ?? items.length,
        );
      });

  Future<RecordingSummary> summarize(String recordingId, {bool regenerate = false}) => _guard(() async {
        final r = await _dio.post(
          '/api/v1/recordings/$recordingId/summarize',
          data: {'regenerate': regenerate},
          options: Options(receiveTimeout: const Duration(minutes: 3)),
        );
        return RecordingSummary.fromJson(_map(_data(r)));
      });

  Future<void> delete(String recordingId) => _guard(() async {
        await _dio.delete('/api/v1/recordings/$recordingId');
      });
}
import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/document_models.dart';

class DocumentRepository {
  DocumentRepository._();
  static final DocumentRepository instance = DocumentRepository._();

  Dio get _dio => ApiClient.instance.dio;

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
          case 403:
            msg = 'You do not have permission to open this document.';
          case 404:
            msg = 'Document not found.';
          default:
            msg = 'Request failed ($status).';
        }
      }
      throw ApiException(msg, statusCode: status);
    }
  }

  dynamic _data(Response r) => r.data is Map ? r.data['data'] : null;

  Future<List<DocumentSummary>> list({
    String? organizationId,
    String? teamId,
    String? projectId,
    String? meetingId,
  }) =>
      _guard(() async {
        final r = await _dio.get('/api/documents', queryParameters: {
          if (organizationId != null) 'organizationId': organizationId,
          if (teamId != null) 'teamId': teamId,
          if (projectId != null) 'projectId': projectId,
          if (meetingId != null) 'meetingId': meetingId,
        });
        return DocumentSummary.listFrom(_data(r));
      });

  Future<QuorumDoc> get(String id, {String? meetingCode}) => _guard(() async {
        final r = await _dio.get(
          '/api/documents/$id',
          queryParameters: {
            if (meetingCode != null && meetingCode.isNotEmpty) 'meetingCode': meetingCode,
          },
        );
        return QuorumDoc.fromJson(_data(r));
      });

  Future<QuorumDoc> create({
    required String title,
    required DocumentScope scope,
    String? organizationId,
    String? teamId,
    String? projectId,
    String? meetingId,
  }) =>
      _guard(() async {
        final r = await _dio.post('/api/documents', data: {
          'title': title,
          'scopeType': scope.value,
          if (organizationId != null) 'organizationId': organizationId,
          if (teamId != null) 'teamId': teamId,
          if (projectId != null) 'projectId': projectId,
          if (meetingId != null) 'meetingId': meetingId,
        });
        return QuorumDoc.fromJson(_data(r));
      });

  Future<void> rename(String id, String title) => _guard(() async {
        await _dio.patch('/api/documents/$id', data: {'title': title});
      });

  Future<void> saveContent(String id, dynamic content) => _guard(() async {
        await _dio.patch('/api/documents/$id', data: {'content': content});
      });

  Future<void> openInMeeting(String id, String meetingCode) => _guard(() async {
        await _dio.post('/api/documents/$id/open-in-meeting', data: {'meetingCode': meetingCode});
      });

  Future<String> ai(
    String id, {
    required DocumentAiAction action,
    required String selectedText,
    String? prompt,
  }) =>
      _guard(() async {
        final r = await _dio.post(
          '/api/documents/$id/ai',
          data: {
            'action': action.value,
            'selectedText': selectedText,
            if (prompt != null && prompt.isNotEmpty) 'prompt': prompt,
          },
          options: Options(
            receiveTimeout: const Duration(seconds: 90),
            sendTimeout: const Duration(seconds: 30),
          ),
        );
        final data = _data(r);
        final completion = data is Map ? data['completion'] : null;
        if (completion == null || completion.toString().trim().isEmpty) {
          throw ApiException('The AI returned an empty response.');
        }
        return completion.toString();
      });
}
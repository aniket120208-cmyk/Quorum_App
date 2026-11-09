import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/ai_model.dart';

class AiService {
  AiService._();
  static final AiService instance = AiService._();
  static const _base = '/api/ai';
  Dio get _dio => ApiClient.instance.dio;

  Options get _slow => Options(
        receiveTimeout: const Duration(seconds: 90),
        sendTimeout: const Duration(seconds: 30),
      );

  Map<String, dynamic> _body(dynamic data) {
    if (data is Map && data['data'] is Map) {
      return Map<String, dynamic>.from(data['data']);
    }
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  ApiException _toException(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    String? msg;
    if (data is Map) {
      msg = (data['message'] ?? data['error'])?.toString();
    }

    if (status == 429) {
      final reset = int.tryParse(e.response?.headers.value('x-ratelimit-reset') ?? '');
      var wait = '';
      if (reset != null) {
        final secs = reset - DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (secs > 0) wait = ' Try again in ${secs}s.';
      }
      return ApiException('Too many requests.$wait', statusCode: 429);
    }
    if (status == 502) {
      return ApiException(
        'The AI service is temporarily unavailable. Please retry.',
        statusCode: 502,
      );
    }
    if (status == 413) {
      return ApiException(
        msg ?? 'One of the files is too large. Files can be 10 MB at most.',
        statusCode: 413,
      );
    }
    if (status == 403) {
      return ApiException(
        msg ?? 'You do not have access to this workspace.',
        statusCode: 403,
      );
    }
    if (status == 404) {
      return ApiException(msg ?? 'That item was not found.', statusCode: 404);
    }
    if (e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return ApiException('The AI took too long to respond. Try again.');
    }
    if (status == null) {
      return ApiException('Cannot reach the server. Try again.');
    }
    return ApiException(msg ?? 'Request failed ($status).', statusCode: status);
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  AiMeta? _meta(Map<String, dynamic> b) => b['metadata'] is Map ? AiMeta.fromJson(Map<String, dynamic>.from(b['metadata'])) : null;

  AiProject? _project(Map<String, dynamic> b) => b['project'] is Map ? AiProject.fromJson(Map<String, dynamic>.from(b['project'])) : null;

  static const Map<String, String> _mimeByExt = {
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'csv': 'text/csv',
    'json': 'application/json',
    'html': 'text/html',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'bmp': 'image/bmp',
  };

  String _mimeFor(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
    return _mimeByExt[ext] ?? 'application/octet-stream';
  }

  List<AiAttachment> _attachments(Map<String, dynamic> b) => (b['attachments'] is List ? b['attachments'] as List : const [])
      .whereType<Map>()
      .map((e) => AiAttachment.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  Future<AiResult> chat(
    String prompt, {
    String? context,
    List<AiPickedFile> files = const [],
  }) =>
      _guard(() async {
        final hasContext = context != null && context.trim().isNotEmpty;
        final Object data;
        if (files.isEmpty) {
          data = {
            'prompt': prompt,
            if (hasContext) 'context': context,
          };
        } else {
          final form = FormData();
          if (prompt.trim().isNotEmpty) form.fields.add(MapEntry('prompt', prompt.trim()));
          if (hasContext) form.fields.add(MapEntry('context', context!));
          for (final f in files.take(aiMaxFiles)) {
            form.files.add(MapEntry(
              'files',
              await MultipartFile.fromFile(
                f.path,
                filename: f.name,
                contentType: DioMediaType.parse(_mimeFor(f.name)),
              ),
            ));
          }
          data = form;
        }
        final r = await _dio.post(
          '$_base/chat',
          data: data,
          options: files.isEmpty
              ? _slow
              : Options(
                  receiveTimeout: const Duration(seconds: 120),
                  sendTimeout: const Duration(seconds: 90),
                ),
        );
        final b = _body(r.data);
        return AiResult(
          answer: (b['answer'] ?? '').toString(),
          meta: _meta(b),
          attachments: _attachments(b),
        );
      });

  Future<AiResult> search(String query, {int limit = 15}) => _guard(() async {
        final r = await _dio.post(
          '$_base/search',
          data: {'query': query, 'limit': limit},
          options: _slow,
        );
        final b = _body(r.data);
        final sources = (b['sources'] is List ? b['sources'] as List : const [])
            .map((e) => AiSource.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        return AiResult(
          answer: (b['answer'] ?? '').toString(),
          sources: sources,
          meta: _meta(b),
        );
      });

  Future<AiResult> projectAssistance(
    String prompt,
    AiScope scope,
    String scopeId,
  ) =>
      _guard(() async {
        final r = await _dio.post(
          '$_base/project-assistance',
          data: {'prompt': prompt, scope.key: scopeId},
          options: _slow,
        );
        final b = _body(r.data);
        return AiResult(
          answer: (b['answer'] ?? '').toString(),
          project: _project(b),
          meta: _meta(b),
        );
      });

  Future<AiResult> quickReplies({
    required String mode,
    required String tone,
    required String message,
  }) =>
      _guard(() async {
        final r = await _dio.post(
          '$_base/quick-replies',
          data: {'mode': mode, 'tone': tone, 'message': message},
          options: _slow,
        );
        final b = _body(r.data);
        final suggestions =
            (b['suggestions'] is List ? b['suggestions'] as List : const [])
                .map((e) => e.toString())
                .toList();
        return AiResult(
          suggestions: suggestions,
          target: b['targetContext']?.toString(),
          disclaimer: b['disclaimer']?.toString(),
          meta: _meta(b),
        );
      });

  Future<AiResult> projectUpdate(
    String timeframe,
    AiScope scope,
    String scopeId,
  ) =>
      _guard(() async {
        final r = await _dio.post(
          '$_base/project-update',
          data: {'timeframe': timeframe, scope.key: scopeId},
          options: _slow,
        );
        final b = _body(r.data);
        final f = b['retrievedFacts'] is Map
            ? Map<String, dynamic>.from(b['retrievedFacts'])
            : <String, dynamic>{};
        int n(String k) => int.tryParse((f[k] ?? 0).toString()) ?? 0;
        return AiResult(
          answer: (b['statusUpdate'] ?? '').toString(),
          project: _project(b),
          disclaimer: b['disclaimer']?.toString(),
          note: b['activitySource']?.toString(),
          facts: {
            'Members': n('membersCount'),
            'Discussions analyzed': n('discussionsAnalyzed'),
            'Teams recorded': n('teamsRecorded'),
          },
          meta: _meta(b),
        );
      });

  Future<AiHistoryPage> history({
    int limit = 20,
    String? cursor,
    String? actionType,
  }) =>
      _guard(() async {
        final r = await _dio.get('$_base/history', queryParameters: {
          'limit': limit,
          if (cursor != null) 'cursor': cursor,
          if (actionType != null) 'actionType': actionType,
        });
        final b = _body(r.data);
        final items =
            (b['interactions'] is List ? b['interactions'] as List : const [])
                .map((e) =>
                    AiInteraction.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList();
        return AiHistoryPage(
          items: items,
          nextCursor: b['nextCursor']?.toString(),
          hasMore: b['hasMore'] == true,
        );
      });

  Future<void> deleteHistoryItem(String id) => _guard(() async {
        await _dio.delete('$_base/history/$id');
      });

  Future<void> clearHistory() => _guard(() async {
        await _dio.delete('$_base/history');
      });
}
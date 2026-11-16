import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/quorumbot_models.dart';

class UltronService {
  UltronService._();
  static final UltronService instance = UltronService._();
  static const _base = '/api/ai/workflows';
  Dio get _dio => ApiClient.instance.dio;

  Options get _slow => Options(
        receiveTimeout: const Duration(seconds: 90),
        sendTimeout: const Duration(seconds: 30),
      );

  Map<String, dynamic> _data(dynamic body) {
    if (body is Map && body['data'] is Map) return Map<String, dynamic>.from(body['data']);
    if (body is Map) return Map<String, dynamic>.from(body);
    return <String, dynamic>{};
  }

  ApiException _toException(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    String? msg;
    if (data is Map) msg = (data['message'] ?? data['error'])?.toString();
    if (status == 429) return ApiException('Too many requests. Give me a moment.', statusCode: 429);
    if (status == 409) {
      return ApiException(msg ?? 'This plan is already executing.', statusCode: 409);
    }
    if (status == 502) {
      return ApiException('The AI service is temporarily unavailable. Please retry.', statusCode: 502);
    }
    if (e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.sendTimeout) {
      return ApiException('That took too long. Try again.');
    }
    if (status == null) return ApiException('Cannot reach the server. Try again.');
    return ApiException(msg ?? 'Request failed ($status).', statusCode: status);
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<UltronPlan> plan(String prompt, {String? organizationId}) => _guard(() async {
        final r = await _dio.post(
          '$_base/plan',
          data: {
            'prompt': prompt,
            if (organizationId != null && organizationId.isNotEmpty) 'organizationId': organizationId,
            'autoExecute': false,
          },
          options: _slow,
        );
        return UltronPlan.fromJson(_data(r.data));
      });

  Future<UltronOutcome> run(String prompt, {String? organizationId}) => _guard(() async {
        final r = await _dio.post(
          '$_base/plan',
          data: {
            'prompt': prompt,
            if (organizationId != null && organizationId.isNotEmpty) 'organizationId': organizationId,
            'autoExecute': true,
          },
          options: _slow,
        );
        final d = _data(r.data);
        final planMap = d['plan'] is Map ? Map<String, dynamic>.from(d['plan']) : d;
        final plan = UltronPlan.fromJson(planMap);
        Map<String, dynamic>? execMap;
        if (d['execution'] is Map) {
          execMap = Map<String, dynamic>.from(d['execution']);
        } else if (d['results'] is List && (d['results'] as List).isNotEmpty) {
          execMap = d;
        }
        if (execMap == null) return UltronOutcome(plan, null);
        final id = (execMap['planId'] ?? '').toString();
        return UltronOutcome(
          plan,
          UltronExecution.fromJson({...execMap, 'planId': id.isEmpty ? plan.planId : id}),
        );
      });

  Future<UltronExecution> execute(String planId) => _guard(() async {
        final r = await _dio.post(
          '$_base/execute',
          data: {'planId': planId},
          options: _slow,
        );
        return UltronExecution.fromJson(_data(r.data));
      });
}
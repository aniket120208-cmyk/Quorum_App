import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/calendar_models.dart';

class CalendarRepository {
  CalendarRepository._();

  static final CalendarRepository instance = CalendarRepository._();

  Dio get _dio => ApiClient.instance.dio;

  ApiException _toApiException(DioException e) {
    final data = e.response?.data;
    final status = e.response?.statusCode;
    String message;
    if (data is Map && data['message'] != null) {
      message = data['message'].toString();
    } else if (status == 401) {
      message = 'Unauthorized, login required';
    } else if (status == 404) {
      message = 'Calendar event not found';
    } else {
      message = 'Cannot reach the server. Try again.';
    }
    return ApiException(message, statusCode: status);
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  dynamic _unwrap(dynamic response) {
    if (response is Map && response['success'] == false) {
      throw ApiException(
        response['message']?.toString() ?? 'Calendar request failed',
      );
    }

    if (response is Map && response.containsKey('data')) {
      return response['data'];
    }

    return response;
  }

  List<CalendarEvent> _parseEvents(dynamic response) {
    final data = _unwrap(response);

    Iterable<dynamic>? list;
    if (data is List) {
      list = data;
    } else if (data is Map) {
      final nested = data['events'] ?? data['items'];
      if (nested is List) list = nested;
    }

    final events = (list ?? const <dynamic>[])
        .whereType<Map>()
        .map((e) => CalendarEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    events.sort(CalendarEvent.compare);
    return events;
  }

  CalendarEvent _parseEvent(dynamic response) {
    final data = _unwrap(response);

    if (data is Map) {
      final event = data['event'] ?? data;
      if (event is Map) {
        return CalendarEvent.fromJson(Map<String, dynamic>.from(event));
      }
    }

    throw ApiException('Unexpected calendar event response');
  }

  Future<List<CalendarEvent>> getMonth({
    required int year,
    required int month,
  }) {
    return _guard(() async {
      final response = await _dio.get(
        '/api/calendar/month',
        data: <String, dynamic>{},
        queryParameters: {'year': year, 'month': month},
      );
      return _parseEvents(response.data);
    });
  }

  Future<List<CalendarEvent>> getDate(DateTime date) {
    final formattedDate =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    return _guard(() async {
      final response = await _dio.get(
        '/api/calendar/date',
        data: <String, dynamic>{},
        queryParameters: {'date': formattedDate},
      );
      return _parseEvents(response.data);
    });
  }

  Future<List<CalendarEvent>> getDay(
    DateTime date, {
    List<CalendarEvent> known = const [],
  }) async {
    final local = known.where((event) => event.occursOn(date)).toList();

    try {
      final remote = await getDate(date);
      final merged = <String, CalendarEvent>{
        for (final event in local) event.id: event,
      };
      for (final event in remote) {
        if (event.occursOn(date)) merged[event.id] = event;
      }
      final result = merged.values.toList()..sort(CalendarEvent.compare);
      return result;
    } on ApiException {
      if (known.isNotEmpty) return local;
      rethrow;
    }
  }

  Future<List<CalendarEvent>> getUpcoming({int limit = 5}) {
    return _guard(() async {
      final response = await _dio.get(
        '/api/calendar/upcoming',
        data: <String, dynamic>{},
        queryParameters: {'limit': limit},
      );
      return _parseEvents(response.data);
    });
  }

  Future<CalendarEvent> getById(String id) {
    return _guard(() async {
      final response = await _dio.get('/api/calendar/$id', data: <String, dynamic>{});
      return _parseEvent(response.data);
    });
  }

  Future<CalendarEvent> create(CalendarEvent event) {
    return _guard(() async {
      final response = await _dio.post('/api/calendar', data: event.toJson());
      return _parseEvent(response.data);
    });
  }

  Future<CalendarEvent> update(String id, Map<String, dynamic> changes) {
    return _guard(() async {
      final response = await _dio.patch('/api/calendar/$id', data: changes);
      return _parseEvent(response.data);
    });
  }

  Future<void> delete(String id) {
    return _guard(() async {
      await _dio.delete('/api/calendar/$id', data: <String, dynamic>{});
    });
  }
}
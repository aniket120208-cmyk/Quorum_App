import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/jira_models.dart';

class JiraRepository {
  JiraRepository._(this.api);
  static final JiraRepository instance = JiraRepository._(ApiClient.instance);
  final ApiClient api;

  Dio get _dio => api.dio;

  String? _accountId;

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
          case 400:
            msg = 'Request failed. Make sure your Jira account is connected.';
          case 401:
            msg = 'Unauthorized, login required.';
          case 403:
            msg = 'You do not have permission to do that.';
          case 404:
            msg = 'Jira endpoint not found: ${e.requestOptions.method} ${e.requestOptions.path}';
          default:
            msg = 'Request failed ($status).';
        }
      }
      throw ApiException(msg, statusCode: status);
    }
  }

  dynamic _data(Response r) => r.data is Map ? r.data['data'] : null;
  Map<String, dynamic> _map(dynamic d) => d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};

  List<JiraTicket> _tickets(dynamic d) {
    if (d is! List) return const [];
    return d.map((e) => JiraTicket.fromJson(_map(e))).toList();
  }

  Future<String> authorizeUrl() => _guard(() async {
        final r = await _dio.get('/api/integrations/jira/oauth/authorize-url');
        return _map(_data(r))['authorizeUrl']?.toString() ?? '';
      });

  Future<JiraUserStatus> userStatus() => _guard(() async {
        final r = await _dio.get('/api/integrations/jira/oauth/status');
        return JiraUserStatus.fromJson(_map(_data(r)));
      });

  Future<void> disconnectUser() => _guard(() async {
        await _dio.post('/api/integrations/jira/disconnect', data: <String, dynamic>{});
        _accountId = null;
      });

  Future<List<JiraTicket>> myTickets() => _guard(() async {
        final r = await _dio.get('/api/integrations/jira/tickets/my');
        return _tickets(_data(r));
      });

  Future<String?> myAccountId({bool refresh = false}) async {
    if (_accountId != null && !refresh) return _accountId;
    final tickets = await myTickets();
    for (final ticket in tickets) {
      final id = ticket.assigneeAccountId;
      if (id != null && id.isNotEmpty) {
        _accountId = id;
        break;
      }
    }
    return _accountId;
  }

  Future<OrgJiraStatus> orgStatus(String orgId) => _guard(() async {
        final r = await _dio.get('/api/organizations/$orgId/jira');
        return OrgJiraStatus.fromJson(_map(_data(r)));
      });

  Future<OrgJiraStatus> setupOrg(String orgId, String projectKey) => _guard(() async {
        final r = await _dio.post('/api/organizations/$orgId/jira/setup', data: {'projectKey': projectKey});
        return OrgJiraStatus.fromJson({..._map(_data(r)), 'isConnected': true});
      });

  Future<void> disconnectOrg(String orgId) => _guard(() async {
        await _dio.delete('/api/organizations/$orgId/jira', data: <String, dynamic>{});
      });

  Future<List<JiraTicket>> teamTickets(String orgId, String teamId) => _guard(() async {
        final r = await _dio.get('/api/organizations/$orgId/teams/$teamId/jira/tickets');
        return _tickets(_data(r));
      });

  Future<List<JiraAssignee>> assignees(String orgId, String teamId) => _guard(() async {
        final r = await _dio.get('/api/organizations/$orgId/teams/$teamId/jira/assignees');
        var d = _data(r);
        if (d is Map) d = d['assignees'] ?? d['members'] ?? d['users'];
        if (d is! List) return const <JiraAssignee>[];
        return d
            .map((e) => JiraAssignee.fromJson(_map(e)))
            .where((a) => a.accountId.isNotEmpty)
            .toList();
      });

  Future<JiraTicket> createTicket(
    String orgId,
    String teamId, {
    required String summary,
    String? description,
    required String issueType,
    required String priority,
    String? assigneeAccountId,
  }) =>
      _guard(() async {
        final r = await _dio.post('/api/organizations/$orgId/teams/$teamId/jira/tickets', data: {
          'summary': summary,
          if (description != null && description.isNotEmpty) 'description': description,
          'issueType': issueType,
          'priority': priority,
          if (assigneeAccountId != null && assigneeAccountId.isNotEmpty) 'assigneeAccountId': assigneeAccountId,
        });
        return JiraTicket.fromJson(_map(_data(r)));
      });

  Future<JiraTicket> ticketDetails(String orgId, String teamId, String key) => _guard(() async {
        final r = await _dio.get('/api/organizations/$orgId/teams/$teamId/jira/tickets/$key');
        return JiraTicket.fromJson(_map(_data(r)));
      });

  Future<String?> transition(String orgId, String teamId, String key, String status) => _guard(() async {
        final r = await _dio.patch(
          '/api/organizations/$orgId/teams/$teamId/jira/tickets/$key/status',
          data: {'status': status},
        );
        return _map(_data(r))['jiraStatus']?.toString();
      });
}
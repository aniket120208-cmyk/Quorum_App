import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/organization_models.dart';

class OrganizationRepository {
  OrganizationRepository._(this.api);
  static final OrganizationRepository instance = OrganizationRepository._(ApiClient.instance);
  final ApiClient api;

  Dio get _dio => api.dio;

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
            msg = 'You do not have permission to do that.';
          case 404:
            msg = 'Organization not found.';
          case 409:
            msg = 'This action has already been done.';
          case 410:
            msg = 'This invitation link has expired.';
          default:
            msg = 'Request failed ($status).';
        }
      }
      throw ApiException(msg, statusCode: status);
    }
  }

  dynamic _data(Response r) => r.data is Map ? r.data['data'] : null;
  Map<String, dynamic> _map(dynamic d) => Map<String, dynamic>.from(d as Map);

  List _list(dynamic d, String key) {
    if (d is List) return d;
    if (d is Map && d[key] is List) return d[key] as List;
    return const [];
  }

  Future<List<Organization>> organizations() => _guard(() async {
        final r = await _dio.get('/api/organizations');
        return _list(_data(r), 'organizations').map((e) => Organization.fromJson(_map(e))).toList();
      });

  Future<Organization> create({
    required String name,
    String? description,
    String? logo,
  }) =>
      _guard(() async {
        final r = await _dio.post('/api/organizations', data: {
          'name': name,
          if (description != null && description.isNotEmpty) 'description': description,
          if (logo != null && logo.isNotEmpty) 'logo': logo,
        });
        return Organization.fromJson(_map(_data(r)), fallbackRole: 'ORG_ADMIN');
      });

  Future<Organization> detail(String id, {required String role}) => _guard(() async {
        final r = await _dio.get('/api/organizations/$id');
        return Organization.fromJson(_map(_data(r)), fallbackRole: role);
      });

  Future<void> update(
    String id, {
    required String name,
    required String description,
    String? logo,
  }) =>
      _guard(() async {
        await _dio.patch('/api/organizations/$id', data: {
          'name': name,
          'description': description,
          if (logo != null && logo.isNotEmpty) 'logo': logo,
        });
      });

  Future<void> leave(String id) => _guard(() async {
        await _dio.post('/api/organizations/$id/leave', data: <String, dynamic>{});
      });

  Future<void> delete(String id) => _guard(() async {
        await _dio.delete('/api/organizations/$id');
      });

  Future<List<OrgMember>> members(String id) => _guard(() async {
        final r = await _dio.get('/api/organizations/$id/members');
        return _list(_data(r), 'members').map((e) => OrgMember.fromJson(_map(e))).toList();
      });

  Future<void> updateMemberRole(String id, String userId, String role) => _guard(() async {
        await _dio.patch('/api/organizations/$id/members/$userId', data: {'role': role});
      });

  Future<void> removeMember(String id, String userId) => _guard(() async {
        await _dio.delete('/api/organizations/$id/members/$userId');
      });

  Future<OrgInvite> createInvite(
    String id, {
    String? email,
    required String role,
    required int maxUses,
    required int expiresInDays,
  }) =>
      _guard(() async {
        final r = await _dio.post('/api/organizations/$id/invites', data: {
          if (email != null && email.isNotEmpty) 'email': email,
          'role': role,
          'maxUses': maxUses,
          'expiresInDays': expiresInDays,
        });
        return OrgInvite.fromJson(_map(_data(r)));
      });

  Future<InvitePreview> previewInvite(String token) => _guard(() async {
        final r = await _dio.get('/api/organizations/join/$token');
        return InvitePreview.fromJson(_map(_data(r)));
      });

  Future<String?> acceptInvite(String token) => _guard(() async {
        final r = await _dio.post('/api/organizations/join/$token');
        final d = _data(r);
        return d is Map ? d['organizationId']?.toString() : null;
      });

  Future<List<OrgTeam>> teams(String id) => _guard(() async {
        final r = await _dio.get('/api/organizations/$id/teams');
        return _list(_data(r), 'teams').map((e) => OrgTeam.fromJson(_map(e))).toList();
      });

  Future<void> createTeam(String id, {required String name, String? description}) =>
      _guard(() async {
        await _dio.post('/api/organizations/$id/teams', data: {
          'name': name,
          if (description != null && description.isNotEmpty) 'description': description,
        });
      });

  Future<void> addTeamMember(String id, String teamId, String userId) => _guard(() async {
        await _dio.post('/api/organizations/$id/teams/$teamId/members', data: {'userId': userId});
      });

  Future<void> removeTeamMember(String id, String teamId, String userId) => _guard(() async {
        await _dio.delete('/api/organizations/$id/teams/$teamId/members/$userId');
      });

  Future<TeamChatHistory> teamMessages(String id, String teamId) => _guard(() async {
        final r = await _dio.get('/api/organizations/$id/teams/$teamId/messages');
        return TeamChatHistory.fromJson(_map(_data(r)));
      });

  Future<TeamMessage> sendTeamMessage(
    String id,
    String teamId, {
    required String content,
    String? fileUrl,
    String? fileType,
    String? fileName,
    int? fileSize,
  }) =>
      _guard(() async {
        final r = await _dio.post('/api/organizations/$id/teams/$teamId/messages', data: {
          'content': content,
          if (fileUrl != null && fileUrl.isNotEmpty) 'fileUrl': fileUrl,
          if (fileUrl != null && fileUrl.isNotEmpty && fileType != null) 'fileType': fileType,
          if (fileUrl != null && fileUrl.isNotEmpty && fileName != null) 'fileName': fileName,
          if (fileUrl != null && fileUrl.isNotEmpty && fileSize != null) 'fileSize': fileSize,
        });
        return TeamMessage.fromJson(_map(_data(r)));
      });

  Future<void> deleteTeamMessage(String id, String teamId, String messageId) => _guard(() async {
        await _dio.delete(
          '/api/organizations/$id/teams/$teamId/messages/$messageId',
          data: <String, dynamic>{},
        );
      });

  Future<bool> toggleTeamMessagePin(String id, String teamId, String messageId) => _guard(() async {
        final r = await _dio.post(
          '/api/organizations/$id/teams/$teamId/messages/$messageId/pin',
          data: <String, dynamic>{},
        );
        final d = _data(r);
        return d is Map && d['isPinned'] == true;
      });

  Future<List<OrgMember>> teamMembers(String id, String teamId) => _guard(() async {
        final r = await _dio.get('/api/organizations/$id/teams/$teamId');
        return _list(_data(r), 'members').map((e) => OrgMember.fromJson(_map(e))).toList();
      });

  Future<List<TeamTask>> teamTasks(String id, String teamId) => _guard(() async {
        final r = await _dio.get('/api/organizations/$id/teams/$teamId/tasks');
        return _list(_data(r), 'tasks').map((e) => TeamTask.fromJson(_map(e))).toList();
      });

  Future<TeamTask> createTask(
    String id,
    String teamId, {
    required String title,
    String? description,
    DateTime? dueDate,
    required String assigneeId,
  }) =>
      _guard(() async {
        final r = await _dio.post('/api/organizations/$id/teams/$teamId/tasks', data: {
          'title': title,
          if (description != null && description.isNotEmpty) 'description': description,
          if (dueDate != null) 'dueDate': dueDate.toUtc().toIso8601String(),
          'assigneeId': assigneeId,
        });
        return TeamTask.fromJson(_map(_data(r)));
      });

  Future<TaskStatus> updateTaskStatus(
    String id,
    String teamId,
    String taskId,
    TaskStatus status,
  ) =>
      _guard(() async {
        final r = await _dio.patch(
          '/api/organizations/$id/teams/$teamId/tasks/$taskId/status',
          data: {'status': status.apiValue},
        );
        final d = _data(r);
        return d is Map ? TaskStatus.fromString(d['status']?.toString()) : status;
      });

  Future<List<TeamTask>> myTasks(String id) => _guard(() async {
        final r = await _dio.get('/api/organizations/$id/tasks/my');
        return _list(_data(r), 'tasks').map((e) => TeamTask.fromJson(_map(e))).toList();
      });
}
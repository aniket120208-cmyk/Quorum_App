import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/project_models.dart';

class ProjectRepository {
  ProjectRepository._(this.api);
  static final ProjectRepository instance = ProjectRepository._(ApiClient.instance);
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
          case 400:
            msg = 'That request was not valid.';
          case 401:
            msg = 'Unauthorized, login required.';
          case 403:
            msg = 'You do not have permission to do that.';
          case 404:
            msg = 'Not found.';
          case 409:
            msg = 'This action has already been done.';
          case 410:
            msg = 'This invitation has expired.';
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

  String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

  Future<List<Project>> projects() => _guard(() async {
        final r = await _dio.get('/api/projects');
        return _list(_data(r), 'projects').map((e) => Project.fromJson(_map(e))).toList();
      });

  Future<Project> createProject(
    String organizationId, {
    required String name,
    String? description,
    DateTime? dueDate,
  }) =>
      _guard(() async {
        final r = await _dio.post('/api/projects/organization/$organizationId', data: {
          'name': name,
          if (description != null && description.isNotEmpty) 'description': description,
          if (dueDate != null) 'dueDate': _iso(dueDate),
        });
        return Project.fromJson(_map(_data(r)));
      });

  Future<Project> project(String id) => _guard(() async {
        final r = await _dio.get('/api/projects/$id');
        return Project.fromJson(_map(_data(r)));
      });

  Future<Project> updateProject(
    String id, {
    String? name,
    String? description,
    String? status,
    DateTime? dueDate,
  }) =>
      _guard(() async {
        final r = await _dio.patch('/api/projects/$id', data: {
          if (name != null) 'name': name,
          if (description != null) 'description': description,
          if (status != null) 'status': status,
          if (dueDate != null) 'dueDate': _iso(dueDate),
        });
        final d = _data(r);
        return d is Map ? Project.fromJson(_map(d)) : project(id);
      });

  Future<void> deleteProject(String id) => _guard(() async {
        await _dio.delete('/api/projects/$id');
      });

  Future<ProjectInviteResult> invite(
    String projectId, {
    required String email,
    required ProjectRole role,
    double? hourlyRate,
    String? companyName,
  }) =>
      _guard(() async {
        final r = await _dio.post('/api/projects/$projectId/invites', data: {
          'email': email,
          'role': role.apiValue,
          if (hourlyRate != null) 'hourlyRate': hourlyRate,
          if (companyName != null && companyName.isNotEmpty) 'companyName': companyName,
        });
        return ProjectInviteResult.fromJson(_map(_data(r)));
      });

  Future<void> acceptInvite(String token) => _guard(() async {
        await _dio.post('/api/projects/accept-invite', data: {'token': token});
      });

  Future<void> updateMember(
    String projectId,
    String userId, {
    ProjectRole? role,
    double? hourlyRate,
    String? companyName,
  }) =>
      _guard(() async {
        await _dio.patch('/api/projects/$projectId/members/$userId', data: {
          if (role != null) 'role': role.apiValue,
          if (hourlyRate != null) 'hourlyRate': hourlyRate,
          if (companyName != null) 'companyName': companyName,
        });
      });

  Future<void> removeMember(String projectId, String userId) => _guard(() async {
        await _dio.delete('/api/projects/$projectId/members/$userId');
      });

  Future<List<ProjectTask>> tasks(String projectId, {ProjectTaskStatus? status, String? assigneeId}) =>
      _guard(() async {
        final r = await _dio.get('/api/projects/$projectId/tasks', queryParameters: {
          if (status != null) 'status': status.apiValue,
          if (assigneeId != null) 'assigneeId': assigneeId,
        });
        return _list(_data(r), 'tasks').map((e) => ProjectTask.fromJson(_map(e), projectId: projectId)).toList();
      });

  Future<ProjectTask> createTask(
    String projectId, {
    required String title,
    String? description,
    required ProjectTaskPriority priority,
    required String assigneeId,
    required DateTime dueDate,
  }) =>
      _guard(() async {
        final r = await _dio.post('/api/projects/$projectId/tasks', data: {
          'title': title,
          if (description != null && description.isNotEmpty) 'description': description,
          'priority': priority.apiValue,
          'assigneeId': assigneeId,
          'dueDate': _iso(dueDate),
        });
        return ProjectTask.fromJson(_map(_data(r)), projectId: projectId);
      });

  Future<ProjectTask> updateTask(
    String projectId,
    String taskId, {
    String? title,
    String? description,
    ProjectTaskPriority? priority,
    String? assigneeId,
    DateTime? dueDate,
  }) =>
      _guard(() async {
        final r = await _dio.patch('/api/projects/$projectId/tasks/$taskId', data: {
          if (title != null) 'title': title,
          if (description != null) 'description': description,
          if (priority != null) 'priority': priority.apiValue,
          if (assigneeId != null) 'assigneeId': assigneeId,
          if (dueDate != null) 'dueDate': _iso(dueDate),
        });
        return ProjectTask.fromJson(_map(_data(r)), projectId: projectId);
      });

  Future<ProjectTask> updateTaskStatus(String projectId, String taskId, ProjectTaskStatus status) =>
      _guard(() async {
        final r = await _dio.patch(
          '/api/projects/$projectId/tasks/$taskId/status',
          data: {'status': status.apiValue},
        );
        return ProjectTask.fromJson(_map(_data(r)), projectId: projectId);
      });

  Future<ProjectTask> submitDeliverable(
    String projectId,
    String taskId, {
    required String url,
    String? note,
  }) =>
      _guard(() async {
        final r = await _dio.post('/api/projects/$projectId/tasks/$taskId/deliverable', data: {
          'deliverableUrl': url,
          if (note != null && note.isNotEmpty) 'deliverableNote': note,
        });
        return ProjectTask.fromJson(_map(_data(r)), projectId: projectId);
      });

  Future<ProjectTask> reviewDeliverable(
    String projectId,
    String taskId, {
    required bool approved,
    String? feedback,
    String? fileUrl,
  }) =>
      _guard(() async {
        final text = (feedback ?? '').trim();
        final combined = fileUrl == null || fileUrl.isEmpty
            ? text
            : '${text.isEmpty ? 'Please see the attached file.' : text}\n\nAttachment: $fileUrl';
        final r = await _dio.post('/api/projects/$projectId/tasks/$taskId/review', data: {
          'approved': approved,
          if (combined.isNotEmpty) 'feedback': combined,
          if (fileUrl != null && fileUrl.isNotEmpty) 'feedbackFileUrl': fileUrl,
        });
        return ProjectTask.fromJson(_map(_data(r)), projectId: projectId);
      });

  Future<List<ProjectResource>> resources(String projectId) => _guard(() async {
        final r = await _dio.get('/api/projects/$projectId/resources');
        return _list(_data(r), 'resources').map((e) => ProjectResource.fromJson(_map(e))).toList();
      });

  Future<ProjectResource> addResource(
    String projectId, {
    required String title,
    required String fileUrl,
    String? fileName,
    String? fileType,
    int? fileSize,
  }) =>
      _guard(() async {
        final r = await _dio.post('/api/projects/$projectId/resources', data: {
          'title': title,
          'fileUrl': fileUrl,
          if (fileName != null) 'fileName': fileName,
          if (fileType != null) 'fileType': fileType,
          if (fileSize != null) 'fileSize': fileSize,
        });
        return ProjectResource.fromJson(_map(_data(r)));
      });

  Future<void> deleteResource(String projectId, String resourceId) => _guard(() async {
        await _dio.delete('/api/projects/$projectId/resources/$resourceId');
      });
}
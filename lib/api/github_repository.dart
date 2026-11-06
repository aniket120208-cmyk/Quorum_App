import 'package:dio/dio.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/github_models.dart';

class GithubRepository {
  GithubRepository._(this.api);
  static final GithubRepository instance = GithubRepository._(ApiClient.instance);
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
            msg = 'Request failed. Make sure your GitHub account is connected.';
          case 401:
            msg = 'Unauthorized, login required.';
          case 403:
            msg = 'You do not have permission to do that.';
          case 404:
            msg = 'GitHub endpoint not found: ${e.requestOptions.method} ${e.requestOptions.path}';
          case 422:
            msg = 'GitHub rejected the request. Check the details and try again.';
          default:
            msg = 'Request failed ($status).';
        }
      }
      throw ApiException(msg, statusCode: status);
    }
  }

  dynamic _data(Response r) => r.data is Map ? r.data['data'] : r.data;

  Map<String, dynamic> _map(dynamic d) => d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};

  List<Map<String, dynamic>> _rows(dynamic d, List<String> keys) {
    dynamic list = d;
    if (list is Map) {
      for (final key in keys) {
        if (list[key] is List) {
          list = list[key];
          break;
        }
      }
    }
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<GithubStatus> status() => _guard(() async {
        final r = await _dio.get('/api/github/status');
        return GithubStatus.fromJson(_map(_data(r)));
      });

  Future<String> authorizeUrl() => _guard(() async {
        final r = await _dio.get('/api/github/oauth/authorize-url');
        return _map(_data(r))['authorizeUrl']?.toString() ?? '';
      });

  Future<void> disconnect() => _guard(() async {
        await _dio.post('/api/github/disconnect', data: <String, dynamic>{});
      });

  Future<List<GithubRepoOption>> userRepos({int page = 1, int perPage = 30}) => _guard(() async {
        final r = await _dio.get('/api/github/user/repos', queryParameters: {'page': page, 'per_page': perPage});
        return _rows(_data(r), ['repos', 'repositories', 'items']).map(GithubRepoOption.fromJson).toList();
      });

  Future<TeamRepoStatus> teamRepo(String teamId) => _guard(() async {
        final r = await _dio.get('/api/github/teams/$teamId/repo');
        return TeamRepoStatus.fromJson(_map(_data(r)));
      });

  Future<LinkedRepo> linkRepo(String teamId, String repoFullName) => _guard(() async {
        final r = await _dio.post('/api/github/teams/$teamId/repo', data: {'repoFullName': repoFullName});
        final d = _map(_data(r));
        return LinkedRepo.fromJson({...d, 'repoFullName': d['repoFullName'] ?? repoFullName});
      });

  Future<void> unlinkRepo(String teamId, String repoFullName) => _guard(() async {
        await _dio.delete('/api/github/teams/$teamId/repo', data: {'repoFullName': repoFullName});
      });

  Future<List<GithubIssue>> issues(String teamId, {String state = 'open', int page = 1, int perPage = 20}) =>
      _guard(() async {
        final r = await _dio.get(
          '/api/github/teams/$teamId/issues',
          queryParameters: {'state': state, 'page': page, 'per_page': perPage},
        );
        return _rows(_data(r), ['issues', 'items'])
            .where((e) => !e.containsKey('pull_request'))
            .map(GithubIssue.fromJson)
            .toList();
      });

  Future<GithubIssue> createIssue(
    String teamId, {
    required String title,
    String? body,
    List<String> assignees = const [],
    List<String> labels = const [],
  }) =>
      _guard(() async {
        final r = await _dio.post('/api/github/teams/$teamId/issues', data: {
          'title': title,
          if (body != null && body.isNotEmpty) 'body': body,
          if (assignees.isNotEmpty) 'assignees': assignees,
          if (labels.isNotEmpty) 'labels': labels,
        });
        return GithubIssue.fromJson(_map(_data(r)));
      });

  Future<void> setIssueState(String teamId, int issueNumber, String state) => _guard(() async {
        await _dio.patch('/api/github/teams/$teamId/issues/$issueNumber', data: {'state': state});
      });

  Future<List<GithubPull>> pulls(String teamId, {String state = 'open', int page = 1, int perPage = 20}) =>
      _guard(() async {
        final r = await _dio.get(
          '/api/github/teams/$teamId/pulls',
          queryParameters: {'state': state, 'page': page, 'per_page': perPage},
        );
        return _rows(_data(r), ['pulls', 'pullRequests', 'items']).map(GithubPull.fromJson).toList();
      });

  Future<List<GithubCommit>> commits(String teamId, {String? branch, int page = 1, int perPage = 20}) =>
      _guard(() async {
        final r = await _dio.get('/api/github/teams/$teamId/commits', queryParameters: {
          'page': page,
          'per_page': perPage,
          if (branch != null && branch.isNotEmpty) 'branch': branch,
        });
        return _rows(_data(r), ['commits', 'items']).map(GithubCommit.fromJson).toList();
      });

  Future<List<String>> branches(String teamId) => _guard(() async {
        final r = await _dio.get('/api/github/teams/$teamId/branches');
        return _rows(_data(r), ['branches', 'items'])
            .map((e) => (e['name'] ?? '').toString())
            .where((name) => name.isNotEmpty)
            .toList();
      });

  Future<List<GithubUser>> collaborators(String teamId) => _guard(() async {
        final r = await _dio.get('/api/github/teams/$teamId/collaborators');
        return _rows(_data(r), ['collaborators', 'users', 'items'])
            .map(GithubUser.fromJson)
            .where((u) => u.login.isNotEmpty)
            .toList();
      });
}
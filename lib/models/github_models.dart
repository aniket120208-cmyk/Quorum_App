DateTime? _date(dynamic v) => DateTime.tryParse((v ?? '').toString())?.toLocal();

String? _str(dynamic v) {
  final s = v?.toString();
  if (s == null || s.isEmpty || s == 'null') return null;
  return s;
}

int _int(dynamic v) => int.tryParse((v ?? 0).toString()) ?? 0;

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<T> _mapList<T>(dynamic v, T Function(Map<String, dynamic>) build) {
  if (v is! List) return <T>[];
  return v.whereType<Map>().map((e) => build(Map<String, dynamic>.from(e))).toList();
}

class GithubStatus {
  final bool connected;
  final String? username;
  final String? email;
  final DateTime? connectedAt;
  final DateTime? expiresAt;

  const GithubStatus({
    required this.connected,
    this.username,
    this.email,
    this.connectedAt,
    this.expiresAt,
  });

  factory GithubStatus.fromJson(Map<String, dynamic> j) => GithubStatus(
        connected: j['connected'] == true,
        username: _str(j['githubUsername']),
        email: _str(j['githubEmail']),
        connectedAt: _date(j['connectedAt']),
        expiresAt: _date(j['expiresAt']),
      );
}

class GithubUser {
  final String login;
  final String? avatarUrl;

  const GithubUser({required this.login, this.avatarUrl});

  factory GithubUser.fromJson(Map<String, dynamic> j) => GithubUser(
        login: (j['login'] ?? '').toString(),
        avatarUrl: _str(j['avatar_url'] ?? j['avatarUrl']),
      );

  static GithubUser? maybe(dynamic v) => v is Map ? GithubUser.fromJson(Map<String, dynamic>.from(v)) : null;
}

class GithubLabel {
  final String name;
  final String? color;

  const GithubLabel({required this.name, this.color});

  factory GithubLabel.fromJson(Map<String, dynamic> j) => GithubLabel(
        name: (j['name'] ?? '').toString(),
        color: _str(j['color']),
      );
}

class GithubRepoOption {
  final String id;
  final String name;
  final String fullName;
  final bool isPrivate;
  final String? defaultBranch;

  const GithubRepoOption({
    required this.id,
    required this.name,
    required this.fullName,
    required this.isPrivate,
    this.defaultBranch,
  });

  factory GithubRepoOption.fromJson(Map<String, dynamic> j) {
    final full = (j['full_name'] ?? j['fullName'] ?? '').toString();
    return GithubRepoOption(
      id: (j['id'] ?? full).toString(),
      name: (j['name'] ?? (full.contains('/') ? full.split('/').last : full)).toString(),
      fullName: full,
      isPrivate: j['private'] == true || j['isPrivate'] == true,
      defaultBranch: _str(j['default_branch'] ?? j['defaultBranch']),
    );
  }
}

class LinkedRepo {
  final String fullName;
  final String? defaultBranch;
  final bool isPrivate;
  final String? linkedByName;
  final String? linkedByEmail;

  const LinkedRepo({
    required this.fullName,
    this.defaultBranch,
    this.isPrivate = false,
    this.linkedByName,
    this.linkedByEmail,
  });

  String get name => fullName.contains('/') ? fullName.split('/').last : fullName;

  factory LinkedRepo.fromJson(Map<String, dynamic> j) {
    final by = _map(j['linkedBy']);
    return LinkedRepo(
      fullName: (j['repoFullName'] ?? j['fullName'] ?? '').toString(),
      defaultBranch: _str(j['defaultBranch']),
      isPrivate: j['isPrivate'] == true,
      linkedByName: _str(by['name']),
      linkedByEmail: _str(by['email']),
    );
  }
}

class TeamRepoStatus {
  final bool linked;
  final LinkedRepo? repository;

  const TeamRepoStatus({required this.linked, this.repository});

  factory TeamRepoStatus.fromJson(Map<String, dynamic> j) {
    final repo = j['repository'];
    final parsed = repo is Map ? LinkedRepo.fromJson(Map<String, dynamic>.from(repo)) : null;
    final hasRepo = parsed != null && parsed.fullName.isNotEmpty;
    return TeamRepoStatus(linked: (j['linked'] == true) && hasRepo, repository: hasRepo ? parsed : null);
  }
}

class GithubIssue {
  final String id;
  final int number;
  final String title;
  final String? body;
  final String state;
  final GithubUser? user;
  final List<GithubUser> assignees;
  final List<GithubLabel> labels;
  final int comments;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? htmlUrl;

  const GithubIssue({
    required this.id,
    required this.number,
    required this.title,
    this.body,
    required this.state,
    this.user,
    this.assignees = const [],
    this.labels = const [],
    this.comments = 0,
    this.createdAt,
    this.updatedAt,
    this.htmlUrl,
  });

  bool get isOpen => state.toLowerCase() == 'open';

  GithubIssue copyWith({String? state}) => GithubIssue(
        id: id,
        number: number,
        title: title,
        body: body,
        state: state ?? this.state,
        user: user,
        assignees: assignees,
        labels: labels,
        comments: comments,
        createdAt: createdAt,
        updatedAt: updatedAt,
        htmlUrl: htmlUrl,
      );

  factory GithubIssue.fromJson(Map<String, dynamic> j) => GithubIssue(
        id: (j['id'] ?? j['number'] ?? '').toString(),
        number: _int(j['number']),
        title: (j['title'] ?? '').toString(),
        body: _str(j['body']),
        state: (j['state'] ?? 'open').toString(),
        user: GithubUser.maybe(j['user']),
        assignees: _mapList(j['assignees'], GithubUser.fromJson),
        labels: (j['labels'] is List)
            ? (j['labels'] as List)
                .map((e) => e is Map
                    ? GithubLabel.fromJson(Map<String, dynamic>.from(e))
                    : GithubLabel(name: e.toString()))
                .toList()
            : <GithubLabel>[],
        comments: _int(j['comments']),
        createdAt: _date(j['created_at'] ?? j['createdAt']),
        updatedAt: _date(j['updated_at'] ?? j['updatedAt']),
        htmlUrl: _str(j['html_url'] ?? j['htmlUrl']),
      );
}

class GithubPull {
  final int number;
  final String title;
  final String state;
  final bool draft;
  final bool merged;
  final GithubUser? user;
  final String? headRef;
  final String? baseRef;
  final List<GithubUser> reviewers;
  final DateTime? createdAt;
  final String? htmlUrl;

  const GithubPull({
    required this.number,
    required this.title,
    required this.state,
    this.draft = false,
    this.merged = false,
    this.user,
    this.headRef,
    this.baseRef,
    this.reviewers = const [],
    this.createdAt,
    this.htmlUrl,
  });

  bool get isOpen => state.toLowerCase() == 'open';

  factory GithubPull.fromJson(Map<String, dynamic> j) => GithubPull(
        number: _int(j['number']),
        title: (j['title'] ?? '').toString(),
        state: (j['state'] ?? 'open').toString(),
        draft: j['draft'] == true,
        merged: j['merged'] == true || _str(j['merged_at']) != null,
        user: GithubUser.maybe(j['user']),
        headRef: _str(_map(j['head'])['ref']),
        baseRef: _str(_map(j['base'])['ref']),
        reviewers: _mapList(j['requested_reviewers'], GithubUser.fromJson),
        createdAt: _date(j['created_at'] ?? j['createdAt']),
        htmlUrl: _str(j['html_url'] ?? j['htmlUrl']),
      );
}

class GithubCommit {
  final String sha;
  final String message;
  final String? authorName;
  final DateTime? date;
  final GithubUser? author;
  final String? htmlUrl;

  const GithubCommit({
    required this.sha,
    required this.message,
    this.authorName,
    this.date,
    this.author,
    this.htmlUrl,
  });

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;

  String get title {
    final line = message.split('\n').first.trim();
    return line.isEmpty ? '(no message)' : line;
  }

  String get displayAuthor {
    final login = author?.login;
    if (login != null && login.isNotEmpty) return login;
    return authorName ?? 'Unknown';
  }

  factory GithubCommit.fromJson(Map<String, dynamic> j) {
    final commit = _map(j['commit']);
    final commitAuthor = _map(commit['author']);
    return GithubCommit(
      sha: (j['sha'] ?? '').toString(),
      message: (commit['message'] ?? '').toString(),
      authorName: _str(commitAuthor['name']),
      date: _date(commitAuthor['date']),
      author: GithubUser.maybe(j['author']),
      htmlUrl: _str(j['html_url'] ?? j['htmlUrl']),
    );
  }
}
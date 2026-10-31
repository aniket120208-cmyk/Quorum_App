DateTime? _date(dynamic v) => DateTime.tryParse((v ?? '').toString())?.toLocal();

String? _str(dynamic v) {
  final s = v?.toString();
  if (s == null || s.isEmpty || s == 'null') return null;
  return s;
}

enum JiraColumn {
  todo('To Do', 'new'),
  inProgress('In Progress', 'indeterminate'),
  done('Done', 'done');

  const JiraColumn(this.label, this.category);
  final String label;
  final String category;
}

class JiraTicket {
  final String id;
  final String teamId;
  final String? jiraIssueId;
  final String jiraKey;
  final String jiraSummary;
  final String jiraStatus;
  final String? statusCategory;
  final String? priority;
  final String? assigneeAccountId;
  final String? reporterAccountId;
  final DateTime? lastSyncedAt;
  final DateTime? createdAt;

  const JiraTicket({
    required this.id,
    required this.teamId,
    this.jiraIssueId,
    required this.jiraKey,
    required this.jiraSummary,
    required this.jiraStatus,
    this.statusCategory,
    this.priority,
    this.assigneeAccountId,
    this.reporterAccountId,
    this.lastSyncedAt,
    this.createdAt,
  });

  JiraColumn get column {
    final status = jiraStatus.toLowerCase();
    final category = (statusCategory ?? '').toLowerCase();
    if (status == 'done' || category == 'done') return JiraColumn.done;
    if (status == 'in progress' || category == 'indeterminate') return JiraColumn.inProgress;
    return JiraColumn.todo;
  }

  JiraTicket copyWith({String? jiraStatus, String? statusCategory}) => JiraTicket(
        id: id,
        teamId: teamId,
        jiraIssueId: jiraIssueId,
        jiraKey: jiraKey,
        jiraSummary: jiraSummary,
        jiraStatus: jiraStatus ?? this.jiraStatus,
        statusCategory: statusCategory ?? this.statusCategory,
        priority: priority,
        assigneeAccountId: assigneeAccountId,
        reporterAccountId: reporterAccountId,
        lastSyncedAt: lastSyncedAt,
        createdAt: createdAt,
      );

  factory JiraTicket.fromJson(Map<String, dynamic> j) => JiraTicket(
        id: (j['id'] ?? '').toString(),
        teamId: (j['teamId'] ?? '').toString(),
        jiraIssueId: _str(j['jiraIssueId']),
        jiraKey: (j['jiraKey'] ?? '').toString(),
        jiraSummary: (j['jiraSummary'] ?? '').toString(),
        jiraStatus: (j['jiraStatus'] ?? '').toString(),
        statusCategory: _str(j['statusCategory']),
        priority: _str(j['priority']),
        assigneeAccountId: _str(j['assigneeAccountId']),
        reporterAccountId: _str(j['reporterAccountId']),
        lastSyncedAt: _date(j['lastSyncedAt']),
        createdAt: _date(j['createdAt']),
      );
}

class JiraUserStatus {
  final bool isConnected;
  final String? jiraEmail;
  final String? jiraDisplayName;
  final String? siteUrl;

  const JiraUserStatus({
    required this.isConnected,
    this.jiraEmail,
    this.jiraDisplayName,
    this.siteUrl,
  });

  factory JiraUserStatus.fromJson(Map<String, dynamic> j) => JiraUserStatus(
        isConnected: j['isConnected'] == true,
        jiraEmail: _str(j['jiraEmail']),
        jiraDisplayName: _str(j['jiraDisplayName']),
        siteUrl: _str(j['siteUrl']),
      );
}

class OrgJiraStatus {
  final bool isConnected;
  final String? cloudId;
  final String? siteUrl;
  final String? projectKey;
  final bool isActive;

  const OrgJiraStatus({
    required this.isConnected,
    this.cloudId,
    this.siteUrl,
    this.projectKey,
    this.isActive = false,
  });

  factory OrgJiraStatus.fromJson(Map<String, dynamic> j) => OrgJiraStatus(
        isConnected: j['isConnected'] == true,
        cloudId: _str(j['cloudId']),
        siteUrl: _str(j['siteUrl']),
        projectKey: _str(j['projectKey']),
        isActive: j['isActive'] == true,
      );
}


class JiraAssignee {
  final String accountId;
  final String name;
  final String? email;
  final String? avatar;

  const JiraAssignee({
    required this.accountId,
    required this.name,
    this.email,
    this.avatar,
  });

  factory JiraAssignee.fromJson(Map<String, dynamic> j) {
    final user = j['user'] is Map ? Map<String, dynamic>.from(j['user'] as Map) : <String, dynamic>{};
    final id = _str(j['accountId'] ?? j['assigneeAccountId'] ?? user['accountId']) ?? '';
    final email = _str(j['email'] ?? j['jiraEmail'] ?? user['email']);
    final name = _str(j['displayName'] ?? j['name'] ?? j['jiraDisplayName'] ?? user['name']) ?? email ?? id;
    return JiraAssignee(
      accountId: id,
      name: name,
      email: email,
      avatar: _str(j['avatar'] ?? j['avatarUrl'] ?? user['avatar']),
    );
  }
}
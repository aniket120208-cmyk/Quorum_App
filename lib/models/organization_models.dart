DateTime? _date(dynamic v) => DateTime.tryParse((v ?? '').toString())?.toLocal();
int _int(dynamic v) => int.tryParse((v ?? 0).toString()) ?? 0;
String? _str(dynamic v) {
  final s = v?.toString();
  if (s == null || s.isEmpty || s == 'null') return null;
  return s;
}

Map<String, dynamic> _asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

bool orgIsAdmin(String role) => role == 'ORG_ADMIN';
bool orgCanInvite(String role) => role == 'ORG_ADMIN' || role == 'TEAM_HEAD';

String orgRoleLabel(String role) {
  switch (role) {
    case 'ORG_ADMIN':
      return 'Admin';
    case 'TEAM_HEAD':
      return 'Team Head';
    default:
      return 'Member';
  }
}

class Organization {
  final String id;
  final String name;
  final String? slug;
  final String? description;
  final String? logo;
  final String role;
  final int membersCount;
  final int teamsCount;
  final DateTime? createdAt;

  const Organization({
    required this.id,
    required this.name,
    this.slug,
    this.description,
    this.logo,
    required this.role,
    required this.membersCount,
    required this.teamsCount,
    this.createdAt,
  });

  Organization copyWith({String? role, int? membersCount, int? teamsCount}) => Organization(
        id: id,
        name: name,
        slug: slug,
        description: description,
        logo: logo,
        role: role ?? this.role,
        membersCount: membersCount ?? this.membersCount,
        teamsCount: teamsCount ?? this.teamsCount,
        createdAt: createdAt,
      );

  factory Organization.fromJson(Map<String, dynamic> raw, {String? fallbackRole}) {
    final j = raw['organization'] is Map ? _asMap(raw['organization']) : raw;
    final count = _asMap(j['_count']);
    return Organization(
      id: (j['id'] ?? j['organizationId'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      slug: _str(j['slug']),
      description: _str(j['description']),
      logo: _str(j['logo']),
      role: (j['role'] ?? j['userRole'] ?? raw['role'] ?? raw['userRole'] ?? fallbackRole ?? 'MEMBER')
          .toString()
          .toUpperCase(),
      membersCount: _int(j['membersCount'] ?? count['members']),
      teamsCount: _int(j['teamsCount'] ?? count['teams']),
      createdAt: _date(j['createdAt']),
    );
  }
}

class OrgMember {
  final String id;
  final String userId;
  final String name;
  final String? email;
  final String? avatar;
  final String role;
  final DateTime? joinedAt;

  const OrgMember({
    required this.id,
    required this.userId,
    required this.name,
    this.email,
    this.avatar,
    required this.role,
    this.joinedAt,
  });

  factory OrgMember.fromJson(Map<String, dynamic> j) {
    final u = _asMap(j['user']);
    return OrgMember(
      id: (j['id'] ?? '').toString(),
      userId: (u['id'] ?? j['userId'] ?? '').toString(),
      name: (u['name'] ?? j['name'] ?? '').toString(),
      email: _str(u['email'] ?? j['email']),
      avatar: _str(u['avatar'] ?? j['avatar']),
      role: (j['role'] ?? 'MEMBER').toString().toUpperCase(),
      joinedAt: _date(j['joinedAt']),
    );
  }
}

class OrgTeam {
  final String id;
  final String name;
  final String? description;
  final int membersCount;
  final DateTime? createdAt;

  const OrgTeam({
    required this.id,
    required this.name,
    this.description,
    required this.membersCount,
    this.createdAt,
  });

  OrgTeam copyWith({int? membersCount}) => OrgTeam(
        id: id,
        name: name,
        description: description,
        membersCount: membersCount ?? this.membersCount,
        createdAt: createdAt,
      );

  factory OrgTeam.fromJson(Map<String, dynamic> j) {
    final count = _asMap(j['_count']);
    return OrgTeam(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      description: _str(j['description']),
      membersCount: _int(j['membersCount'] ?? count['members']),
      createdAt: _date(j['createdAt']),
    );
  }
}

class OrgInvite {
  final String inviteId;
  final String token;
  final String url;
  final DateTime? expiresAt;

  const OrgInvite({
    required this.inviteId,
    required this.token,
    required this.url,
    this.expiresAt,
  });

  static const String _joinBase = 'https://newquorum.me/join/';
  factory OrgInvite.fromJson(Map<String, dynamic> raw) {
    final j = raw['invite'] is Map ? {...raw, ...Map<String, dynamic>.from(raw['invite'])} : raw;
    final token = (j['token'] ?? '').toString();
    var url = (j['inviteUrl'] ?? j['url'] ?? j['link'] ?? '').toString();
    if (url.isEmpty && token.isNotEmpty) url = '$_joinBase$token';
    return OrgInvite(
      inviteId: (j['inviteId'] ?? j['id'] ?? '').toString(),
      token: token,
      url: url,
      expiresAt: _date(j['expiresAt']),
    );
  }
}

class InvitePreview {
  final String organizationId;
  final String organizationName;
  final String? organizationLogo;
  final int membersCount;
  final String role;
  final String? inviterName;

  const InvitePreview({
    required this.organizationId,
    required this.organizationName,
    this.organizationLogo,
    required this.membersCount,
    required this.role,
    this.inviterName,
  });

  factory InvitePreview.fromJson(Map<String, dynamic> j) {
    final o = _asMap(j['organization']);
    return InvitePreview(
      organizationId: (o['id'] ?? '').toString(),
      organizationName: (o['name'] ?? '').toString(),
      organizationLogo: _str(o['logo']),
      membersCount: _int(o['membersCount']),
      role: (j['role'] ?? 'MEMBER').toString().toUpperCase(),
      inviterName: _str(j['inviterName']),
    );
  }
}

enum TeamMessageStatus { sent, uploading, sending, failed }

class TeamMessageSender {
  final String id;
  final String name;
  final String? email;
  final String? avatar;

  const TeamMessageSender({
    required this.id,
    required this.name,
    this.email,
    this.avatar,
  });

  factory TeamMessageSender.fromJson(Map<String, dynamic> j) => TeamMessageSender(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        email: _str(j['email']),
        avatar: _str(j['avatar']),
      );
}

class TeamMessage {
  final String id;
  final String conversationId;
  final String? senderId;
  final String content;
  final bool isPinned;
  final String? fileUrl;
  final String? fileType;
  final String? fileName;
  final int? fileSize;
  final DateTime createdAt;
  final TeamMessageSender? sender;
  final TeamMessageStatus status;
  final String? localPath;
  final double uploadProgress;

  const TeamMessage({
    required this.id,
    required this.conversationId,
    this.senderId,
    required this.content,
    this.isPinned = false,
    this.fileUrl,
    this.fileType,
    this.fileName,
    this.fileSize,
    required this.createdAt,
    this.sender,
    this.status = TeamMessageStatus.sent,
    this.localPath,
    this.uploadProgress = 0,
  });

  bool get isSystem => senderId == null || sender == null;
  bool get hasAttachment => (fileUrl != null && fileUrl!.isNotEmpty) || localPath != null;
  bool get isImage => (fileType ?? '').toLowerCase().startsWith('image');
  bool get isPending => status != TeamMessageStatus.sent;

  TeamMessage copyWith({
    bool? isPinned,
    String? fileUrl,
    String? fileType,
    TeamMessageStatus? status,
    double? uploadProgress,
  }) =>
      TeamMessage(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        content: content,
        isPinned: isPinned ?? this.isPinned,
        fileUrl: fileUrl ?? this.fileUrl,
        fileType: fileType ?? this.fileType,
        fileName: fileName,
        fileSize: fileSize,
        createdAt: createdAt,
        sender: sender,
        status: status ?? this.status,
        localPath: localPath,
        uploadProgress: uploadProgress ?? this.uploadProgress,
      );

  factory TeamMessage.fromJson(Map<String, dynamic> j, {String? fallbackConversationId}) {
    final rawSender = j['sender'];
    final sender = rawSender is Map ? TeamMessageSender.fromJson(Map<String, dynamic>.from(rawSender)) : null;
    return TeamMessage(
      id: (j['id'] ?? '').toString(),
      conversationId: (j['conversationId'] ?? fallbackConversationId ?? '').toString(),
      senderId: _str(j['senderId']),
      content: (j['content'] ?? '').toString(),
      isPinned: j['isPinned'] == true,
      fileUrl: _str(j['fileUrl']),
      fileType: _str(j['fileType']),
      fileName: _str(j['fileName']),
      fileSize: j['fileSize'] == null ? null : _int(j['fileSize']),
      createdAt: _date(j['createdAt']) ?? DateTime.now(),
      sender: sender,
    );
  }
}

class TeamChatHistory {
  final String conversationId;
  final List<TeamMessage> messages;
  const TeamChatHistory({required this.conversationId, required this.messages});

  factory TeamChatHistory.fromJson(Map<String, dynamic> j) {
    final conversationId = (j['conversationId'] ?? '').toString();
    final raw = j['messages'] is List ? j['messages'] as List : const [];
    final messages = raw
        .whereType<Map>()
        .map((e) => TeamMessage.fromJson(Map<String, dynamic>.from(e), fallbackConversationId: conversationId))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return TeamChatHistory(conversationId: conversationId, messages: messages);
  }
}

enum TaskStatus {
  todo('TODO', 'To Do'),
  inProgress('IN_PROGRESS', 'In Progress'),
  completed('COMPLETED', 'Completed');

  const TaskStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static TaskStatus fromString(String? value) {
    switch ((value ?? '').toUpperCase()) {
      case 'IN_PROGRESS':
        return TaskStatus.inProgress;
      case 'COMPLETED':
        return TaskStatus.completed;
      default:
        return TaskStatus.todo;
    }
  }
}

class TaskUser {
  final String id;
  final String name;
  final String? email;
  final String? avatar;
  const TaskUser({required this.id, required this.name, this.email, this.avatar});
  factory TaskUser.fromJson(Map<String, dynamic> j) => TaskUser(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        email: _str(j['email']),
        avatar: _str(j['avatar']),
      );
}

class TeamTask {
  final String id;
  final String teamId;
  final String? teamName;
  final String title;
  final String? description;
  final TaskStatus status;
  final DateTime? dueDate;
  final String assigneeId;
  final String createdById;
  final DateTime? createdAt;
  final TaskUser? assignee;
  final TaskUser? createdBy;

  const TeamTask({
    required this.id,
    required this.teamId,
    this.teamName,
    required this.title,
    this.description,
    required this.status,
    this.dueDate,
    required this.assigneeId,
    required this.createdById,
    this.createdAt,
    this.assignee,
    this.createdBy,
  });

  bool get isOverdue => status != TaskStatus.completed && dueDate != null && dueDate!.isBefore(DateTime.now());

  TeamTask copyWith({TaskStatus? status}) => TeamTask(
        id: id,
        teamId: teamId,
        teamName: teamName,
        title: title,
        description: description,
        status: status ?? this.status,
        dueDate: dueDate,
        assigneeId: assigneeId,
        createdById: createdById,
        createdAt: createdAt,
        assignee: assignee,
        createdBy: createdBy,
      );

  factory TeamTask.fromJson(Map<String, dynamic> j) {
    final team = _asMap(j['team']);
    final assignee = j['assignee'] is Map ? TaskUser.fromJson(_asMap(j['assignee'])) : null;
    final createdBy = j['createdBy'] is Map ? TaskUser.fromJson(_asMap(j['createdBy'])) : null;
    return TeamTask(
      id: (j['id'] ?? '').toString(),
      teamId: (j['teamId'] ?? team['id'] ?? '').toString(),
      teamName: _str(team['name']),
      title: (j['title'] ?? '').toString(),
      description: _str(j['description']),
      status: TaskStatus.fromString(j['status']?.toString()),
      dueDate: _date(j['dueDate']),
      assigneeId: (j['assigneeId'] ?? assignee?.id ?? '').toString(),
      createdById: (j['createdById'] ?? createdBy?.id ?? '').toString(),
      createdAt: _date(j['createdAt']),
      assignee: assignee,
      createdBy: createdBy,
    );
  }
}
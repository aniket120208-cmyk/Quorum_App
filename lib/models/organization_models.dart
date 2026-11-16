import 'package:quorum_app/api/current_user.dart';

DateTime? _date(dynamic v) => DateTime.tryParse((v ?? '').toString())?.toLocal();
int _int(dynamic v) => int.tryParse((v ?? 0).toString()) ?? 0;
String? _str(dynamic v) {
  final s = v?.toString();
  if (s == null || s.isEmpty || s == 'null') return null;
  return s;
}

Map<String, dynamic> _asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

bool orgIsOwner(String role) => role == 'OWNER';
bool orgIsAdmin(String role) => role == 'ORG_ADMIN' || role == 'OWNER';
bool orgCanInvite(String role) => orgIsAdmin(role);

String orgNormalizeRole(String? role) {
  switch ((role ?? '').toUpperCase()) {
    case 'OWNER':
      return 'OWNER';
    case 'ORG_ADMIN':
    case 'ADMIN':
      return 'ORG_ADMIN';
    default:
      return 'MEMBER';
  }
}

String? _teamRoleOf(dynamic v) {
  final raw = _str(v)?.toUpperCase();
  if (raw == null) return null;
  return raw == 'LEAD' || raw == 'TEAM_HEAD' || raw == 'HEAD' ? 'LEAD' : 'MEMBER';
}

String orgRoleLabel(String role) {
  switch (role) {
    case 'OWNER':
      return 'Owner';
    case 'ORG_ADMIN':
      return 'Admin';
    case 'LEAD':
      return 'Team head';
    default:
      return 'Member';
  }
}

String orgTeamRoleLabel(String role) => role == 'LEAD' ? 'Team head' : 'Member';

const List<String> orgTeamRoles = ['MEMBER', 'LEAD'];

String orgTeamDisplayRole(String orgRole, String? teamRole) {
  if (orgIsAdmin(orgRole)) return orgRole;
  return teamRole == 'LEAD' ? 'LEAD' : 'MEMBER';
}

int orgRoleRank(String role) {
  switch (role) {
    case 'OWNER':
      return 0;
    case 'ORG_ADMIN':
      return 1;
    default:
      return 2;
  }
}

List<String> orgInvitableRoles(String callerRole) =>
    orgIsAdmin(callerRole) ? const ['MEMBER', 'ORG_ADMIN'] : const ['MEMBER'];

enum OrgSearchScope { mine, all }

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
  final String? industry;
  final String? teamSize;
  final bool isMember;
  final DateTime? joinedAt;

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
    this.industry,
    this.teamSize,
    this.isMember = true,
    this.joinedAt,
  });

  Organization copyWith({
    String? role,
    int? membersCount,
    int? teamsCount,
    String? logo,
    bool clearLogo = false,
  }) =>
      Organization(
        id: id,
        name: name,
        slug: slug,
        description: description,
        logo: clearLogo ? null : (logo ?? this.logo),
        role: role ?? this.role,
        membersCount: membersCount ?? this.membersCount,
        teamsCount: teamsCount ?? this.teamsCount,
        createdAt: createdAt,
        industry: industry,
        teamSize: teamSize,
        isMember: isMember,
        joinedAt: joinedAt,
      );

  factory Organization.fromJson(Map<String, dynamic> raw, {String? fallbackRole}) {
    final j = raw['organization'] is Map ? _asMap(raw['organization']) : raw;
    final count = _asMap(j['_count']);
    final ownerId = _str(j['ownerId'] ?? j['createdById'] ?? _asMap(j['owner'])['id']);
    final owner = j['isOwner'] == true ||
        j['isOrgOwner'] == true ||
        raw['isOwner'] == true ||
        (ownerId != null && CurrentUser.isLoaded && ownerId == CurrentUser.id && j['isMember'] != false);
    return Organization(
      id: (j['id'] ?? j['organizationId'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      slug: _str(j['slug']),
      description: _str(j['description']),
      logo: _str(j['logo']),
      role: owner ? 'OWNER' : orgNormalizeRole((j['role'] ?? j['myRole'] ?? j['userRole'] ?? raw['role'] ?? raw['myRole'] ?? raw['userRole'] ?? fallbackRole ?? 'MEMBER')
          .toString()),
      membersCount: _int(j['membersCount'] ?? j['memberCount'] ?? count['members']),
      teamsCount: _int(j['teamsCount'] ?? count['teams']),
      createdAt: _date(j['createdAt']),
      industry: _str(j['industry']),
      teamSize: _str(j['teamSize']),
      isMember: j['isMember'] == null ? true : j['isMember'] == true,
      joinedAt: _date(j['joinedAt']),
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
  final bool isOwner;
  final String? teamRole;
  final DateTime? joinedAt;

  const OrgMember({
    required this.id,
    required this.userId,
    required this.name,
    this.email,
    this.avatar,
    required this.role,
    this.isOwner = false,
    this.teamRole,
    this.joinedAt,
  });

  bool get isTeamLead => teamRole == 'LEAD';
  String get teamDisplayRole => orgTeamDisplayRole(role, teamRole);

  factory OrgMember.fromJson(Map<String, dynamic> j) {
    final u = _asMap(j['user']);
    final rawRole = (j['organizationRole'] ?? j['role'] ?? 'MEMBER').toString().toUpperCase();
    final owner = j['isOwner'] == true || j['isOrgOwner'] == true || rawRole == 'OWNER';
    return OrgMember(
      id: (j['id'] ?? '').toString(),
      userId: (u['id'] ?? j['userId'] ?? '').toString(),
      name: (u['name'] ?? j['name'] ?? '').toString(),
      email: _str(u['email'] ?? j['email']),
      avatar: _str(u['avatar'] ?? j['avatar']),
      role: owner ? 'OWNER' : orgNormalizeRole(rawRole),
      isOwner: owner,
      teamRole: _teamRoleOf(j['teamRole']),
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
  final bool isMember;
  final String? avatar;

  const OrgTeam({
    required this.id,
    required this.name,
    this.avatar,
    this.description,
    required this.membersCount,
    this.createdAt,
    this.isMember = true,
  });

  OrgTeam copyWith({int? membersCount, bool? isMember}) => OrgTeam(
        id: id,
        name: name,
        avatar: avatar,
        description: description,
        membersCount: membersCount ?? this.membersCount,
        createdAt: createdAt,
        isMember: isMember ?? this.isMember,
      );

  factory OrgTeam.fromJson(Map<String, dynamic> j) {
    final count = _asMap(j['_count']);
    return OrgTeam(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      avatar: _str(j['avatar'] ?? j['avatarUrl'] ?? j['logo']),
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
  final DateTime? createdAt;
  final String? email;
  final String role;
  final String? teamId;
  final String? teamName;
  final String? teamRole;
  final int usedCount;
  final int maxUses;
  final bool isRevoked;
  final String? inviterName;

  const OrgInvite({
    required this.inviteId,
    required this.token,
    required this.url,
    this.expiresAt,
    this.createdAt,
    this.email,
    this.role = 'MEMBER',
    this.teamId,
    this.teamName,
    this.teamRole,
    this.usedCount = 0,
    this.maxUses = 1,
    this.isRevoked = false,
    this.inviterName,
  });

  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isExhausted => maxUses > 0 && usedCount >= maxUses;
  bool get isActive => !isRevoked && !isExpired && !isExhausted;

  String get statusLabel {
    if (isRevoked) return 'Revoked';
    if (isExpired) return 'Expired';
    if (isExhausted) return 'Fully used';
    return 'Active';
  }

  static const String _joinBase = 'https://app.newquorum.me/join/';
  factory OrgInvite.fromJson(Map<String, dynamic> raw) {
    final j = raw['invite'] is Map ? {...raw, ...Map<String, dynamic>.from(raw['invite'])} : raw;
    final token = (j['token'] ?? '').toString();
    var url = (j['inviteUrl'] ?? j['url'] ?? j['link'] ?? '').toString();
    if (url.isEmpty && token.isNotEmpty) url = '$_joinBase$token';
    final team = _asMap(j['team']);
    final inviter = _asMap(j['inviter']);
    return OrgInvite(
      inviteId: (j['inviteId'] ?? j['id'] ?? '').toString(),
      token: token,
      url: url,
      expiresAt: _date(j['expiresAt']),
      createdAt: _date(j['createdAt']),
      email: _str(j['email']),
      role: orgNormalizeRole((j['role'] ?? 'MEMBER').toString()),
      teamId: _str(j['teamId'] ?? team['id']),
      teamName: _str(team['name'] ?? j['teamName']),
      teamRole: _teamRoleOf(j['teamRole']),
      usedCount: _int(j['usedCount']),
      maxUses: j['maxUses'] == null ? 1 : _int(j['maxUses']),
      isRevoked: j['isRevoked'] == true,
      inviterName: _str(inviter['name']),
    );
  }
}

class InvitePreview {
  final String organizationId;
  final String organizationName;
  final String? organizationLogo;
  final String? organizationDescription;
  final int membersCount;
  final String role;
  final String? inviterName;
  final String? teamName;
  final String? teamRole;
  final String? restrictedEmail;
  final DateTime? expiresAt;

  const InvitePreview({
    required this.organizationId,
    required this.organizationName,
    this.organizationLogo,
    this.organizationDescription,
    required this.membersCount,
    required this.role,
    this.inviterName,
    this.teamName,
    this.teamRole,
    this.restrictedEmail,
    this.expiresAt,
  });

  factory InvitePreview.fromJson(Map<String, dynamic> j) {
    final o = _asMap(j['organization']);
    final inviter = _asMap(j['inviter']);
    return InvitePreview(
      organizationId: (o['id'] ?? '').toString(),
      organizationName: (o['name'] ?? '').toString(),
      organizationLogo: _str(o['logo']),
      organizationDescription: _str(o['description']),
      membersCount: _int(o['membersCount'] ?? o['memberCount']),
      role: orgNormalizeRole((j['role'] ?? 'MEMBER').toString()),
      inviterName: _str(inviter['name'] ?? j['inviterName']),
      teamName: _str(j['teamName']),
      teamRole: _teamRoleOf(j['teamRole']),
      restrictedEmail: _str(j['email']),
      expiresAt: _date(j['expiresAt']),
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
        avatar: _str(j['avatar'] ?? j['avatarUrl'] ?? j['profilePicture'] ?? j['profileImage'] ?? j['image']),
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
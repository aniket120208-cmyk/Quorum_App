DateTime? _date(dynamic v) => DateTime.tryParse((v ?? '').toString())?.toLocal();
int _int(dynamic v) => int.tryParse((v ?? 0).toString()) ?? 0;
double? _num(dynamic v) => v == null ? null : double.tryParse(v.toString());
String? _str(dynamic v) {
  final s = v?.toString();
  if (s == null || s.isEmpty || s == 'null') return null;
  return s;
}

Map<String, dynamic> _asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

enum ProjectRole {
  projectManager('PROJECT_MANAGER', 'Manager'),
  internalMember('INTERNAL_MEMBER', 'Manager'),
  freelancer('FREELANCER', 'Freelancer'),
  client('CLIENT', 'Client');

  const ProjectRole(this.apiValue, this.label);
  final String apiValue;
  final String label;

  bool get isExternal => this == ProjectRole.freelancer || this == ProjectRole.client;

  static const List<ProjectRole> selectable = [
    ProjectRole.projectManager,
    ProjectRole.client,
    ProjectRole.freelancer,
  ];

  static ProjectRole fromString(String? v) {
    switch ((v ?? '').toUpperCase()) {
      case 'PROJECT_MANAGER':
      case 'MANAGER':
        return ProjectRole.projectManager;
      case 'FREELANCER':
        return ProjectRole.freelancer;
      case 'CLIENT':
        return ProjectRole.client;
      default:
        return ProjectRole.internalMember;
    }
  }
}

enum ProjectTaskStatus {
  todo('TODO', 'To Do'),
  inProgress('IN_PROGRESS', 'In Progress'),
  inReview('IN_REVIEW', 'In Review'),
  completed('COMPLETED', 'Completed'),
  cancelled('CANCELLED', 'Cancelled');

  const ProjectTaskStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static ProjectTaskStatus fromString(String? v) {
    switch ((v ?? '').toUpperCase()) {
      case 'IN_PROGRESS':
        return ProjectTaskStatus.inProgress;
      case 'IN_REVIEW':
        return ProjectTaskStatus.inReview;
      case 'COMPLETED':
        return ProjectTaskStatus.completed;
      case 'CANCELLED':
        return ProjectTaskStatus.cancelled;
      default:
        return ProjectTaskStatus.todo;
    }
  }
}

enum ProjectTaskPriority {
  low('LOW', 'Low'),
  medium('MEDIUM', 'Medium'),
  high('HIGH', 'High'),
  urgent('URGENT', 'Urgent');

  const ProjectTaskPriority(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static ProjectTaskPriority fromString(String? v) {
    switch ((v ?? '').toUpperCase()) {
      case 'LOW':
        return ProjectTaskPriority.low;
      case 'HIGH':
        return ProjectTaskPriority.high;
      case 'URGENT':
        return ProjectTaskPriority.urgent;
      default:
        return ProjectTaskPriority.medium;
    }
  }
}

class ProjectUser {
  final String id;
  final String name;
  final String? email;
  final String? avatar;

  const ProjectUser({required this.id, required this.name, this.email, this.avatar});

  factory ProjectUser.fromJson(Map<String, dynamic> j) => ProjectUser(
        id: (j['id'] ?? j['_id'] ?? '').toString(),
        name: (j['name'] ?? j['username'] ?? 'Member').toString(),
        email: _str(j['email']),
        avatar: _str(j['avatar'] ?? j['avatarUrl']),
      );
}

class ProjectMember {
  final ProjectRole role;
  final double? hourlyRate;
  final String? companyName;
  final String? companyId;
  final ProjectUser user;

  const ProjectMember({
    required this.role,
    this.hourlyRate,
    this.companyName,
    this.companyId,
    required this.user,
  });

  factory ProjectMember.fromJson(Map<String, dynamic> j) {
    final user = j['user'] is Map ? _asMap(j['user']) : {'id': j['userId'], 'name': j['name']};
    return ProjectMember(
      role: ProjectRole.fromString(j['role']?.toString()),
      hourlyRate: _num(j['hourlyRate']),
      companyName: _str(j['companyName']),
      companyId: _str(j['companyId']),
      user: ProjectUser.fromJson(user),
    );
  }
}

class ProjectOrg {
  final String id;
  final String name;
  final String? logo;

  const ProjectOrg({required this.id, required this.name, this.logo});

  factory ProjectOrg.fromJson(Map<String, dynamic> j) => ProjectOrg(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        logo: _str(j['logo']),
      );
}

class Project {
  final String id;
  final String name;
  final String? description;
  final String status;
  final DateTime? dueDate;
  final ProjectOrg? organization;
  final String? conversationId;
  final String? conversationName;
  final List<ProjectMember> members;
  final int tasksCount;
  final int membersCount;

  const Project({
    required this.id,
    required this.name,
    this.description,
    required this.status,
    this.dueDate,
    this.organization,
    this.conversationId,
    this.conversationName,
    this.members = const [],
    this.tasksCount = 0,
    this.membersCount = 0,
  });

  ProjectMember? memberFor(String userId) {
    for (final m in members) {
      if (m.user.id == userId) return m;
    }
    return null;
  }

  Project copyWith({List<ProjectMember>? members}) => Project(
        id: id,
        name: name,
        description: description,
        status: status,
        dueDate: dueDate,
        organization: organization,
        conversationId: conversationId,
        conversationName: conversationName,
        members: members ?? this.members,
        tasksCount: tasksCount,
        membersCount: members?.length ?? membersCount,
      );

  factory Project.fromJson(Map<String, dynamic> j) {
    final count = _asMap(j['_count']);
    final members = j['members'] is List
        ? (j['members'] as List).whereType<Map>().map((e) => ProjectMember.fromJson(_asMap(e))).toList()
        : <ProjectMember>[];
    final conv = _asMap(j['conversation']);
    return Project(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      description: _str(j['description']),
      status: (j['status'] ?? 'ACTIVE').toString(),
      dueDate: _date(j['dueDate']),
      organization: j['organization'] is Map ? ProjectOrg.fromJson(_asMap(j['organization'])) : null,
      conversationId: _str(conv['id'] ?? j['conversationId']),
      conversationName: _str(conv['name']),
      members: members,
      tasksCount: _int(count['tasks']),
      membersCount: count.containsKey('members') ? _int(count['members']) : members.length,
    );
  }
}

class ProjectTask {
  final String id;
  final String projectId;
  final String title;
  final String? description;
  final ProjectTaskPriority priority;
  final ProjectTaskStatus status;
  final String? assigneeId;
  final ProjectUser? assignee;
  final DateTime? dueDate;
  final String? deliverableUrl;
  final String? deliverableNote;
  final String? reviewFeedback;
  final String? reviewFeedbackUrl;

  const ProjectTask({
    required this.id,
    required this.projectId,
    required this.title,
    this.description,
    required this.priority,
    required this.status,
    this.assigneeId,
    this.assignee,
    this.dueDate,
    this.deliverableUrl,
    this.deliverableNote,
    this.reviewFeedback,
    this.reviewFeedbackUrl,
  });

  bool get isOverdue =>
      status != ProjectTaskStatus.completed &&
      status != ProjectTaskStatus.cancelled &&
      dueDate != null &&
      dueDate!.isBefore(DateTime.now());

  factory ProjectTask.fromJson(Map<String, dynamic> j, {String projectId = ''}) {
    final assignee = j['assignee'] is Map ? ProjectUser.fromJson(_asMap(j['assignee'])) : null;
    var feedback = _str(j['reviewFeedback'] ?? j['feedback'] ?? j['deliverableFeedback']);
    var feedbackUrl = _str(j['reviewFeedbackUrl'] ?? j['feedbackFileUrl'] ?? j['feedbackUrl'] ?? j['reviewFileUrl']);
    if (feedback != null) {
      final match = RegExp(r'\n*Attachment: (https?://\S+)\s*$').firstMatch(feedback);
      if (match != null) {
        feedbackUrl ??= match.group(1);
        feedback = feedback.substring(0, match.start).trim();
        if (feedback.isEmpty) feedback = null;
      }
    }
    return ProjectTask(
      id: (j['id'] ?? '').toString(),
      projectId: (j['projectId'] ?? projectId).toString(),
      title: (j['title'] ?? '').toString(),
      description: _str(j['description']),
      priority: ProjectTaskPriority.fromString(j['priority']?.toString()),
      status: ProjectTaskStatus.fromString(j['status']?.toString()),
      assigneeId: _str(j['assigneeId']) ?? assignee?.id,
      assignee: assignee,
      dueDate: _date(j['dueDate']),
      deliverableUrl: _str(j['deliverableUrl']),
      deliverableNote: _str(j['deliverableNote']),
      reviewFeedback: feedback,
      reviewFeedbackUrl: feedbackUrl,
    );
  }
}

class ProjectResource {
  final String id;
  final String title;
  final String fileUrl;
  final String? fileName;
  final String? fileType;
  final int? fileSize;
  final String? uploadedById;
  final ProjectUser? uploadedBy;
  final DateTime? createdAt;

  const ProjectResource({
    required this.id,
    required this.title,
    required this.fileUrl,
    this.fileName,
    this.fileType,
    this.fileSize,
    this.uploadedById,
    this.uploadedBy,
    this.createdAt,
  });

  factory ProjectResource.fromJson(Map<String, dynamic> j) {
    final by = j['uploadedBy'] is Map
        ? _asMap(j['uploadedBy'])
        : j['user'] is Map
            ? _asMap(j['user'])
            : j['createdBy'] is Map
                ? _asMap(j['createdBy'])
                : null;
    return ProjectResource(
      id: (j['id'] ?? '').toString(),
      title: (j['title'] ?? j['fileName'] ?? 'File').toString(),
      fileUrl: (j['fileUrl'] ?? '').toString(),
      fileName: _str(j['fileName']),
      fileType: _str(j['fileType']),
      fileSize: j['fileSize'] == null ? null : _int(j['fileSize']),
      uploadedById: _str(j['uploadedById'] ?? j['userId'] ?? j['createdById'] ?? by?['id']),
      uploadedBy: by == null ? null : ProjectUser.fromJson(by),
      createdAt: _date(j['createdAt']),
    );
  }
}

class ProjectInviteResult {
  final String id;
  final String email;
  final String role;
  final String token;
  final DateTime? expiresAt;

  const ProjectInviteResult({
    required this.id,
    required this.email,
    required this.role,
    required this.token,
    this.expiresAt,
  });

  factory ProjectInviteResult.fromJson(Map<String, dynamic> j) => ProjectInviteResult(
        id: (j['id'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        role: (j['role'] ?? '').toString(),
        token: (j['token'] ?? '').toString(),
        expiresAt: _date(j['expiresAt']),
      );
}
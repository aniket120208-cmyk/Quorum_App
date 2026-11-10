import 'package:flutter/material.dart';

enum DocumentScope { personal, team, organization, project, meeting }

extension DocumentScopeX on DocumentScope {
  String get value => name.toUpperCase();

  String get label {
    switch (this) {
      case DocumentScope.personal:
        return 'Personal';
      case DocumentScope.team:
        return 'Team';
      case DocumentScope.organization:
        return 'Organization';
      case DocumentScope.project:
        return 'Project';
      case DocumentScope.meeting:
        return 'Meeting';
    }
  }

  static DocumentScope parse(dynamic raw) {
    final v = (raw ?? '').toString().toUpperCase();
    for (final s in DocumentScope.values) {
      if (s.value == v) return s;
    }
    return DocumentScope.personal;
  }
}

enum DocumentAccess { read, write, owner }

DocumentAccess? parseDocumentAccess(dynamic raw) {
  switch ((raw ?? '').toString().toUpperCase()) {
    case 'READ':
    case 'VIEW':
      return DocumentAccess.read;
    case 'WRITE':
    case 'EDIT':
      return DocumentAccess.write;
    case 'OWNER':
      return DocumentAccess.owner;
  }
  return null;
}

String? _idOrNull(dynamic raw) {
  final s = raw?.toString();
  if (s == null || s.isEmpty || s == 'null') return null;
  return s;
}

DateTime? _date(dynamic raw) => DateTime.tryParse((raw ?? '').toString())?.toLocal();

class DocumentPerson {
  final String id;
  final String name;
  final String? email;
  final String? avatar;

  const DocumentPerson({required this.id, required this.name, this.email, this.avatar});

  factory DocumentPerson.fromJson(dynamic raw) {
    final j = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final avatar = j['avatar']?.toString();
    return DocumentPerson(
      id: (j['id'] ?? j['userId'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      email: j['email']?.toString(),
      avatar: avatar == null || avatar.isEmpty ? null : avatar,
    );
  }
}

class DocumentCollaborator {
  final String id;
  final String userId;
  final DocumentAccess permission;
  final DocumentPerson user;

  const DocumentCollaborator({
    required this.id,
    required this.userId,
    required this.permission,
    required this.user,
  });

  factory DocumentCollaborator.fromJson(Map<String, dynamic> j) {
    final user = DocumentPerson.fromJson(j['user']);
    return DocumentCollaborator(
      id: (j['id'] ?? '').toString(),
      userId: (j['userId'] ?? user.id).toString(),
      permission: parseDocumentAccess(j['permission']) ?? DocumentAccess.read,
      user: user,
    );
  }
}

class EmbeddedWhiteboard {
  final String id;
  final String whiteboardId;
  final String name;

  const EmbeddedWhiteboard({required this.id, required this.whiteboardId, required this.name});

  factory EmbeddedWhiteboard.fromJson(Map<String, dynamic> j) {
    final board = j['whiteboard'] is Map ? Map<String, dynamic>.from(j['whiteboard']) : <String, dynamic>{};
    return EmbeddedWhiteboard(
      id: (j['id'] ?? '').toString(),
      whiteboardId: (j['whiteboardId'] ?? board['id'] ?? '').toString(),
      name: (board['name'] ?? 'Whiteboard').toString(),
    );
  }
}

List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) build) {
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((e) => build(Map<String, dynamic>.from(e))).toList();
}

class QuorumDoc {
  final String id;
  final String title;
  final dynamic content;
  final DocumentScope scopeType;
  final String? organizationId;
  final String? teamId;
  final String? projectId;
  final String? meetingId;
  final bool isArchived;
  final int version;
  final String createdById;
  final DocumentPerson createdBy;
  final List<DocumentCollaborator> collaborators;
  final List<EmbeddedWhiteboard> whiteboards;
  final DocumentAccess? userPermission;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const QuorumDoc({
    required this.id,
    required this.title,
    this.content,
    this.scopeType = DocumentScope.personal,
    this.organizationId,
    this.teamId,
    this.projectId,
    this.meetingId,
    this.isArchived = false,
    this.version = 0,
    this.createdById = '',
    this.createdBy = const DocumentPerson(id: '', name: ''),
    this.collaborators = const [],
    this.whiteboards = const [],
    this.userPermission,
    this.createdAt,
    this.updatedAt,
  });

  DocumentAccess accessFor(String myId) {
    final explicit = userPermission;
    if (explicit != null) return explicit;
    if (myId.isNotEmpty && (createdById == myId || createdBy.id == myId)) return DocumentAccess.owner;
    for (final c in collaborators) {
      if (c.userId == myId) return c.permission;
    }
    return DocumentAccess.read;
  }

  QuorumDoc copyWith({
    String? title,
    int? version,
    dynamic content,
    List<EmbeddedWhiteboard>? whiteboards,
  }) =>
      QuorumDoc(
        id: id,
        title: title ?? this.title,
        content: content ?? this.content,
        scopeType: scopeType,
        organizationId: organizationId,
        teamId: teamId,
        projectId: projectId,
        meetingId: meetingId,
        isArchived: isArchived,
        version: version ?? this.version,
        createdById: createdById,
        createdBy: createdBy,
        collaborators: collaborators,
        whiteboards: whiteboards ?? this.whiteboards,
        userPermission: userPermission,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  factory QuorumDoc.fromJson(dynamic raw) {
    final j = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final createdBy = DocumentPerson.fromJson(j['createdBy']);
    return QuorumDoc(
      id: (j['id'] ?? '').toString(),
      title: (j['title'] ?? 'Untitled').toString(),
      content: j['content'],
      scopeType: DocumentScopeX.parse(j['scopeType']),
      organizationId: j['organizationId']?.toString(),
      teamId: j['teamId']?.toString(),
      projectId: j['projectId']?.toString(),
      meetingId: j['meetingId']?.toString(),
      isArchived: j['isArchived'] == true,
      version: int.tryParse((j['version'] ?? 0).toString()) ?? 0,
      createdById: (j['createdById'] ?? createdBy.id).toString(),
      createdBy: createdBy,
      collaborators: _list(j['collaborators'], DocumentCollaborator.fromJson),
      whiteboards: _list(j['whiteboards'], EmbeddedWhiteboard.fromJson)
          .where((b) => b.whiteboardId.isNotEmpty)
          .toList(),
      userPermission: parseDocumentAccess(j['userPermission']),
      createdAt: _date(j['createdAt']),
      updatedAt: _date(j['updatedAt']),
    );
  }
}

class DocumentSummary {
  final String id;
  final String title;
  final DocumentScope scopeType;
  final int version;
  final bool isArchived;
  final DateTime? updatedAt;
  final DocumentPerson createdBy;
  final int collaboratorsCount;
  final String? organizationId;
  final String? teamId;

  const DocumentSummary({
    required this.id,
    required this.title,
    required this.scopeType,
    required this.version,
    required this.isArchived,
    required this.updatedAt,
    required this.createdBy,
    required this.collaboratorsCount,
    this.organizationId,
    this.teamId,
  });

  DocumentSummary copyWith({String? title}) => DocumentSummary(
        id: id,
        title: title ?? this.title,
        scopeType: scopeType,
        version: version,
        isArchived: isArchived,
        updatedAt: updatedAt,
        createdBy: createdBy,
        collaboratorsCount: collaboratorsCount,
        organizationId: organizationId,
        teamId: teamId,
      );

  factory DocumentSummary.fromJson(Map<String, dynamic> j) => DocumentSummary(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? 'Untitled').toString(),
        scopeType: DocumentScopeX.parse(j['scopeType']),
        version: int.tryParse((j['version'] ?? 0).toString()) ?? 0,
        isArchived: j['isArchived'] == true,
        updatedAt: _date(j['updatedAt']),
        createdBy: DocumentPerson.fromJson(j['createdBy']),
        collaboratorsCount: int.tryParse((j['collaboratorsCount'] ?? 0).toString()) ?? 0,
        organizationId: _idOrNull(j['organizationId']),
        teamId: _idOrNull(j['teamId']),
      );

  static List<DocumentSummary> listFrom(dynamic raw) {
    final list = raw is Map ? (raw['documents'] ?? raw['items'] ?? raw['data']) : raw;
    return _list(list, DocumentSummary.fromJson).where((d) => d.id.isNotEmpty).toList();
  }
}

class ActiveDocumentUser {
  final String userId;
  final String name;
  final String? email;
  final String? avatar;
  final String? socketId;

  const ActiveDocumentUser({
    required this.userId,
    required this.name,
    this.email,
    this.avatar,
    this.socketId,
  });

  static ActiveDocumentUser? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final id = (j['userId'] ?? j['id'] ?? '').toString();
    if (id.isEmpty) return null;
    final avatar = j['avatar']?.toString();
    return ActiveDocumentUser(
      userId: id,
      name: (j['name'] ?? '').toString(),
      email: j['email']?.toString(),
      avatar: avatar == null || avatar.isEmpty ? null : avatar,
      socketId: j['socketId']?.toString(),
    );
  }

  static List<ActiveDocumentUser> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map(tryParse).whereType<ActiveDocumentUser>().toList();
  }
}

class DocumentCursor {
  final String userId;
  final String name;
  final String? avatar;
  final int line;
  final int ch;
  final int? selectionStart;
  final int? selectionEnd;

  const DocumentCursor({
    required this.userId,
    required this.name,
    this.avatar,
    required this.line,
    required this.ch,
    this.selectionStart,
    this.selectionEnd,
  });

  bool get hasSelection => selectionStart != null && selectionEnd != null && selectionEnd! > selectionStart!;

  static DocumentCursor? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final user = j['user'] is Map ? Map<String, dynamic>.from(j['user']) : <String, dynamic>{};
    final cursor = j['cursor'] is Map ? Map<String, dynamic>.from(j['cursor']) : <String, dynamic>{};
    final id = (user['id'] ?? user['userId'] ?? j['userId'] ?? '').toString();
    if (id.isEmpty) return null;
    final line = int.tryParse((cursor['line'] ?? 0).toString()) ?? 0;
    final ch = int.tryParse((cursor['ch'] ?? 0).toString()) ?? 0;
    int? from;
    int? to;
    final sel = cursor['selection'];
    if (sel is Map) {
      from = int.tryParse((sel['start'] ?? sel['from'] ?? sel['anchor'] ?? '').toString());
      to = int.tryParse((sel['end'] ?? sel['to'] ?? sel['head'] ?? '').toString());
      if (from != null && to != null && to < from) {
        final t = from;
        from = to;
        to = t;
      }
    }
    final avatar = user['avatar']?.toString();
    return DocumentCursor(
      userId: id,
      name: (user['name'] ?? j['name'] ?? '').toString(),
      avatar: avatar == null || avatar.isEmpty ? null : avatar,
      line: line < 0 ? 0 : line,
      ch: ch < 0 ? 0 : ch,
      selectionStart: from,
      selectionEnd: to,
    );
  }
}

enum DocumentAiAction {
  actionItems('action_items', 'Action items', Icons.checklist_rounded),
  summarize('summarize', 'Summarize', Icons.short_text_rounded),
  rewrite('rewrite', 'Rewrite', Icons.edit_note_rounded),
  expand('expand', 'Expand', Icons.unfold_more_rounded),
  fixGrammar('fix_grammar', 'Fix grammar', Icons.spellcheck_rounded),
  custom('custom', 'Custom', Icons.auto_awesome_rounded);

  const DocumentAiAction(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;

  bool get replacesSelection => this == DocumentAiAction.rewrite || this == DocumentAiAction.expand || this == DocumentAiAction.fixGrammar;
}

class DocumentAiResult {
  final String text;
  final bool replaceSelection;
  const DocumentAiResult(this.text, {this.replaceSelection = false});
}
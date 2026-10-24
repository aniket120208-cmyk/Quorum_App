enum MessageStatus { uploading, uploadFailed, sending, sent, failed }

class ChatUser {
  final String id;
  final String name;
  final String? email;
  final String? avatarUrl;
  final String? role;

  const ChatUser({
    required this.id,
    required this.name,
    this.email,
    this.avatarUrl,
    this.role,
  });

  factory ChatUser.fromJson(Map<String, dynamic> j) => ChatUser(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        email: j['email']?.toString(),
        avatarUrl: (j['avatar'] ?? j['avatarUrl'])?.toString(),
        role: j['role']?.toString(),
      );
}

class ChatMessage {
  final String id;
  final String? clientMessageId;
  final String senderId;
  final String senderName;
  final String? senderEmail;
  final String text;
  final String? fileUrl;
  final String? fileType;
  final String? fileName;
  final String? localPath;
  final double? uploadProgress;
  final DateTime createdAt;
  final MessageStatus status;
  final bool isRead;
  final List<String> mentionedUserIds;
  final List<ChatUser> mentionedUsers;
  final bool isEdited;

  const ChatMessage({
    required this.id,
    this.clientMessageId,
    required this.senderId,
    required this.senderName,
    this.senderEmail,
    this.text = '',
    this.fileUrl,
    this.fileType,
    this.fileName,
    this.localPath,
    this.uploadProgress,
    required this.createdAt,
    this.status = MessageStatus.sent,
    this.isRead = false,
    this.mentionedUserIds = const [],
    this.mentionedUsers = const [],
    this.isEdited = false,
  });
  bool mentions(String userId) => userId.isNotEmpty && mentionedUserIds.contains(userId);
  bool get hasAttachment => fileUrl != null || localPath != null;

  String get previewText {
    if (text.isNotEmpty) return text;
    if (!hasAttachment) return '';
    switch (fileType) {
      case 'image':
        return '📷 Photo';
      case 'video':
        return '🎥 Video';
      case 'audio':
        return '🎵 Audio';
      default:
        return '📎 File';
    }
  }

  String get attachmentName {
    if (fileName != null && fileName!.isNotEmpty) return fileName!;
    final u = fileUrl;
    if (u == null) return 'File';
    final segments = Uri.tryParse(u)?.pathSegments;
    if (segments == null || segments.isEmpty) return 'File';
    return Uri.decodeComponent(segments.last);
  }

  ChatMessage copyWith({
    String? id,
    String? clientMessageId,
    String? senderId,
    String? senderName,
    String? senderEmail,
    String? text,
    String? fileUrl,
    String? fileType,
    String? fileName,
    String? localPath,
    double? uploadProgress,
    DateTime? createdAt,
    MessageStatus? status,
    bool? isRead,
    List<String>? mentionedUserIds,
    List<ChatUser>? mentionedUsers,
    bool? isEdited,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderEmail: senderEmail ?? this.senderEmail,
      text: text ?? this.text,
      fileUrl: fileUrl ?? this.fileUrl,
      fileType: fileType ?? this.fileType,
      fileName: fileName ?? this.fileName,
      localPath: localPath ?? this.localPath,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      isRead: isRead ?? this.isRead,
      mentionedUserIds: mentionedUserIds ?? this.mentionedUserIds,
      mentionedUsers: mentionedUsers ?? this.mentionedUsers,
      isEdited: isEdited ?? this.isEdited,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final users = j['mentionedUsers'] is List
        ? (j['mentionedUsers'] as List)
            .whereType<Map>()
            .map((e) => ChatUser.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <ChatUser>[];
    final ids = j['mentionedUserIds'] is List
        ? (j['mentionedUserIds'] as List).map((e) => e.toString()).toList()
        : users.map((u) => u.id).toList();
    return ChatMessage(
      id: j['id'].toString(),
      clientMessageId: j['clientMessageId']?.toString(),
      senderId: (j['senderId'] ?? j['sender']?['id'] ?? '').toString(),
      senderName: (j['sender']?['name'] ?? '').toString(),
      senderEmail: j['sender']?['email']?.toString(),
      text: (j['content'] ?? '').toString(),
      fileUrl: j['fileUrl']?.toString(),
      fileType: j['fileType']?.toString(),
      createdAt: DateTime.parse(j['createdAt'].toString()).toLocal(),
      mentionedUserIds: ids,
      mentionedUsers: users,
      isEdited: j['isEdited'] == true || j['editedAt'] != null,
    );
  }
}

class TeamConversations {
  static final Set<String> ids = {};
}

String cleanGroupName(String? raw) =>
    (raw ?? '').replaceAll(RegExp(r'[\s\u00A0\u200B-\u200D\u2060\uFEFF]+'), ' ').trim();

class Conversation {
  final String id;
  final bool isTeam;
  final String? directName;
  final String? directEmail;
  final String? groupTitle;
  final bool isGroup;
  final String? avatar;
  final String? adminId;
  final int unreadCount;
  final DateTime updatedAt;
  final ChatMessage? lastMessage;
  final List<ChatUser> members;

  const Conversation({
    required this.id,
    this.isTeam = false,
    this.directName,
    this.directEmail,
    this.groupTitle,
    this.isGroup = false,
    this.avatar,
    this.adminId,
    this.unreadCount = 0,
    required this.updatedAt,
    this.lastMessage,
    this.members = const [],
  });

  Conversation copyWith({
    int? unreadCount,
    DateTime? updatedAt,
    ChatMessage? lastMessage,
  }) =>
      Conversation(
        id: id,
        isTeam: isTeam,
        directName: directName,
        directEmail: directEmail,
        groupTitle: groupTitle,
        isGroup: isGroup,
        avatar: avatar,
        adminId: adminId,
        unreadCount: unreadCount ?? this.unreadCount,
        updatedAt: updatedAt ?? this.updatedAt,
        lastMessage: lastMessage ?? this.lastMessage,
        members: members,
      );

  String titleFor(String currentUserId) {
    if (isGroup) {
      final name = cleanGroupName(groupTitle);
      return name.isEmpty ? 'Unnamed Group' : name;
    }
    return directName ?? 'Direct Chat';
  }

  factory Conversation.fromJson(Map<String, dynamic> j, String myId) {
    final rawMembers = (j['participants'] ?? j['members'] ?? []) as List;
    final members = rawMembers.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final u = m['user'] is Map
          ? Map<String, dynamic>.from(m['user'])
          : Map<String, dynamic>.from(m);
      if (m['role'] != null) u['role'] = m['role'];
      return ChatUser.fromJson(u);
    }).toList();

    final typeName = (j['type'] ?? '').toString().toLowerCase();
    final isTeam = typeName.contains('team') ||
        typeName.contains('org') ||
        j['teamId'] != null ||
        j['team'] is Map ||
        j['organizationId'] != null ||
        j['orgId'] != null ||
        TeamConversations.ids.contains(j['id'].toString());

    final isGroup = j['isGroup'] == true || j['type']?.toString().toLowerCase() == 'group';

    String? directName;
    String? directEmail;
    if (!isGroup) {
      final other = members.where((m) => m.id != myId);
      if (other.isNotEmpty) {
        directName = other.first.name;
        directEmail = other.first.email;
      }
    }

    String? adminId = (j['adminId'] ??
            j['ownerId'] ??
            j['createdBy'] ??
            j['creatorId'] ??
            (j['admin'] is Map ? j['admin']['id'] : null) ??
            (j['owner'] is Map ? j['owner']['id'] : null))
        ?.toString();
    if (adminId == null) {
      final admins = members.where((m) {
        final role = m.role?.toLowerCase();
        return role == 'admin' || role == 'owner';
      });
      if (admins.isNotEmpty) adminId = admins.first.id;
    }

    final last = j['lastMessage'] is Map
        ? ChatMessage.fromJson(Map<String, dynamic>.from(j['lastMessage']))
        : null;

    return Conversation(
      id: j['id'].toString(),
      isTeam: isTeam,
      isGroup: isGroup,
      groupTitle: isGroup ? cleanGroupName((j['name'] ?? j['title'])?.toString()) : null,
      directName: directName,
      directEmail: directEmail,
      avatar: j['avatar']?.toString(),
      adminId: adminId,
      unreadCount: int.tryParse((j['unreadCount'] ?? 0).toString()) ?? 0,
      updatedAt: DateTime.tryParse((j['updatedAt'] ?? '').toString())
              ?.toLocal() ??
          last?.createdAt ??
          DateTime.now(),
      lastMessage: last,
      members: members,
    );
  }
}
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
        avatarUrl: j['avatar']?.toString(),
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
  });

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
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'].toString(),
        clientMessageId: j['clientMessageId']?.toString(),
        senderId: (j['senderId'] ?? j['sender']?['id'] ?? '').toString(),
        senderName: (j['sender']?['name'] ?? '').toString(),
        senderEmail: j['sender']?['email']?.toString(),
        text: (j['content'] ?? '').toString(),
        fileUrl: j['fileUrl']?.toString(),
        fileType: j['fileType']?.toString(),
        createdAt: DateTime.parse(j['createdAt'].toString()).toLocal(),
      );
}

class Conversation {
  final String id;
  final String? directName;
  final String? directEmail;
  final String? groupTitle;
  final bool isGroup;
  final String? avatar;
  final String? ownerId;
  final int unreadCount;
  final DateTime updatedAt;
  final ChatMessage? lastMessage;
  final List<ChatUser> members;

  const Conversation({
    required this.id,
    this.directName,
    this.directEmail,
    this.groupTitle,
    this.isGroup = false,
    this.avatar,
    this.ownerId,
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
        directName: directName,
        directEmail: directEmail,
        groupTitle: groupTitle,
        isGroup: isGroup,
        avatar: avatar,
        ownerId: ownerId,
        unreadCount: unreadCount ?? this.unreadCount,
        updatedAt: updatedAt ?? this.updatedAt,
        lastMessage: lastMessage ?? this.lastMessage,
        members: members,
      );

  String titleFor(String currentUserId) {
    if (isGroup) return groupTitle ?? 'Unnamed Group';
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

    String? ownerId = (j['ownerId'] ??
            j['createdBy'] ??
            j['creatorId'] ??
            (j['owner'] is Map ? j['owner']['id'] : null))
        ?.toString();
    if (ownerId == null) {
      final owners = members.where((m) => m.role?.toLowerCase() == 'owner');
      if (owners.isNotEmpty) ownerId = owners.first.id;
    }

    final last = j['lastMessage'] is Map
        ? ChatMessage.fromJson(Map<String, dynamic>.from(j['lastMessage']))
        : null;

    return Conversation(
      id: j['id'].toString(),
      isGroup: isGroup,
      groupTitle: isGroup ? (j['name'] ?? j['title'])?.toString() : null,
      directName: directName,
      directEmail: directEmail,
      avatar: j['avatar']?.toString(),
      ownerId: ownerId,
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
enum MessageStatus{sending,sent,failed}

class ChatUser {
  final String id;
  final String name;
  final String? avatarUrl;

  const ChatUser({
    required this.id,
    required this.name,
    this.avatarUrl,
  });
}

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String previewText;
  final DateTime createdAt;
  final MessageStatus status;
  final bool isRead;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.previewText,
    required this.createdAt,
    this.status = MessageStatus.sent,
    this.isRead = false,
  });
  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? previewText,
    DateTime? createdAt,
    MessageStatus? status,
    bool? isRead,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      previewText: previewText ?? this.previewText,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      isRead: isRead ?? this.isRead,
    );
  }
}

class Conversation {
  final String id;
  final String? directName;
  final String? groupTitle;
  final bool isGroup;
  final String? avatar;
  final int unreadCount;
  final DateTime updatedAt;
  final ChatMessage? lastMessage;
  final List<ChatUser> members;

  const Conversation({
    required this.id,
    this.directName,
    this.groupTitle,
    this.isGroup = false,
    this.avatar,
    this.unreadCount = 0,
    required this.updatedAt,
    this.lastMessage,
    this.members = const [],
  });

  String titleFor(String currentUserId) {
    if (isGroup) return groupTitle ?? 'Unnamed Group';
    return directName ?? 'Direct Chat';
  }
}
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

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.previewText,
    required this.createdAt,
  });
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

  const Conversation({
    required this.id,
    this.directName,
    this.groupTitle,
    this.isGroup = false,
    this.avatar,
    this.unreadCount = 0,
    required this.updatedAt,
    this.lastMessage,
  });

  String titleFor(String currentUserId) {
    if (isGroup) return groupTitle ?? 'Unnamed Group';
    return directName ?? 'Direct Chat';
  }
}
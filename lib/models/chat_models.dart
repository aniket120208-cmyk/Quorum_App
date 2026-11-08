import 'package:quorum_app/models/poll_models.dart';

enum MessageStatus { uploading, uploadFailed, sending, sent, failed }

String? _avatarFrom(Map j) {
  for (final key in const [
    'avatar',
    'avatarUrl',
    'profilePicture',
    'profileImage',
    'profilePic',
    'photoUrl',
    'photo',
    'picture',
    'imageUrl',
    'image',
  ]) {
    final v = j[key];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return null;
}

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
        avatarUrl: _avatarFrom(j),
        role: j['role']?.toString(),
      );
}

class MessageReactionGroup {
  final String emoji;
  final int count;
  final List<ChatUser> users;

  const MessageReactionGroup({required this.emoji, required this.count, this.users = const []});

  bool reactedBy(String userId) => userId.isNotEmpty && users.any((u) => u.id == userId);

  factory MessageReactionGroup.fromJson(Map<String, dynamic> j) {
    final users = j['users'] is List
        ? (j['users'] as List)
            .whereType<Map>()
            .map((e) => ChatUser.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <ChatUser>[];
    return MessageReactionGroup(
      emoji: (j['emoji'] ?? '').toString(),
      count: int.tryParse((j['count'] ?? users.length).toString()) ?? users.length,
      users: users,
    );
  }

  static List<MessageReactionGroup> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => MessageReactionGroup.fromJson(Map<String, dynamic>.from(e)))
        .where((g) => g.emoji.isNotEmpty && g.count > 0)
        .toList();
  }
}

List<MessageReactionGroup> toggleReaction(List<MessageReactionGroup> groups, ChatUser me, String emoji) {
  final next = <MessageReactionGroup>[];
  var previous = '';
  for (final g in groups) {
    if (g.reactedBy(me.id)) {
      previous = g.emoji;
      final rest = g.users.where((u) => u.id != me.id).toList();
      if (rest.isNotEmpty) next.add(MessageReactionGroup(emoji: g.emoji, count: rest.length, users: rest));
    } else {
      next.add(g);
    }
  }
  if (previous == emoji) return next;
  final i = next.indexWhere((g) => g.emoji == emoji);
  if (i == -1) {
    next.add(MessageReactionGroup(emoji: emoji, count: 1, users: [me]));
  } else {
    final users = [...next[i].users, me];
    next[i] = MessageReactionGroup(emoji: emoji, count: users.length, users: users);
  }
  return next;
}

class QuotedReply {
  final String id;
  final String content;
  final String? fileUrl;
  final String? fileType;
  final String? fileName;
  final int? audioDuration;
  final bool isDeleted;
  final String senderId;
  final String senderName;
  final String? senderAvatar;

  const QuotedReply({
    required this.id,
    this.content = '',
    this.fileUrl,
    this.fileType,
    this.fileName,
    this.audioDuration,
    this.isDeleted = false,
    this.senderId = '',
    this.senderName = '',
    this.senderAvatar,
  });

  bool get isVoice => fileType == 'voice';
  bool get isImage => fileType == 'image';

  QuotedReply asDeleted() => QuotedReply(
        id: id,
        senderId: senderId,
        senderName: senderName,
        senderAvatar: senderAvatar,
        isDeleted: true,
      );

  factory QuotedReply.fromJson(Map<String, dynamic> j) {
    final sender = j['sender'] is Map ? Map<String, dynamic>.from(j['sender']) : const <String, dynamic>{};
    return QuotedReply(
      id: j['id'].toString(),
      content: (j['content'] ?? '').toString(),
      fileUrl: j['fileUrl']?.toString(),
      fileType: j['fileType']?.toString(),
      fileName: j['fileName']?.toString(),
      audioDuration: int.tryParse((j['audioDuration'] ?? '').toString()),
      isDeleted: j['isDeleted'] == true,
      senderId: (sender['id'] ?? j['senderId'] ?? '').toString(),
      senderName: (sender['name'] ?? '').toString(),
      senderAvatar: _avatarFrom(sender),
    );
  }
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
  final String? senderAvatar;
  final int? fileSize;
  final int? audioDuration;
  final List<double> audioWaveform;
  final String? replyToId;
  final QuotedReply? replyTo;
  final bool isForwarded;
  final int forwardCount;
  final bool isDeleted;
  final List<MessageReactionGroup> reactions;
  final Poll? poll;

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
    this.senderAvatar,
    this.fileSize,
    this.audioDuration,
    this.audioWaveform = const [],
    this.replyToId,
    this.replyTo,
    this.isForwarded = false,
    this.forwardCount = 0,
    this.isDeleted = false,
    this.reactions = const [],
    this.poll,
  });
  bool get isVoice => fileType == 'voice';
  bool get isPoll => fileType == 'poll' || poll != null;
  bool mentions(String userId) => userId.isNotEmpty && mentionedUserIds.contains(userId);
  bool get hasAttachment => fileUrl != null || localPath != null;

  String get previewText {
    if (isDeleted) return 'This message was deleted';
    if (isPoll) {
      final q = poll?.question ?? text;
      return q.isEmpty ? '📊 Poll' : '📊 $q';
    }
    if (text.isNotEmpty) return text;
    if (!hasAttachment) return '';
    switch (fileType) {
      case 'voice':
        return '🎤 Voice message';
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
    String? senderAvatar,
    int? fileSize,
    int? audioDuration,
    List<double>? audioWaveform,
    String? replyToId,
    QuotedReply? replyTo,
    bool? isForwarded,
    int? forwardCount,
    bool? isDeleted,
    List<MessageReactionGroup>? reactions,
    Poll? poll,
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
      senderAvatar: senderAvatar ?? this.senderAvatar,
      fileSize: fileSize ?? this.fileSize,
      audioDuration: audioDuration ?? this.audioDuration,
      audioWaveform: audioWaveform ?? this.audioWaveform,
      replyToId: replyToId ?? this.replyToId,
      replyTo: replyTo ?? this.replyTo,
      isForwarded: isForwarded ?? this.isForwarded,
      forwardCount: forwardCount ?? this.forwardCount,
      isDeleted: isDeleted ?? this.isDeleted,
      reactions: reactions ?? this.reactions,
      poll: poll ?? this.poll,
    );
  }

  ChatMessage asDeleted() => ChatMessage(
        id: id,
        clientMessageId: clientMessageId,
        senderId: senderId,
        senderName: senderName,
        senderEmail: senderEmail,
        senderAvatar: senderAvatar,
        createdAt: createdAt,
        isRead: isRead,
        replyToId: replyToId,
        replyTo: replyTo,
        isForwarded: isForwarded,
        forwardCount: forwardCount,
        isDeleted: true,
      );

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
      fileType: j['fileType']?.toString() ?? (j['poll'] is Map || j['type']?.toString() == 'poll' ? 'poll' : null),
      fileName: j['fileName']?.toString(),
      createdAt: DateTime.parse(j['createdAt'].toString()).toLocal(),
      mentionedUserIds: ids,
      mentionedUsers: users,
      isEdited: j['isEdited'] == true || j['editedAt'] != null,
      senderAvatar: j['sender'] is Map ? _avatarFrom(j['sender'] as Map) : null,
      fileSize: int.tryParse((j['fileSize'] ?? '').toString()),
      audioDuration: int.tryParse((j['audioDuration'] ?? '').toString()),
      audioWaveform: j['audioWaveform'] is List
          ? (j['audioWaveform'] as List)
              .map((e) => (double.tryParse(e.toString()) ?? 0).clamp(0.0, 1.0).toDouble())
              .toList()
          : const [],
      replyToId: j['replyToId']?.toString(),
      replyTo: j['replyTo'] is Map ? QuotedReply.fromJson(Map<String, dynamic>.from(j['replyTo'])) : null,
      isForwarded: j['isForwarded'] == true,
      forwardCount: int.tryParse((j['forwardCount'] ?? 0).toString()) ?? 0,
      isDeleted: j['isDeleted'] == true,
      reactions: MessageReactionGroup.listFrom(j['reactions']),
      poll: Poll.tryParse(j['poll']),
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
  final String? directAvatar;
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
    this.directAvatar,
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
        directAvatar: directAvatar,
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
    String? directAvatar;
    if (!isGroup) {
      final other = members.where((m) => m.id != myId);
      if (other.isNotEmpty) {
        directName = other.first.name;
        directEmail = other.first.email;
        directAvatar = other.first.avatarUrl;
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
      directAvatar: directAvatar,
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
import 'package:flutter/material.dart';

DateTime? _date(dynamic v) => DateTime.tryParse((v ?? '').toString())?.toLocal();
int _int(dynamic v) => int.tryParse((v ?? 0).toString()) ?? 0;
Map<String, dynamic> _asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

String? _str(dynamic v) {
  final s = v?.toString();
  if (s == null || s.isEmpty || s == 'null') return null;
  return s;
}

String orgFeedTimeAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes < 1 ? 1 : d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[t.month - 1]} ${t.day}${t.year == DateTime.now().year ? '' : ', ${t.year}'}';
}

String orgFeedFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

enum OrgPostCategory {
  announcement('ANNOUNCEMENT', 'Announcement', Color(0xFF38BDF8), Icons.campaign_rounded),
  festival('FESTIVAL', 'Festival', Color(0xFFF59E0B), Icons.celebration_rounded),
  milestone('MILESTONE', 'Milestone', Color(0xFFF97316), Icons.emoji_events_rounded),
  promotion('PROMOTION', 'Promotion', Color(0xFF22C55E), Icons.trending_up_rounded),
  birthday('BIRTHDAY', 'Birthday', Color(0xFFEC4899), Icons.cake_rounded),
  welcome('WELCOME', 'Welcome', Color(0xFF3DDCC4), Icons.waving_hand_rounded),
  newTeam('NEW_TEAM', 'New team', Color(0xFF7C5CFC), Icons.groups_rounded),
  general('GENERAL', 'General', Color(0xFF9EA3AE), Icons.chat_bubble_outline_rounded);

  const OrgPostCategory(this.value, this.label, this.color, this.icon);
  final String value;
  final String label;
  final Color color;
  final IconData icon;

  bool get managerOnly => this == announcement || this == festival;

  static OrgPostCategory from(String? raw) {
    for (final c in OrgPostCategory.values) {
      if (c.value == raw?.toUpperCase()) return c;
    }
    return OrgPostCategory.general;
  }
}

class OrgFeedUser {
  final String id;
  final String name;
  final String? avatar;

  const OrgFeedUser({required this.id, required this.name, this.avatar});

  static OrgFeedUser? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final j = _asMap(raw);
    final id = (j['id'] ?? '').toString();
    if (id.isEmpty) return null;
    return OrgFeedUser(
      id: id,
      name: (j['name'] ?? '').toString(),
      avatar: _str(j['avatar'] ?? j['avatarUrl']),
    );
  }
}

class OrgFeedTeamRef {
  final String id;
  final String name;

  const OrgFeedTeamRef({required this.id, required this.name});

  static OrgFeedTeamRef? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final j = _asMap(raw);
    final id = (j['id'] ?? '').toString();
    if (id.isEmpty) return null;
    return OrgFeedTeamRef(id: id, name: (j['name'] ?? '').toString());
  }
}

class OrgFeedReaction {
  final String emoji;
  final int count;
  final bool reactedByMe;

  const OrgFeedReaction({required this.emoji, required this.count, required this.reactedByMe});

  OrgFeedReaction copyWith({int? count, bool? reactedByMe}) => OrgFeedReaction(
        emoji: emoji,
        count: count ?? this.count,
        reactedByMe: reactedByMe ?? this.reactedByMe,
      );

  factory OrgFeedReaction.fromJson(Map<String, dynamic> j) => OrgFeedReaction(
        emoji: (j['emoji'] ?? '').toString(),
        count: _int(j['count']),
        reactedByMe: j['reactedByMe'] == true,
      );

  static List<OrgFeedReaction> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map) OrgFeedReaction.fromJson(_asMap(e)),
    ].where((r) => r.emoji.isNotEmpty && r.count > 0).toList();
  }
}

class OrgFeedPost {
  final String id;
  final String organizationId;
  final String authorId;
  final OrgPostCategory category;
  final String? title;
  final String content;
  final String? fileUrl;
  final String? fileType;
  final String? fileName;
  final int? fileSize;
  final String? targetUserId;
  final String? targetTeamId;
  final List<String> mentionedUserIds;
  final bool isPinned;
  final DateTime? pinnedAt;
  final bool isSystemGenerated;
  final bool isEdited;
  final DateTime? editedAt;
  final DateTime? createdAt;
  final OrgFeedUser? author;
  final OrgFeedUser? targetUser;
  final OrgFeedTeamRef? targetTeam;
  final int commentCount;
  final List<OrgFeedReaction> reactions;

  const OrgFeedPost({
    required this.id,
    required this.organizationId,
    required this.authorId,
    required this.category,
    this.title,
    this.content = '',
    this.fileUrl,
    this.fileType,
    this.fileName,
    this.fileSize,
    this.targetUserId,
    this.targetTeamId,
    this.mentionedUserIds = const [],
    this.isPinned = false,
    this.pinnedAt,
    this.isSystemGenerated = false,
    this.isEdited = false,
    this.editedAt,
    this.createdAt,
    this.author,
    this.targetUser,
    this.targetTeam,
    this.commentCount = 0,
    this.reactions = const [],
  });

  bool get hasFile => fileUrl != null && fileUrl!.isNotEmpty;

  bool get isImage {
    if (!hasFile) return false;
    if (fileType == 'image') return true;
    final clean = fileUrl!.split('?').first.toLowerCase();
    return const ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic'].any(clean.endsWith);
  }

  OrgFeedPost copyWith({
    bool? isPinned,
    DateTime? pinnedAt,
    List<OrgFeedReaction>? reactions,
    int? commentCount,
  }) =>
      OrgFeedPost(
        id: id,
        organizationId: organizationId,
        authorId: authorId,
        category: category,
        title: title,
        content: content,
        fileUrl: fileUrl,
        fileType: fileType,
        fileName: fileName,
        fileSize: fileSize,
        targetUserId: targetUserId,
        targetTeamId: targetTeamId,
        mentionedUserIds: mentionedUserIds,
        isPinned: isPinned ?? this.isPinned,
        pinnedAt: pinnedAt ?? this.pinnedAt,
        isSystemGenerated: isSystemGenerated,
        isEdited: isEdited,
        editedAt: editedAt,
        createdAt: createdAt,
        author: author,
        targetUser: targetUser,
        targetTeam: targetTeam,
        commentCount: commentCount ?? this.commentCount,
        reactions: reactions ?? this.reactions,
      );

  factory OrgFeedPost.fromJson(Map<String, dynamic> raw) {
    final j = raw['post'] is Map ? _asMap(raw['post']) : raw;
    final count = _asMap(j['_count']);
    final mentions = j['mentionedUserIds'];
    return OrgFeedPost(
      id: (j['id'] ?? '').toString(),
      organizationId: (j['organizationId'] ?? '').toString(),
      authorId: (j['authorId'] ?? '').toString(),
      category: OrgPostCategory.from(j['category']?.toString()),
      title: _str(j['title']),
      content: (j['content'] ?? '').toString(),
      fileUrl: _str(j['fileUrl']),
      fileType: _str(j['fileType']),
      fileName: _str(j['fileName']),
      fileSize: j['fileSize'] == null ? null : _int(j['fileSize']),
      targetUserId: _str(j['targetUserId']),
      targetTeamId: _str(j['targetTeamId']),
      mentionedUserIds: mentions is List ? [for (final m in mentions) m.toString()] : const [],
      isPinned: j['isPinned'] == true,
      pinnedAt: _date(j['pinnedAt']),
      isSystemGenerated: j['isSystemGenerated'] == true,
      isEdited: j['isEdited'] == true,
      editedAt: _date(j['editedAt']),
      createdAt: _date(j['createdAt']),
      author: OrgFeedUser.fromJson(j['author']),
      targetUser: OrgFeedUser.fromJson(j['targetUser']),
      targetTeam: OrgFeedTeamRef.fromJson(j['targetTeam']),
      commentCount: _int(j['commentCount'] ?? count['comments']),
      reactions: OrgFeedReaction.listFrom(j['reactions']),
    );
  }
}

class OrgFeedPage {
  final List<OrgFeedPost> posts;
  final String? nextCursor;
  final bool hasNextPage;

  const OrgFeedPage(this.posts, this.nextCursor, this.hasNextPage);
}

class OrgFeedComment {
  final String id;
  final String postId;
  final String authorId;
  final String? parentId;
  final String content;
  final bool isEdited;
  final DateTime? createdAt;
  final OrgFeedUser? author;
  final List<OrgFeedComment> replies;

  const OrgFeedComment({
    required this.id,
    required this.postId,
    required this.authorId,
    this.parentId,
    required this.content,
    this.isEdited = false,
    this.createdAt,
    this.author,
    this.replies = const [],
  });

  OrgFeedComment copyWith({
    String? content,
    bool? isEdited,
    List<OrgFeedComment>? replies,
  }) =>
      OrgFeedComment(
        id: id,
        postId: postId,
        authorId: authorId,
        parentId: parentId,
        content: content ?? this.content,
        isEdited: isEdited ?? this.isEdited,
        createdAt: createdAt,
        author: author,
        replies: replies ?? this.replies,
      );

  factory OrgFeedComment.fromJson(Map<String, dynamic> raw) {
    final j = raw['comment'] is Map ? _asMap(raw['comment']) : raw;
    final replies = j['replies'];
    final author = OrgFeedUser.fromJson(j['author'] ?? j['user']);
    return OrgFeedComment(
      id: (j['id'] ?? '').toString(),
      postId: (j['postId'] ?? '').toString(),
      authorId: (j['authorId'] ?? author?.id ?? '').toString(),
      parentId: _str(j['parentId']),
      content: (j['content'] ?? '').toString(),
      isEdited: j['isEdited'] == true,
      createdAt: _date(j['createdAt']),
      author: author,
      replies: replies is List
          ? [for (final r in replies) if (r is Map) OrgFeedComment.fromJson(_asMap(r))]
          : const [],
    );
  }
}

class OrgCommentsPage {
  final List<OrgFeedComment> comments;
  final String? nextCursor;
  final bool hasNextPage;

  const OrgCommentsPage(this.comments, this.nextCursor, this.hasNextPage);
}

class OrgReactResult {
  final String action;
  final List<OrgFeedReaction> reactions;

  const OrgReactResult(this.action, this.reactions);
}
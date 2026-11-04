import 'package:quorum_app/models/chat_models.dart';

class PageResult<T> {
  final List<T> items;
  final String? cursor;
  final bool hasMore;
  const PageResult(this.items, this.cursor, this.hasMore);
}

bool canModerate(String role) => role == 'OWNER' || role == 'ADMIN';

bool canRemoveMember(String myRole, String targetRole) {
  if (myRole == 'OWNER') return targetRole != 'OWNER';
  if (myRole == 'ADMIN') return targetRole == 'MEMBER';
  return false;
}

String roleLabel(String role) {
  switch (role) {
    case 'OWNER':
      return 'Owner';
    case 'ADMIN':
      return 'Admin';
    default:
      return 'Member';
  }
}

DateTime? _date(dynamic v) => DateTime.tryParse((v ?? '').toString())?.toLocal();
int _int(dynamic v) => int.tryParse((v ?? 0).toString()) ?? 0;

class Community {
  final String id;
  final String name;
  final String? description;
  final String role;
  final int memberCount;
  final DateTime? createdAt;

  const Community({
    required this.id,
    required this.name,
    this.description,
    required this.role,
    required this.memberCount,
    this.createdAt,
  });

  factory Community.fromJson(Map<String, dynamic> j) => Community(
        id: (j['id'] ?? j['communityId']).toString(),
        name: (j['name'] ?? '').toString(),
        description: j['description']?.toString(),
        role: (j['role'] ?? j['currentUserRole'] ?? 'MEMBER').toString().toUpperCase(),
        memberCount: _int(j['memberCount']),
        createdAt: _date(j['createdAt'] ?? j['joinedAt']),
      );
}

class CommunityDetail {
  final String id;
  final String name;
  final String? description;
  final String ownerId;
  final String ownerName;
  final String? ownerAvatar;
  final int memberCount;
  final String role;
  final DateTime? createdAt;

  const CommunityDetail({
    required this.id,
    required this.name,
    this.description,
    required this.ownerId,
    required this.ownerName,
    this.ownerAvatar,
    required this.memberCount,
    required this.role,
    this.createdAt,
  });

  factory CommunityDetail.fromJson(Map<String, dynamic> j) {
    final owner = j['owner'] is Map ? Map<String, dynamic>.from(j['owner']) : <String, dynamic>{};
    return CommunityDetail(
      id: j['id'].toString(),
      name: (j['name'] ?? '').toString(),
      description: j['description']?.toString(),
      ownerId: (j['ownerId'] ?? owner['id'] ?? '').toString(),
      ownerName: (owner['name'] ?? '').toString(),
      ownerAvatar: owner['avatar']?.toString(),
      memberCount: _int(j['memberCount']),
      role: (j['currentUserRole'] ?? j['role'] ?? 'MEMBER').toString().toUpperCase(),
      createdAt: _date(j['createdAt']),
    );
  }
}

class CommunityMember {
  final String id;
  final String role;
  final DateTime? joinedAt;
  final ChatUser user;

  const CommunityMember({
    required this.id,
    required this.role,
    this.joinedAt,
    required this.user,
  });

  factory CommunityMember.fromJson(Map<String, dynamic> j) => CommunityMember(
        id: (j['id'] ?? '').toString(),
        role: (j['role'] ?? 'MEMBER').toString().toUpperCase(),
        joinedAt: _date(j['joinedAt']),
        user: ChatUser.fromJson(
          j['user'] is Map ? Map<String, dynamic>.from(j['user']) : <String, dynamic>{'id': ''},
        ),
      );
}

class CommunityChannel {
  final String id;
  final String communityId;
  final String name;
  final String? description;
  final bool isDefault;
  final DateTime? createdAt;

  const CommunityChannel({
    required this.id,
    required this.communityId,
    required this.name,
    this.description,
    this.isDefault = false,
    this.createdAt,
  });

  factory CommunityChannel.fromJson(Map<String, dynamic> j) => CommunityChannel(
        id: j['id'].toString(),
        communityId: (j['communityId'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        description: j['description']?.toString(),
        isDefault: j['isDefault'] == true,
        createdAt: _date(j['createdAt']),
      );
}

class CommunityPost {
  final String id;
  final String communityId;
  final String? channelId;
  final String? fileUrl;
  final String? fileType;
  final String authorId;
  final String authorName;
  final String? authorAvatar;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int commentCount;

  const CommunityPost({
    required this.id,
    required this.communityId,
    this.channelId,
    this.fileUrl,
    this.fileType,
    required this.authorId,
    required this.authorName,
    this.authorAvatar,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.commentCount = 0,
  });

  bool get edited => updatedAt.difference(createdAt).inSeconds > 1;

  bool get hasAttachment => fileUrl != null && fileUrl!.isNotEmpty;

  bool get isImage => hasAttachment && fileType == 'image';

  bool get isDocument => hasAttachment && (fileType == 'document' || fileType == 'file');

  String get attachmentName {
    final u = fileUrl;
    if (u == null || u.isEmpty) return 'File';
    final segments = Uri.tryParse(u)?.pathSegments;
    if (segments == null || segments.isEmpty) return 'File';
    return Uri.decodeComponent(segments.last);
  }

  CommunityPost copyWith({
    String? content,
    DateTime? updatedAt,
    int? commentCount,
    String? fileUrl,
    String? fileType,
  }) =>
      CommunityPost(
        id: id,
        communityId: communityId,
        channelId: channelId,
        fileUrl: fileUrl ?? this.fileUrl,
        fileType: fileType ?? this.fileType,
        authorId: authorId,
        authorName: authorName,
        authorAvatar: authorAvatar,
        content: content ?? this.content,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        commentCount: commentCount ?? this.commentCount,
      );

  factory CommunityPost.fromJson(Map<String, dynamic> j) {
    final author = j['author'] is Map ? Map<String, dynamic>.from(j['author']) : <String, dynamic>{};
    final counts = j['_count'] is Map ? Map<String, dynamic>.from(j['_count']) : <String, dynamic>{};
    final created = _date(j['createdAt']) ?? DateTime.now();
    final channel = j['channel'] is Map ? Map<String, dynamic>.from(j['channel']) : <String, dynamic>{};
    final rawChannelId = (j['channelId'] ?? channel['id'])?.toString();
    final rawFileUrl = j['fileUrl']?.toString();
    return CommunityPost(
      id: j['id'].toString(),
      communityId: (j['communityId'] ?? '').toString(),
      channelId: (rawChannelId == null || rawChannelId.isEmpty) ? null : rawChannelId,
      fileUrl: (rawFileUrl == null || rawFileUrl.isEmpty) ? null : rawFileUrl,
      fileType: j['fileType']?.toString(),
      authorId: (j['authorId'] ?? author['id'] ?? '').toString(),
      authorName: (author['name'] ?? '').toString(),
      authorAvatar: author['avatar']?.toString(),
      content: (j['content'] ?? '').toString(),
      createdAt: created,
      updatedAt: _date(j['updatedAt']) ?? created,
      commentCount: _int(counts['comments']),
    );
  }
}

class CommunityComment {
  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String? authorAvatar;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CommunityComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    this.authorAvatar,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get edited => updatedAt.difference(createdAt).inSeconds > 1;

  CommunityComment copyWith({String? content, DateTime? updatedAt}) => CommunityComment(
        id: id,
        postId: postId,
        authorId: authorId,
        authorName: authorName,
        authorAvatar: authorAvatar,
        content: content ?? this.content,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory CommunityComment.fromJson(Map<String, dynamic> j) {
    final author = j['author'] is Map ? Map<String, dynamic>.from(j['author']) : <String, dynamic>{};
    final created = _date(j['createdAt']) ?? DateTime.now();
    return CommunityComment(
      id: j['id'].toString(),
      postId: (j['postId'] ?? '').toString(),
      authorId: (j['authorId'] ?? author['id'] ?? '').toString(),
      authorName: (author['name'] ?? '').toString(),
      authorAvatar: author['avatar']?.toString(),
      content: (j['content'] ?? '').toString(),
      createdAt: created,
      updatedAt: _date(j['updatedAt']) ?? created,
    );
  }
}

class InviteLink {
  final String token;
  final String url;
  final DateTime? expiresAt;

  const InviteLink({required this.token, required this.url, this.expiresAt});

  factory InviteLink.fromJson(Map<String, dynamic> j) => InviteLink(
        token: (j['token'] ?? '').toString(),
        url: (j['inviteUrl'] ?? '').toString(),
        expiresAt: _date(j['expiresAt']),
      );
}

class InvitePreview {
  final bool valid;
  final String communityName;
  final String? description;
  final int memberCount;
  final String inviterName;
  final DateTime? expiresAt;

  const InvitePreview({
    required this.valid,
    required this.communityName,
    this.description,
    required this.memberCount,
    required this.inviterName,
    this.expiresAt,
  });

  factory InvitePreview.fromJson(Map<String, dynamic> j) {
    final c = j['community'] is Map ? Map<String, dynamic>.from(j['community']) : <String, dynamic>{};
    final i = j['inviter'] is Map ? Map<String, dynamic>.from(j['inviter']) : <String, dynamic>{};
    return InvitePreview(
      valid: j['valid'] != false,
      communityName: (c['name'] ?? '').toString(),
      description: c['description']?.toString(),
      memberCount: _int(c['memberCount']),
      inviterName: (i['name'] ?? '').toString(),
      expiresAt: _date(j['expiresAt']),
    );
  }
}

enum MembershipStatus {
  owner,
  admin,
  member,
  pendingRequest,
  notMember;

  static MembershipStatus from(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'OWNER':
        return MembershipStatus.owner;
      case 'ADMIN':
        return MembershipStatus.admin;
      case 'MEMBER':
        return MembershipStatus.member;
      case 'PENDING_REQUEST':
        return MembershipStatus.pendingRequest;
      default:
        return MembershipStatus.notMember;
    }
  }

  bool get isJoined =>
      this == MembershipStatus.owner || this == MembershipStatus.admin || this == MembershipStatus.member;

  String get role {
    switch (this) {
      case MembershipStatus.owner:
        return 'OWNER';
      case MembershipStatus.admin:
        return 'ADMIN';
      default:
        return 'MEMBER';
    }
  }
}

class DiscoveredCommunity {
  final String id;
  final String name;
  final String? description;
  final String? icon;
  final DateTime? createdAt;
  final int memberCount;
  final int channelCount;
  final MembershipStatus status;
  final String? pendingRequestId;

  const DiscoveredCommunity({
    required this.id,
    required this.name,
    this.description,
    this.icon,
    this.createdAt,
    required this.memberCount,
    required this.channelCount,
    required this.status,
    this.pendingRequestId,
  });

  DiscoveredCommunity copyWith({MembershipStatus? status, String? pendingRequestId, bool clearPending = false}) =>
      DiscoveredCommunity(
        id: id,
        name: name,
        description: description,
        icon: icon,
        createdAt: createdAt,
        memberCount: memberCount,
        channelCount: channelCount,
        status: status ?? this.status,
        pendingRequestId: clearPending ? null : (pendingRequestId ?? this.pendingRequestId),
      );

  factory DiscoveredCommunity.fromJson(Map<String, dynamic> j) {
    final rawIcon = j['icon']?.toString();
    final rawPending = j['pendingRequestId']?.toString();
    return DiscoveredCommunity(
      id: j['id'].toString(),
      name: (j['name'] ?? '').toString(),
      description: j['description']?.toString(),
      icon: (rawIcon == null || rawIcon.isEmpty) ? null : rawIcon,
      createdAt: _date(j['createdAt']),
      memberCount: _int(j['memberCount']),
      channelCount: _int(j['channelCount']),
      status: MembershipStatus.from(j['membershipStatus']?.toString()),
      pendingRequestId: (rawPending == null || rawPending.isEmpty) ? null : rawPending,
    );
  }
}

enum JoinRequestStatus {
  pending,
  accepted,
  rejected,
  cancelled;

  static JoinRequestStatus from(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'ACCEPTED':
        return JoinRequestStatus.accepted;
      case 'REJECTED':
        return JoinRequestStatus.rejected;
      case 'CANCELLED':
        return JoinRequestStatus.cancelled;
      default:
        return JoinRequestStatus.pending;
    }
  }

  String get value => name.toUpperCase();
}

class JoinRequestApplicant {
  final String id;
  final String name;
  final String email;
  final String? avatar;

  const JoinRequestApplicant({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
  });

  factory JoinRequestApplicant.fromJson(Map<String, dynamic> j) {
    final rawAvatar = j['avatar']?.toString();
    return JoinRequestApplicant(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      avatar: (rawAvatar == null || rawAvatar.isEmpty) ? null : rawAvatar,
    );
  }
}

class JoinRequestCommunity {
  final String id;
  final String name;
  final String? description;
  final String? icon;

  const JoinRequestCommunity({
    required this.id,
    required this.name,
    this.description,
    this.icon,
  });

  factory JoinRequestCommunity.fromJson(Map<String, dynamic> j) {
    final rawIcon = j['icon']?.toString();
    return JoinRequestCommunity(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      description: j['description']?.toString(),
      icon: (rawIcon == null || rawIcon.isEmpty) ? null : rawIcon,
    );
  }
}

class CommunityJoinRequest {
  final String id;
  final String communityId;
  final String userId;
  final JoinRequestStatus status;
  final String? message;
  final DateTime? createdAt;
  final JoinRequestApplicant? user;
  final JoinRequestCommunity? community;

  const CommunityJoinRequest({
    required this.id,
    required this.communityId,
    required this.userId,
    required this.status,
    this.message,
    this.createdAt,
    this.user,
    this.community,
  });

  factory CommunityJoinRequest.fromJson(Map<String, dynamic> j) {
    final rawMessage = j['message']?.toString();
    return CommunityJoinRequest(
      id: j['id'].toString(),
      communityId: (j['communityId'] ?? '').toString(),
      userId: (j['userId'] ?? '').toString(),
      status: JoinRequestStatus.from(j['status']?.toString()),
      message: (rawMessage == null || rawMessage.trim().isEmpty) ? null : rawMessage.trim(),
      createdAt: _date(j['createdAt']),
      user: j['user'] is Map ? JoinRequestApplicant.fromJson(Map<String, dynamic>.from(j['user'])) : null,
      community: j['community'] is Map ? JoinRequestCommunity.fromJson(Map<String, dynamic>.from(j['community'])) : null,
    );
  }
}
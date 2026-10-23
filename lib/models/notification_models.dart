enum NotificationType {
  orgInvite('ORG_INVITE', 'Organization invites'),
  teamInvite('TEAM_INVITE', 'Team invites'),
  communityInvite('COMMUNITY_INVITE', 'Community invites'),
  communityPostComment('COMMUNITY_POST_COMMENT', 'Community comments'),
  meetingStarted('MEETING_STARTED', 'Meeting started'),
  directMessage('DIRECT_MESSAGE', 'Direct messages'),
  eventReminder('EVENT_REMINDER', 'Calendar reminders'),
  system('SYSTEM', 'System announcements');

  const NotificationType(this.value, this.label);
  final String value;
  final String label;

  static NotificationType from(String? raw) {
    for (final t in NotificationType.values) {
      if (t.value == raw) return t;
    }
    return NotificationType.system;
  }
}

class NotificationActor {
  final String id;
  final String name;
  final String? avatar;

  const NotificationActor({required this.id, required this.name, this.avatar});

  factory NotificationActor.fromJson(Map<String, dynamic> j) => NotificationActor(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        avatar: (j['avatar'] == null || j['avatar'].toString().isEmpty) ? null : j['avatar'].toString(),
      );
}

class NotificationItem {
  final String id;
  final String recipientId;
  final String? actorId;
  final NotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;
  final NotificationActor? actor;

  const NotificationItem({
    required this.id,
    required this.recipientId,
    this.actorId,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.isRead,
    this.readAt,
    required this.createdAt,
    this.actor,
  });

  NotificationItem copyWith({bool? isRead, DateTime? readAt}) => NotificationItem(
        id: id,
        recipientId: recipientId,
        actorId: actorId,
        type: type,
        title: title,
        body: body,
        data: data,
        isRead: isRead ?? this.isRead,
        readAt: readAt ?? this.readAt,
        createdAt: createdAt,
        actor: actor,
      );

  factory NotificationItem.fromJson(Map<String, dynamic> j) {
    final rawData = j['data'];
    final rawActor = j['actor'];
    return NotificationItem(
      id: (j['id'] ?? '').toString(),
      recipientId: (j['recipientId'] ?? '').toString(),
      actorId: j['actorId']?.toString(),
      type: NotificationType.from(j['type']?.toString()),
      title: (j['title'] ?? '').toString(),
      body: (j['body'] ?? '').toString(),
      data: rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{},
      isRead: j['isRead'] == true,
      readAt: DateTime.tryParse((j['readAt'] ?? '').toString())?.toLocal(),
      createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString())?.toLocal() ?? DateTime.now(),
      actor: rawActor is Map ? NotificationActor.fromJson(Map<String, dynamic>.from(rawActor)) : null,
    );
  }
}

class NotificationPage {
  final List<NotificationItem> items;
  final int total;
  final int page;
  final int totalPages;
  final int unreadCount;

  const NotificationPage({
    required this.items,
    required this.total,
    required this.page,
    required this.totalPages,
    required this.unreadCount,
  });

  bool get hasMore => page < totalPages;
}

class NotificationPreference {
  final NotificationType type;
  final bool inApp;
  final bool push;
  final bool email;

  const NotificationPreference({
    required this.type,
    this.inApp = true,
    this.push = true,
    this.email = true,
  });

  NotificationPreference copyWith({bool? inApp, bool? push, bool? email}) => NotificationPreference(
        type: type,
        inApp: inApp ?? this.inApp,
        push: push ?? this.push,
        email: email ?? this.email,
      );

  factory NotificationPreference.fromJson(Map<String, dynamic> j) => NotificationPreference(
        type: NotificationType.from(j['notificationType']?.toString()),
        inApp: j['inApp'] != false,
        push: j['push'] != false,
        email: j['email'] != false,
      );
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 45) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  if (d.inDays < 30) return '${(d.inDays / 7).floor()}w';
  return '${t.day}/${t.month}/${t.year}';
}
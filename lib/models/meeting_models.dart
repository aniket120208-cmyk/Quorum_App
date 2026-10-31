import 'package:flutter_webrtc/flutter_webrtc.dart';

String formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

class CreatedMeeting {
  final String code;
  final String link;
  const CreatedMeeting({required this.code, required this.link});
}

enum MeetingScope {
  personal('PERSONAL', 'Personal'),
  organization('ORGANIZATION', 'Organization'),
  team('TEAM', 'Team');

  const MeetingScope(this.value, this.label);
  final String value;
  final String label;

  static MeetingScope fromValue(dynamic raw) {
    final text = (raw ?? '').toString().toUpperCase();
    return MeetingScope.values.firstWhere((e) => e.value == text, orElse: () => MeetingScope.personal);
  }
}

enum MeetingStatus {
  scheduled,
  active,
  ended,
  cancelled;

  static MeetingStatus fromValue(dynamic raw) {
    switch ((raw ?? '').toString().toUpperCase()) {
      case 'SCHEDULED':
        return MeetingStatus.scheduled;
      case 'ENDED':
        return MeetingStatus.ended;
      case 'CANCELLED':
        return MeetingStatus.cancelled;
      default:
        return MeetingStatus.active;
    }
  }
}

DateTime? _meetingDate(dynamic v) => DateTime.tryParse((v ?? '').toString())?.toLocal();

String? _meetingText(dynamic v) {
  final s = v?.toString().trim();
  if (s == null || s.isEmpty || s == 'null') return null;
  return s;
}

Map<String, dynamic> _meetingMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class MeetingInfo {
  final String code;
  final String hostId;
  final String hostName;
  final bool waitingRoom;
  final String title;
  final MeetingScope scope;
  final MeetingStatus status;
  final DateTime? scheduledStartTime;

  const MeetingInfo({
    required this.code,
    required this.hostId,
    required this.hostName,
    required this.waitingRoom,
    this.title = 'Meeting',
    this.scope = MeetingScope.personal,
    this.status = MeetingStatus.active,
    this.scheduledStartTime,
  });

  factory MeetingInfo.fromJson(Map<String, dynamic> j) {
    final host = _meetingMap(j['host']);
    return MeetingInfo(
      code: (j['code'] ?? '').toString(),
      hostId: (j['hostId'] ?? host['id'] ?? '').toString(),
      hostName: (host['name'] ?? '').toString(),
      waitingRoom: j['waitingRoom'] == true,
      title: _meetingText(j['title']) ?? 'Meeting',
      scope: MeetingScope.fromValue(j['scopeType']),
      status: MeetingStatus.fromValue(j['status']),
      scheduledStartTime: _meetingDate(j['scheduledStartTime']),
    );
  }
}

class ScopedMeeting {
  static const Duration earlyJoinWindow = Duration(minutes: 15);

  final String code;
  final String title;
  final MeetingScope scope;
  final MeetingStatus status;
  final DateTime? scheduledStartTime;
  final String hostId;
  final String hostName;
  final String? hostAvatar;
  final String? organizationId;
  final String? organizationName;
  final String? teamId;
  final String? teamName;
  final String? link;

  const ScopedMeeting({
    required this.code,
    required this.title,
    required this.scope,
    required this.status,
    this.scheduledStartTime,
    this.hostId = '',
    this.hostName = '',
    this.hostAvatar,
    this.organizationId,
    this.organizationName,
    this.teamId,
    this.teamName,
    this.link,
  });

  bool get isScheduled => status == MeetingStatus.scheduled;
  bool get isActive => status == MeetingStatus.active;
  bool get isOpen => isScheduled || isActive;

  DateTime? get joinOpensAt => scheduledStartTime?.subtract(earlyJoinWindow);

  String get scopeLabel {
    switch (scope) {
      case MeetingScope.personal:
        return 'Personal';
      case MeetingScope.organization:
        return organizationName ?? 'Organization';
      case MeetingScope.team:
        return teamName ?? 'Team';
    }
  }

  bool canJoin({required bool isHost, DateTime? now}) {
    if (!isOpen) return false;
    if (isActive || isHost) return true;
    final opens = joinOpensAt;
    if (opens == null) return true;
    return !(now ?? DateTime.now()).isBefore(opens);
  }

  factory ScopedMeeting.fromJson(Map<String, dynamic> j) {
    final host = _meetingMap(j['host']);
    final organization = _meetingMap(j['organization']);
    final team = _meetingMap(j['team']);
    return ScopedMeeting(
      code: (j['code'] ?? '').toString(),
      title: _meetingText(j['title']) ?? 'Meeting',
      scope: MeetingScope.fromValue(j['scopeType']),
      status: MeetingStatus.fromValue(j['status']),
      scheduledStartTime: _meetingDate(j['scheduledStartTime']),
      hostId: (j['hostId'] ?? host['id'] ?? '').toString(),
      hostName: (host['name'] ?? '').toString(),
      hostAvatar: _meetingText(host['avatar']),
      organizationId: _meetingText(j['organizationId'] ?? organization['id']),
      organizationName: _meetingText(organization['name']),
      teamId: _meetingText(j['teamId'] ?? team['id']),
      teamName: _meetingText(team['name']),
      link: _meetingText(j['link']),
    );
  }
}

class MeetingResult {
  final String code;
  final String title;
  final bool joined;
  final DateTime? joinedAt;
  final int durationSeconds;

  const MeetingResult({
    required this.code,
    required this.title,
    required this.joined,
    required this.joinedAt,
    required this.durationSeconds,
  });
  String get formattedDuration => formatDuration(durationSeconds);
}

class MeetingHistoryItem {
  final String code;
  final String title;
  final DateTime timestamp;
  final int durationSeconds;

  const MeetingHistoryItem({
    required this.code,
    required this.title,
    required this.timestamp,
    required this.durationSeconds,
  });
  String get duration => formatDuration(durationSeconds);

  factory MeetingHistoryItem.fromResult(MeetingResult r) => MeetingHistoryItem(
        code: r.code,
        title: r.title,
        timestamp: r.joinedAt ?? DateTime.now(),
        durationSeconds: r.durationSeconds,
      );

  factory MeetingHistoryItem.fromJson(Map<String, dynamic> j) => MeetingHistoryItem(
        code: j['code'].toString(),
        title: (j['title'] ?? 'Meeting').toString(),
        timestamp: DateTime.tryParse((j['timestamp'] ?? '').toString()) ?? DateTime.now(),
        durationSeconds: (j['durationSeconds'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'title': title,
        'timestamp': timestamp.toIso8601String(),
        'durationSeconds': durationSeconds,
      };
}

class MeetingChatMessage {
  final String senderId;
  final String senderName;
  final String content;
  final DateTime timestamp;

  const MeetingChatMessage({
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
  });

  factory MeetingChatMessage.fromJson(Map<String, dynamic> j) => MeetingChatMessage(
        senderId: (j['senderId'] ?? '').toString(),
        senderName: (j['senderName'] ?? 'Participant').toString(),
        content: (j['content'] ?? '').toString(),
        timestamp: DateTime.tryParse((j['timestamp'] ?? '').toString())?.toLocal() ?? DateTime.now(),
      );
}

class WaitingGuest {
  final String userId;
  final String name;
  const WaitingGuest({required this.userId, required this.name});
}

class RemotePeer {
  RemotePeer({required this.userId, required this.name});
  final String userId;
  String name;
  bool isMuted = false;
  bool isVideoOff = false;
  bool hasVideo = false;
  bool fitContain = false;
  bool isScreenSharing = false;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  late final Future<void> _ready = renderer.initialize();
  bool _disposed = false;

  Future<void> attachVideo(MediaStream stream) async {
    await _ready;
    if (_disposed) return;
    renderer.srcObject = stream;
    hasVideo = true;
  }

  Future<void> detachVideo() async {
    await _ready;
    if (_disposed) return;
    renderer.srcObject = null;
    hasVideo = false;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _ready;
    renderer.srcObject = null;
    await renderer.dispose();
  }
}
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

class MeetingInfo {
  final String code;
  final String hostId;
  final String hostName;
  final bool waitingRoom;
  
  const MeetingInfo({
    required this.code,
    required this.hostId,
    required this.hostName,
    required this.waitingRoom,
  });

  factory MeetingInfo.fromJson(Map<String, dynamic> j) {
    final host = j['host'] is Map ? Map<String, dynamic>.from(j['host']) : const <String, dynamic>{};
    return MeetingInfo(
      code: (j['code'] ?? '').toString(),
      hostId: (j['hostId'] ?? host['id'] ?? '').toString(),
      hostName: (host['name'] ?? '').toString(),
      waitingRoom: j['waitingRoom'] == true,
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
DateTime? _date(dynamic v) => DateTime.tryParse((v ?? '').toString())?.toLocal();
int? _intOrNull(dynamic v) => v == null ? null : int.tryParse(v.toString());
String? _str(dynamic v) {
  final s = v?.toString();
  if (s == null || s.isEmpty || s == 'null') return null;
  return s;
}

Map<String, dynamic> _asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

enum RecordingStatus {
  recording('RECORDING'),
  processing('PROCESSING'),
  completed('COMPLETED'),
  failed('FAILED');

  const RecordingStatus(this.apiValue);
  final String apiValue;

  static RecordingStatus fromString(String? v) {
    switch ((v ?? '').toUpperCase()) {
      case 'RECORDING':
        return RecordingStatus.recording;
      case 'COMPLETED':
        return RecordingStatus.completed;
      case 'FAILED':
        return RecordingStatus.failed;
      default:
        return RecordingStatus.processing;
    }
  }
}

class RecordingUser {
  final String id;
  final String name;
  final String? avatar;
  const RecordingUser({required this.id, required this.name, this.avatar});

  factory RecordingUser.fromJson(Map<String, dynamic> j) => RecordingUser(
        id: (j['id'] ?? j['_id'] ?? '').toString(),
        name: (j['name'] ?? 'Someone').toString(),
        avatar: _str(j['avatar'] ?? j['avatarUrl']),
      );
}

class RecordingStatusEvent {
  final bool isRecording;
  final RecordingStatus status;
  final String? recordingId;
  final String? meetingCode;
  final RecordingUser? startedBy;
  final RecordingUser? stoppedBy;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? durationSeconds;

  const RecordingStatusEvent({
    required this.isRecording,
    required this.status,
    this.recordingId,
    this.meetingCode,
    this.startedBy,
    this.stoppedBy,
    this.startedAt,
    this.endedAt,
    this.durationSeconds,
  });

  factory RecordingStatusEvent.fromJson(Map<String, dynamic> j) {
    final status = RecordingStatus.fromString(j['status']?.toString());
    final recording = j['isRecording'] == true || (j['isRecording'] == null && status == RecordingStatus.recording);
    final started = j['startedBy'] ?? j['recordedBy'];
    return RecordingStatusEvent(
      isRecording: recording,
      status: recording ? RecordingStatus.recording : status,
      recordingId: _str(j['recordingId'] ?? j['id']),
      meetingCode: _str(j['meetingCode']),
      startedBy: started is Map ? RecordingUser.fromJson(_asMap(started)) : null,
      stoppedBy: j['stoppedBy'] is Map ? RecordingUser.fromJson(_asMap(j['stoppedBy'])) : null,
      startedAt: _date(j['startedAt']),
      endedAt: _date(j['endedAt']),
      durationSeconds: _intOrNull(j['durationSeconds']),
    );
  }
}

class MeetingRecording {
  final String id;
  final String meetingCode;
  final RecordingStatus status;
  final String? fileUrl;
  final String? playbackUrl;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final int? fileSizeBytes;
  final String? summary;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? expiresAt;
  final String? meetingTitle;
  final RecordingUser? recordedBy;

  const MeetingRecording({
    required this.id,
    required this.meetingCode,
    required this.status,
    this.fileUrl,
    this.playbackUrl,
    this.thumbnailUrl,
    this.durationSeconds,
    this.fileSizeBytes,
    this.summary,
    this.startedAt,
    this.endedAt,
    this.expiresAt,
    this.meetingTitle,
    this.recordedBy,
  });

  bool get isPlayable => status == RecordingStatus.completed;

  MeetingRecording copyWith({String? summary, String? playbackUrl}) => MeetingRecording(
        id: id,
        meetingCode: meetingCode,
        status: status,
        fileUrl: fileUrl,
        playbackUrl: playbackUrl ?? this.playbackUrl,
        thumbnailUrl: thumbnailUrl,
        durationSeconds: durationSeconds,
        fileSizeBytes: fileSizeBytes,
        summary: summary ?? this.summary,
        startedAt: startedAt,
        endedAt: endedAt,
        expiresAt: expiresAt,
        meetingTitle: meetingTitle,
        recordedBy: recordedBy,
      );

  factory MeetingRecording.fromJson(Map<String, dynamic> j) {
    final meeting = _asMap(j['meeting']);
    return MeetingRecording(
      id: (j['id'] ?? '').toString(),
      meetingCode: (j['meetingCode'] ?? meeting['code'] ?? '').toString(),
      status: RecordingStatus.fromString(j['status']?.toString()),
      fileUrl: _str(j['fileUrl']),
      playbackUrl: _str(j['playbackUrl']),
      thumbnailUrl: _str(j['thumbnailUrl']),
      durationSeconds: _intOrNull(j['durationSeconds']),
      fileSizeBytes: _intOrNull(j['fileSizeBytes']),
      summary: _str(j['summary']),
      startedAt: _date(j['startedAt']),
      endedAt: _date(j['endedAt']),
      expiresAt: _date(j['expiresAt']),
      meetingTitle: _str(meeting['title']),
      recordedBy: j['recordedBy'] is Map ? RecordingUser.fromJson(_asMap(j['recordedBy'])) : null,
    );
  }
}

class RecordingPage {
  final List<MeetingRecording> items;
  final int page;
  final int totalPages;
  final int total;
  const RecordingPage({required this.items, required this.page, required this.totalPages, required this.total});

  bool get hasMore => page < totalPages;
}

class RecordingSummary {
  final String recordingId;
  final bool isCached;
  final String summary;
  const RecordingSummary({required this.recordingId, required this.isCached, required this.summary});

  factory RecordingSummary.fromJson(Map<String, dynamic> j) => RecordingSummary(
        recordingId: (j['recordingId'] ?? '').toString(),
        isCached: j['isCached'] == true,
        summary: (j['summary'] ?? '').toString(),
      );
}

class RecordingUploadTarget {
  final String uploadUrl;
  final String fileUrl;
  const RecordingUploadTarget({required this.uploadUrl, required this.fileUrl});
}
DateTime? _date(dynamic v) => DateTime.tryParse((v ?? '').toString())?.toLocal();
String? _str(dynamic v) {
  final s = v?.toString();
  if (s == null || s.isEmpty || s == 'null') return null;
  return s;
}

Map<String, dynamic> _asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

enum OfficeZone {
  warRoom('WAR_ROOM', 'The War Room'),
  openWorkspace('OPEN_WORKSPACE', 'Open Desks'),
  coffeeLounge('COFFEE_LOUNGE', 'Coffee Lounge'),
  focusPod('FOCUS_POD', 'Focus Pods');

  const OfficeZone(this.apiValue, this.title);
  final String apiValue;
  final String title;

  static OfficeZone fromString(String? v) {
    switch ((v ?? '').toUpperCase()) {
      case 'WAR_ROOM':
        return OfficeZone.warRoom;
      case 'COFFEE_LOUNGE':
        return OfficeZone.coffeeLounge;
      case 'FOCUS_POD':
        return OfficeZone.focusPod;
      default:
        return OfficeZone.openWorkspace;
    }
  }
}

enum OfficePresence {
  available('AVAILABLE', 'Available'),
  busy('BUSY', 'Busy'),
  away('AWAY', 'Away'),
  doNotDisturb('DO_NOT_DISTURB', 'Do not disturb'),
  beRightBack('BE_RIGHT_BACK', 'Be right back'),
  offline('OFFLINE', 'Offline');

  const OfficePresence(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static OfficePresence fromString(String? v) {
    switch ((v ?? '').toUpperCase()) {
      case 'BUSY':
        return OfficePresence.busy;
      case 'AWAY':
      case 'IDLE':
        return OfficePresence.away;
      case 'DO_NOT_DISTURB':
        return OfficePresence.doNotDisturb;
      case 'BE_RIGHT_BACK':
        return OfficePresence.beRightBack;
      case 'OFFLINE':
        return OfficePresence.offline;
      default:
        return OfficePresence.available;
    }
  }
}

class OfficeMember {
  final String userId;
  final String name;
  final String? avatarUrl;
  final OfficePresence presence;
  final OfficeZone zone;
  final String? deskId;
  final bool isInMeeting;
  final String? statusMessage;
  final DateTime? joinedAt;

  const OfficeMember({
    required this.userId,
    required this.name,
    this.avatarUrl,
    required this.presence,
    required this.zone,
    this.deskId,
    this.isInMeeting = false,
    this.statusMessage,
    this.joinedAt,
  });

  factory OfficeMember.fromJson(Map<String, dynamic> j) => OfficeMember(
        userId: (j['userId'] ?? j['id'] ?? '').toString(),
        name: (j['name'] ?? 'Teammate').toString(),
        avatarUrl: _str(j['avatarUrl'] ?? j['avatar']),
        presence: OfficePresence.fromString(j['presenceStatus']?.toString()),
        zone: OfficeZone.fromString(j['zoneId']?.toString()),
        deskId: _str(j['deskId']),
        isInMeeting: j['isInMeeting'] == true,
        statusMessage: _str(j['statusMessage']),
        joinedAt: _date(j['joinedOfficeAt'] ?? j['joinedAt']),
      );

  factory OfficeMember.fromZoneEvent(Map<String, dynamic> j, {OfficeMember? previous}) => OfficeMember(
        userId: (j['userId'] ?? '').toString(),
        name: (j['name'] ?? previous?.name ?? 'Teammate').toString(),
        avatarUrl: _str(j['avatarUrl']) ?? previous?.avatarUrl,
        presence: OfficePresence.fromString(j['presenceStatus']?.toString()),
        zone: OfficeZone.fromString(j['newZoneId']?.toString()),
        deskId: _str(j['deskId']),
        isInMeeting: j['isInMeeting'] == true,
        statusMessage: _str(j['statusMessage']),
        joinedAt: previous?.joinedAt,
      );
}

class OfficeDesk {
  final String deskId;
  final int deskNumber;
  final String status;
  final String? occupiedByUserId;
  final String? occupiedByUserName;
  final String? occupiedByUserAvatar;

  const OfficeDesk({
    required this.deskId,
    required this.deskNumber,
    required this.status,
    this.occupiedByUserId,
    this.occupiedByUserName,
    this.occupiedByUserAvatar,
  });

  bool get isEmpty => occupiedByUserId == null;

  OfficeDesk vacated() => OfficeDesk(deskId: deskId, deskNumber: deskNumber, status: 'EMPTY');

  OfficeDesk occupiedBy(OfficeMember m) => OfficeDesk(
        deskId: deskId,
        deskNumber: deskNumber,
        status: m.presence.apiValue,
        occupiedByUserId: m.userId,
        occupiedByUserName: m.name,
        occupiedByUserAvatar: m.avatarUrl,
      );

  factory OfficeDesk.fromJson(Map<String, dynamic> j) {
    final id = (j['deskId'] ?? '').toString();
    final number = int.tryParse('${j['deskNumber'] ?? id.replaceAll(RegExp(r'[^0-9]'), '')}') ?? 0;
    return OfficeDesk(
      deskId: id,
      deskNumber: number,
      status: (j['status'] ?? 'EMPTY').toString().toUpperCase(),
      occupiedByUserId: _str(j['occupiedByUserId']),
      occupiedByUserName: _str(j['occupiedByUserName']),
      occupiedByUserAvatar: _str(j['occupiedByUserAvatar']),
    );
  }
}

class OfficeState {
  final String teamId;
  final String? organizationId;
  final String? activeMeetingCode;
  final Map<String, OfficeMember> members;
  final List<OfficeDesk> desks;

  const OfficeState({
    required this.teamId,
    this.organizationId,
    this.activeMeetingCode,
    required this.members,
    required this.desks,
  });

  List<OfficeMember> inZone(OfficeZone zone) => members.values.where((m) => m.zone == zone).toList();

  int get totalActive => members.values.where((m) => m.presence != OfficePresence.offline).length;

  OfficeState copyWith({
    String? activeMeetingCode,
    bool clearMeeting = false,
    Map<String, OfficeMember>? members,
    List<OfficeDesk>? desks,
  }) =>
      OfficeState(
        teamId: teamId,
        organizationId: organizationId,
        activeMeetingCode: clearMeeting ? null : (activeMeetingCode ?? this.activeMeetingCode),
        members: members ?? this.members,
        desks: desks ?? this.desks,
      );

  OfficeState withMember(OfficeMember m) {
    final nextMembers = {...members, m.userId: m};
    final nextDesks = desks.map((d) {
      if (d.occupiedByUserId == m.userId && d.deskId != m.deskId) return d.vacated();
      if (d.deskId == m.deskId && m.zone == OfficeZone.openWorkspace) return d.occupiedBy(m);
      return d;
    }).toList();
    return copyWith(members: nextMembers, desks: nextDesks);
  }

  OfficeState withoutMember(String userId) {
    final nextMembers = {...members}..remove(userId);
    final nextDesks = desks.map((d) => d.occupiedByUserId == userId ? d.vacated() : d).toList();
    return copyWith(members: nextMembers, desks: nextDesks);
  }

  factory OfficeState.fromJson(Map<String, dynamic> j, {String? fallbackTeamId}) {
    final rawMembers = j['members'];
    final members = <String, OfficeMember>{};
    if (rawMembers is Map) {
      rawMembers.forEach((k, v) {
        if (v is Map) {
          final m = OfficeMember.fromJson(_asMap(v));
          members[m.userId.isEmpty ? k.toString() : m.userId] = m;
        }
      });
    } else if (rawMembers is List) {
      for (final v in rawMembers) {
        if (v is Map) {
          final m = OfficeMember.fromJson(_asMap(v));
          members[m.userId] = m;
        }
      }
    }
    final rawDesks = j['desks'];
    var desks = <OfficeDesk>[];
    if (rawDesks is List) {
      desks = rawDesks.whereType<Map>().map((e) => OfficeDesk.fromJson(_asMap(e))).toList();
    }
    if (desks.isEmpty) {
      desks = [
        for (var i = 1; i <= 12; i++) OfficeDesk(deskId: 'desk_$i', deskNumber: i, status: 'EMPTY'),
      ];
    }
    desks.sort((a, b) => a.deskNumber.compareTo(b.deskNumber));
    return OfficeState(
      teamId: (j['teamId'] ?? fallbackTeamId ?? '').toString(),
      organizationId: _str(j['organizationId']),
      activeMeetingCode: _str(j['activeMeetingCode']),
      members: members,
      desks: desks,
    );
  }
}

class OfficeKnock {
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String teamId;
  final String? message;
  final DateTime? timestamp;

  const OfficeKnock({
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    required this.teamId,
    this.message,
    this.timestamp,
  });

  factory OfficeKnock.fromJson(Map<String, dynamic> j) => OfficeKnock(
        senderId: (j['senderId'] ?? '').toString(),
        senderName: (j['senderName'] ?? 'A teammate').toString(),
        senderAvatar: _str(j['senderAvatar']),
        teamId: (j['teamId'] ?? '').toString(),
        message: _str(j['message']),
        timestamp: _date(j['timestamp']),
      );
}
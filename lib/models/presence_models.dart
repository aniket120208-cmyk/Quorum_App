import 'package:flutter/material.dart';

enum PresenceStatus {
  available('AVAILABLE', 'Available', Color(0xFF22C55E)),
  busy('BUSY', 'Busy', Color(0xFFEF4444)),
  doNotDisturb('DO_NOT_DISTURB', 'Do Not Disturb', Color(0xFFDC2626)),
  beRightBack('BE_RIGHT_BACK', 'Be Right Back', Color(0xFFF59E0B)),
  away('AWAY', 'Away', Color(0xFFF59E0B)),
  offline('OFFLINE', 'Offline', Color(0xFF6B7280));

  const PresenceStatus(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;

  static PresenceStatus parse(dynamic v) {
    final s = (v ?? '').toString().toUpperCase();
    for (final p in PresenceStatus.values) {
      if (p.value == s) return p;
    }
    return PresenceStatus.available;
  }
}

String presenceAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

class UserPresence {
  const UserPresence({
    required this.isOnline,
    required this.status,
    this.statusMessage,
    this.statusExpiresAt,
    this.lastSeen,
  });

  final bool isOnline;
  final PresenceStatus status;
  final String? statusMessage;
  final DateTime? statusExpiresAt;
  final DateTime? lastSeen;

  factory UserPresence.fromJson(Map<String, dynamic> j) {
    final online = j['isOnline'] == true;
    var status = PresenceStatus.parse(j['status']);
    if (!online) status = PresenceStatus.offline;
    final message = j['statusMessage']?.toString();
    return UserPresence(
      isOnline: online,
      status: status,
      statusMessage: (message == null || message.trim().isEmpty) ? null : message.trim(),
      statusExpiresAt: DateTime.tryParse((j['statusExpiresAt'] ?? '').toString())?.toLocal(),
      lastSeen: DateTime.tryParse((j['lastSeen'] ?? '').toString())?.toLocal(),
    );
  }

  bool get _expired => statusExpiresAt != null && statusExpiresAt!.isBefore(DateTime.now());

  PresenceStatus get effective {
    if (!isOnline) return PresenceStatus.offline;
    if (_expired && status != PresenceStatus.available) return PresenceStatus.available;
    return status;
  }

  String? get message => _expired ? null : statusMessage;

  bool get isDnd => effective == PresenceStatus.doNotDisturb;

  String get subtitle {
    final m = message;
    switch (effective) {
      case PresenceStatus.available:
        return m ?? 'Available';
      case PresenceStatus.busy:
        return m ?? 'Busy';
      case PresenceStatus.doNotDisturb:
        return m == null ? 'Do Not Disturb' : '$m (Do Not Disturb)';
      case PresenceStatus.beRightBack:
        return m ?? 'Be right back';
      case PresenceStatus.away:
        return m ?? 'Away';
      case PresenceStatus.offline:
        return lastSeen == null ? 'Offline' : 'Offline · last seen ${presenceAgo(lastSeen!)}';
    }
  }
}
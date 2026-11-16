import 'package:flutter/foundation.dart';
import 'package:quorum_app/api/auth_service.dart';
import 'package:quorum_app/api/calendar_repository.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/meeting_api.dart';
import 'package:quorum_app/api/meeting_history_store.dart';
import 'package:quorum_app/models/calendar_models.dart';
import 'package:quorum_app/models/meeting_models.dart';

class ScheduledEntry {
  final String title;
  final DateTime? start;
  final CalendarEvent? event;
  final ScopedMeeting? meeting;
  const ScheduledEntry({required this.title, required this.start, this.event, this.meeting});
}

class VideoCallController extends ChangeNotifier {
  bool _creating = false;
  bool _disposed = false;
  List<MeetingHistoryItem> _history = [];
  List<ScheduledEntry> _upcoming = [];
  VideoCallController() {
    MeetingHistoryStore.instance.revision.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (_disposed || !CurrentUser.isLoaded) return;
    _reload();
  }

  bool get creating => _creating;
  List<MeetingHistoryItem> get history => List.unmodifiable(_history);
  List<ScheduledEntry> get upcoming => List.unmodifiable(_upcoming);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> ensureUser() async {
    if (CurrentUser.isLoaded) return;
    CurrentUser.setFromProfile(await AuthService.instance.getUserProfile());
  }

  Future<void> loadHistory() async {
    if (!await _userReady()) return;
    await _reload();
    try {
      final all = await MeetingApi.instance.upcomingMeetings();
      final ended = all.where((m) => m.status == MeetingStatus.ended).take(30);
      for (final m in ended) {
        await MeetingHistoryStore.instance.add(
          CurrentUser.id,
          MeetingHistoryItem.fromScoped(m),
          onlyIfMissing: true,
        );
      }
    } catch (_) {}
  }

  Future<void> loadUpcoming() async {
    var events = <CalendarEvent>[];
    var meetings = <ScopedMeeting>[];
    try {
      events = (await CalendarRepository.instance.getUpcoming(limit: 10))
          .where((e) => e.hasMeetingLink && !e.isPast)
          .toList();
    } catch (_) {}
    try {
      meetings = (await MeetingApi.instance.upcomingMeetings()).where((m) => m.isOpen).toList();
    } catch (_) {}
    final codes = meetings.map((m) => m.code).toSet();
    final entries = <ScheduledEntry>[
      for (final m in meetings) ScheduledEntry(title: m.title, start: m.scheduledStartTime, meeting: m),
      for (final e in events)
        if (!codes.contains(MeetingApi.codeFromLink(e.meetingLink ?? '')))
          ScheduledEntry(title: e.title, start: e.startDate, event: e),
    ];
    final now = DateTime.now();
    entries.sort((a, b) {
      final aLive = a.meeting?.isActive ?? false;
      final bLive = b.meeting?.isActive ?? false;
      if (aLive != bLive) return aLive ? -1 : 1;
      final aStart = a.start ?? now;
      final bStart = b.start ?? now;
      return aStart.compareTo(bStart);
    });
    _upcoming = entries.take(8).toList();
    _notify();
  }

  Future<CreatedMeeting> createMeeting() async {
    _creating = true;
    _notify();
    try {
      return await MeetingApi.instance.createMeeting();
    } finally {
      _creating = false;
      _notify();
    }
  }

  Future<void> recordMeeting(MeetingResult result) async {
    if (!await _userReady()) return;
    await MeetingHistoryStore.instance.add(CurrentUser.id, MeetingHistoryItem.fromResult(result));
    await _reload();
  }

  Future<void> saveScheduled(ScopedMeeting meeting) async {
    if (!await _userReady()) return;
    await MeetingHistoryStore.instance.add(
      CurrentUser.id,
      MeetingHistoryItem.fromScoped(meeting),
      onlyIfMissing: true,
    );
    await _reload();
  }

  Future<void> removeMeeting(MeetingHistoryItem item) async {
    _history = _history.where((e) => e != item).toList();
    _notify();
    if (!await _userReady()) return;
    await MeetingHistoryStore.instance.remove(CurrentUser.id, item);
  }

  Future<void> restoreMeeting(MeetingHistoryItem item, int index) async {
    final list = [..._history];
    list.insert(index.clamp(0, list.length), item);
    _history = list;
    _notify();
    if (!await _userReady()) return;
    await MeetingHistoryStore.instance.restore(CurrentUser.id, item, index);
  }

  Future<bool> _userReady() async {
    try {
      await ensureUser();
    } catch (_) {
      return false;
    }
    return CurrentUser.isLoaded;
  }

  Future<void> _reload() async {
    _history = await MeetingHistoryStore.instance.load(CurrentUser.id);
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    MeetingHistoryStore.instance.revision.removeListener(_onStoreChanged);
    super.dispose();
  }
}
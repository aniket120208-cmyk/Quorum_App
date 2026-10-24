import 'package:flutter/foundation.dart';
import 'package:quorum_app/api/auth_service.dart';
import 'package:quorum_app/api/calendar_repository.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/meeting_api.dart';
import 'package:quorum_app/api/meeting_history_store.dart';
import 'package:quorum_app/models/calendar_models.dart';
import 'package:quorum_app/models/meeting_models.dart';

class VideoCallController extends ChangeNotifier {
  bool _creating = false;
  bool _disposed = false;
  List<MeetingHistoryItem> _history = [];
  List<CalendarEvent> _upcoming = [];
  bool get creating => _creating;
  List<MeetingHistoryItem> get history => List.unmodifiable(_history);
  List<CalendarEvent> get upcoming => List.unmodifiable(_upcoming);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> ensureUser() async {
    if (CurrentUser.isLoaded) return;
    CurrentUser.setFromProfile(await AuthService.instance.getUserProfile());
  }

  Future<void> loadHistory() async {
    try {
      await ensureUser();
    } catch (_) {
      return;
    }
    _history = await MeetingHistoryStore.instance.load(CurrentUser.id);
    _notify();
  }

  Future<void> loadUpcoming() async {
    try {
      final events = await CalendarRepository.instance.getUpcoming(limit: 10);
      _upcoming = events
          .where((e) => e.hasMeetingLink && !e.isPast)
          .take(5)
          .toList();
      _notify();
    } catch (_) {}
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

  void recordMeeting(MeetingResult result) {
    _history = [MeetingHistoryItem.fromResult(result), ..._history];
    _persist();
  }

  void removeMeeting(MeetingHistoryItem item) {
    _history = _history.where((e) => e != item).toList();
    _persist();
  }

  void restoreMeeting(MeetingHistoryItem item, int index) {
    final list = [..._history];
    list.insert(index.clamp(0, list.length), item);
    _history = list;
    _persist();
  }

  void _persist() {
    _notify();
    MeetingHistoryStore.instance.save(CurrentUser.id, _history);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
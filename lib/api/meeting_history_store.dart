import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quorum_app/models/meeting_models.dart';

class MeetingHistoryStore {
  MeetingHistoryStore._();
  static final MeetingHistoryStore instance = MeetingHistoryStore._();
  static const int _maxItems = 30;
  String _key(String userId) => 'meeting_history_$userId';

  Future<List<MeetingHistoryItem>> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => MeetingHistoryItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(String userId, List<MeetingHistoryItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = items.take(_maxItems).map((e) => e.toJson()).toList();
    await prefs.setString(_key(userId), jsonEncode(trimmed));
  }
}
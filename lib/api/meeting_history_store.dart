import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quorum_app/api/auth_service.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/models/meeting_models.dart';

class MeetingHistoryStore {
  MeetingHistoryStore._();
  static final MeetingHistoryStore instance = MeetingHistoryStore._();
  static const int _maxItems = 200;
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  String _key(String userId) => 'meeting_history_$userId';
  Future<void> _lock = Future<void>.value();

  Future<T> _synced<T>(Future<T> Function() action) {
    final run = _lock.then((_) => action());
    _lock = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

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
    revision.value++;
  }

  Future<void> add(String userId, MeetingHistoryItem item, {bool onlyIfMissing = false}) {
    return _synced(() async {
      final current = await load(userId);
      final exists = current.any((e) => e.code == item.code);
      if (exists && onlyIfMissing) return;
      final rest = current.where((e) => e.code != item.code).toList();
      await save(userId, [item, ...rest]);
    });
  }

  Future<void> addForCurrentUser(MeetingHistoryItem item, {bool onlyIfMissing = false}) async {
    try {
      if (!CurrentUser.isLoaded) {
        CurrentUser.setFromProfile(await AuthService.instance.getUserProfile());
      }
      if (!CurrentUser.isLoaded) return;
      await add(CurrentUser.id, item, onlyIfMissing: onlyIfMissing);
    } catch (_) {}
  }

  Future<void> remove(String userId, MeetingHistoryItem item) {
    return _synced(() async {
      final current = await load(userId);
      await save(userId, current.where((e) => !(e.code == item.code && e.timestamp == item.timestamp)).toList());
    });
  }

  Future<void> restore(String userId, MeetingHistoryItem item, int index) {
    return _synced(() async {
      final current = await load(userId);
      if (current.any((e) => e.code == item.code)) return;
      final list = [...current];
      list.insert(index.clamp(0, list.length), item);
      await save(userId, list);
    });
  }
}
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/meeting_api.dart';
import 'package:quorum_app/api/meeting_history_store.dart';
import 'package:quorum_app/app_navigator.dart';
import 'package:quorum_app/models/meeting_models.dart';
import 'package:quorum_app/screens/video_call_screen/meeting_room_screen.dart';

class MeetingLauncher {
  MeetingLauncher._();
  static Future<bool> join(String link, {String title = 'Meeting'}) async {
    final trimmed = link.trim();
    if (trimmed.isEmpty) return false;
    final nav = appNavigatorKey.currentState;
    if (MeetingApi.isQuorumLink(trimmed)) {
      final code = MeetingApi.codeFromLink(trimmed);
      if (code == null || nav == null) return false;
      await joinCode(code, title: title);
      return true;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static Future<void> joinCode(String code, {String title = 'Meeting', bool isHost = false}) async {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    final result = await nav.push<MeetingResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MeetingRoomScreen(meetingCode: code, title: title, isHostHint: isHost),
      ),
    );
    await _record(result);
  }

  static Future<void> _record(MeetingResult? result) async {
    if (result == null || !result.joined || !CurrentUser.isLoaded) return;
    try {
      final store = MeetingHistoryStore.instance;
      final current = await store.load(CurrentUser.id);
      await store.save(
        CurrentUser.id,
        [MeetingHistoryItem.fromResult(result), ...current],
      );
    } catch (_) {}
  }
}
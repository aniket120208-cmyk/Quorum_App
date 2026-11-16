import 'package:flutter/material.dart';
import 'package:quorum_app/api/notification_router.dart';
import 'package:quorum_app/app_navigator.dart';
import 'package:quorum_app/models/notification_models.dart';
import 'package:quorum_app/screens/project_screen/accept_project_invite_screen.dart';
import 'package:quorum_app/screens/video_call_screen/meeting_launcher.dart';

class DeepLinkRouter {
  DeepLinkRouter._();

  static const Set<String> _hosts = {'newquorum.me', 'www.newquorum.me', 'app.newquorum.me', 'quorum.me', 'www.quorum.me'};
  static const String _scheme = 'quorum';
  static bool _meetingOpen = false;

  static bool isQuorumUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == _scheme) return true;
    if (scheme != 'https' && scheme != 'http') return false;
    return _hosts.contains(uri.host.toLowerCase());
  }

  static List<String> _segments(Uri uri) {
    final parts = <String>[
      if (uri.scheme.toLowerCase() == _scheme && uri.host.isNotEmpty) uri.host,
      ...uri.pathSegments,
    ];
    return parts.where((s) => s.isNotEmpty).toList();
  }

  static String? _tokenAfter(List<String> segments, Uri uri, Set<String> markers) {
    for (var i = 0; i < segments.length; i++) {
      if (markers.contains(segments[i].toLowerCase()) && i + 1 < segments.length) {
        return segments.last;
      }
    }
    final q = uri.queryParameters['token'] ?? uri.queryParameters['code'];
    return (q == null || q.isEmpty) ? null : q;
  }

  static void _snack(String message) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static Future<bool> tryOpen(Uri uri) async {
    if (!isQuorumUri(uri)) return false;
    return open(uri);
  }

  static Future<bool> open(Uri uri) async {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return false;
    final segments = _segments(uri);
    final lower = segments.map((s) => s.toLowerCase()).toList();
    if (lower.isEmpty) return false;

    if (lower.contains('meet') || lower.contains('meeting') || lower.contains('meetings')) {
      final code = _tokenAfter(segments, uri, {'meet', 'meeting', 'meetings'});
      if (code == null) return false;
      if (_meetingOpen) {
        _snack('Finish your current meeting before joining another');
        return true;
      }
      _meetingOpen = true;
      try {
        await MeetingLauncher.joinCode(code.toLowerCase());
      } finally {
        _meetingOpen = false;
      }
      return true;
    }

    if (lower.contains('project') || lower.contains('projects') || lower.contains('project-invite')) {
      final token = _tokenAfter(segments, uri, {'invite', 'invites', 'accept-invite', 'join', 'project-invite'}) ?? segments.last;
      await nav.push(MaterialPageRoute(builder: (_) => AcceptProjectInviteScreen(initialToken: token)));
      return true;
    }

    if (lower.contains('community') || lower.contains('communities')) {
      final token = _tokenAfter(segments, uri, {'join', 'invite', 'invites'});
      if (token == null) return false;
      await NotificationRouter.open(NotificationType.communityInvite, {'token': token});
      return true;
    }

    if (lower.contains('join') || lower.contains('invite')) {
      final token = _tokenAfter(segments, uri, {'join', 'invite'});
      if (token == null) return false;
      await NotificationRouter.open(NotificationType.orgInvite, {'token': token});
      return true;
    }

    return false;
  }
}
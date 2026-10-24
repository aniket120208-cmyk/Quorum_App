import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/chat_repository.dart';
import 'package:quorum_app/api/community_repository.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/app_navigator.dart';
import 'package:quorum_app/models/notification_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_room_screen.dart';
import 'package:quorum_app/screens/community_screen/communtiy_details_screen.dart';
import 'package:quorum_app/screens/community_screen/post_comments_screen.dart';
import 'package:quorum_app/screens/organization_screen/join_organization_screen.dart';
import 'package:quorum_app/screens/organization_screen/organization_detail_screen.dart';
import 'package:quorum_app/screens/home_screen/calendar_screen.dart';
import 'package:quorum_app/screens/video_call_screen/meeting_launcher.dart';
import 'package:quorum_app/screens/video_call_screen/meeting_room_screen.dart';

class NotificationRouter {
  NotificationRouter._();

  static Future<void> openItem(NotificationItem n) => open(n.type, n.data);

  static void _snack(String message) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static Future<void> open(NotificationType type, Map<String, dynamic> data) async {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    String s(String key) => (data[key] ?? '').toString();
    try {
      switch (type) {
        case NotificationType.orgInvite:
          nav.push(MaterialPageRoute(
            builder: (_) => JoinOrganizationScreen(initialToken: s('token').isEmpty ? null : s('token')),
          ));
        case NotificationType.teamInvite:
          if (s('organizationId').isEmpty) return;
          final org = await OrganizationRepository.instance.detail(
            s('organizationId'),
            role: s('role').isEmpty ? 'MEMBER' : s('role').toUpperCase(),
          );
          nav.push(MaterialPageRoute(builder: (_) => OrganizationDetailScreen(organization: org)));
        case NotificationType.communityPostComment:
          await _openCommunity(nav, s('communityId'), postId: s('postId'));
        case NotificationType.communityInvite:
          if (s('inviteId').isNotEmpty) {
            await _respondToInvite(nav, s('inviteId'), s('communityId'), s('communityName'));
          } else if (s('token').isNotEmpty) {
            await _joinCommunityInvite(nav, s('token'));
          } else {
            await _openCommunity(nav, s('communityId'));
          }
        case NotificationType.meetingStarted:
          final code = s('meetingCode').isNotEmpty ? s('meetingCode') : s('meetingId');
          if (code.isEmpty) return;
          nav.push(MaterialPageRoute(builder: (_) => MeetingRoomScreen(meetingCode: code)));
        case NotificationType.directMessage:
          if (s('conversationId').isEmpty) return;
          final conv = await ChatRepository.instance.conversationById(s('conversationId'), CurrentUser.id);
          if (conv == null) {
            _snack('Conversation not found.');
            return;
          }
          nav.push(MaterialPageRoute(
            builder: (_) => ChatRoomScreen(
              conversation: conv,
              currentUserId: CurrentUser.id,
              currentUserName: CurrentUser.name,
            ),
          ));
        case NotificationType.eventReminder:
          final link = s('meetingLink');
          final opened = link.isNotEmpty &&
              await MeetingLauncher.join(
                link,
                title: s('title').isEmpty ? 'Meeting' : s('title'),
              );
          if (!opened) {
            nav.push(MaterialPageRoute(builder: (_) => const CalendarScreen()));
          }
        case NotificationType.system:
          nav.popUntil((r) => r.isFirst);
      }
    } catch (e) {
      _snack(errorText(e));
    }
  }

  static Future<void> _openCommunity(NavigatorState nav, String communityId, {String postId = ''}) async {
    if (communityId.isEmpty) return;
    final repo = CommunityRepository.instance;
    final detail = await repo.detail(communityId);
    final page = postId.isEmpty ? null : await repo.posts(communityId);
    final matches = page?.items.where((p) => p.id == postId).toList() ?? const [];
    nav.push(MaterialPageRoute(
      builder: (_) => CommunityDetailScreen(
        communityId: communityId,
        initialName: detail.name,
        initialRole: detail.role,
      ),
    ));
    if (matches.isNotEmpty) {
      nav.push(MaterialPageRoute(
        builder: (_) => PostCommentsScreen(
          post: matches.first,
          myId: CurrentUser.id,
          role: detail.role,
          onCountChanged: (_) {},
        ),
      ));
    }
  }

  static Future<void> _respondToInvite(
    NavigatorState nav,
    String inviteId,
    String communityId,
    String communityName,
  ) async {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    final repo = CommunityRepository.instance;
    final label = communityName.isEmpty ? 'this community' : communityName;
    final choice = await showDialog<String>(
      context: ctx,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF14151F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Join $label?', style: const TextStyle(color: Colors.white)),
        content: const Text(
          'You have been invited to join this community.',
          style: TextStyle(color: Color(0xFF9EA3AE)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'later'),
            child: const Text('Later', style: TextStyle(color: Color(0xFF9EA3AE))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'decline'),
            child: const Text('Decline', style: TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'accept'),
            child: const Text('Accept', style: TextStyle(color: Color(0xFF7F77FF))),
          ),
        ],
      ),
    );
    if (choice == 'decline') {
      await repo.declineInvite(inviteId);
      _snack('Invitation declined.');
      return;
    }
    if (choice != 'accept') return;
    await repo.acceptInvite(inviteId);
    if (communityId.isEmpty) {
      _snack('You joined $label.');
      return;
    }
    await _openCommunity(nav, communityId);
  }

  static Future<void> _joinCommunityInvite(NavigatorState nav, String token) async {
    final repo = CommunityRepository.instance;
    final preview = await repo.previewInvite(token);
    if (!preview.valid) {
      _snack('This invitation is no longer valid.');
      return;
    }
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF14151F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Join ${preview.communityName}?', style: const TextStyle(color: Colors.white)),
        content: Text(
          '${preview.memberCount} members${preview.inviterName.isEmpty ? '' : ' · invited by ${preview.inviterName}'}',
          style: const TextStyle(color: Color(0xFF9EA3AE)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF9EA3AE))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Join', style: TextStyle(color: Color(0xFF7F77FF))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final joined = await repo.joinInvite(token);
    nav.push(MaterialPageRoute(
      builder: (_) => CommunityDetailScreen(
        communityId: joined.id,
        initialName: joined.name,
        initialRole: joined.role,
      ),
    ));
  }
}
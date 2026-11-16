import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/auth_service.dart';
import 'package:quorum_app/api/chat_repository.dart';
import 'package:quorum_app/api/community_repository.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/app_navigator.dart';
import 'package:quorum_app/models/notification_models.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_room_screen.dart';
import 'package:quorum_app/screens/community_screen/community_join_requests_screen.dart';
import 'package:quorum_app/screens/community_screen/communtiy_details_screen.dart';
import 'package:quorum_app/screens/community_screen/post_comments_screen.dart';
import 'package:quorum_app/screens/organization_screen/join_organization_screen.dart';
import 'package:quorum_app/screens/organization_screen/organization_detail_screen.dart';
import 'package:quorum_app/screens/organization_screen/team_chat_screen.dart';
import 'package:quorum_app/screens/home_screen/calendar_screen.dart';
import 'package:quorum_app/screens/video_call_screen/meeting_launcher.dart';

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

  static String _camel(String key) {
    if (!key.contains('_')) return key;
    final parts = key.split('_').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return key;
    return parts.first + parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
  }

  static Map<String, dynamic> normalizePayload(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    void absorb(Map source) {
      final nested = <Map>[];
      source.forEach((k, v) {
        final key = _camel(k.toString());
        dynamic value = v;
        if (value is String) {
          final t = value.trim();
          if ((key == 'data' || key == 'payload' || key == 'metadata') && t.startsWith('{')) {
            try {
              final decoded = jsonDecode(t);
              if (decoded is Map) value = decoded;
            } catch (_) {}
          }
        }
        if (value is Map && (key == 'data' || key == 'payload' || key == 'metadata')) {
          nested.add(value);
          return;
        }
        if (value == null) return;
        final existing = out[key];
        if (existing == null || existing.toString().isEmpty) out[key] = value;
      });
      for (final n in nested) {
        absorb(n);
      }
    }

    absorb(raw);
    return out;
  }

  static NotificationType? resolveType(Map<String, dynamic> data) {
    String s(String key) => (data[key] ?? '').toString();
    final raw = (s('type').isNotEmpty ? s('type') : (s('notificationType').isNotEmpty ? s('notificationType') : s('event')))
        .trim()
        .toUpperCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    for (final t in NotificationType.values) {
      if (t.value == raw) return t;
    }
    if (raw.contains('MESSAGE') || raw.contains('CHAT') || raw == 'DM' || raw.contains('MENTION')) {
      return NotificationType.directMessage;
    }
    if (s('conversationId').isNotEmpty || s('teamId').isNotEmpty) return NotificationType.directMessage;
    if (s('meetingCode').isNotEmpty || s('meetingId').isNotEmpty) return NotificationType.meetingStarted;
    if (s('communityId').isNotEmpty) {
      if (s('postId').isNotEmpty) return NotificationType.communityPostComment;
      if (s('inviteId').isNotEmpty || s('token').isNotEmpty) return NotificationType.communityInvite;
      return NotificationType.communityJoinAccepted;
    }
    if (s('organizationId').isNotEmpty) {
      return s('token').isNotEmpty ? NotificationType.orgInvite : NotificationType.orgFeedPost;
    }
    if (s('meetingLink').isNotEmpty) return NotificationType.eventReminder;
    return null;
  }

  static Future<bool> _waitForNavigator() async {
    for (var i = 0; i < 30; i++) {
      if (appNavigatorKey.currentState != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  static Future<void> _ensureUser() async {
    if (CurrentUser.isLoaded) return;
    try {
      CurrentUser.setFromProfile(await AuthService.instance.getUserProfile());
    } catch (_) {}
  }

  static Future<void> openPayload(Map<String, dynamic> raw) async {
    final data = normalizePayload(raw);
    final type = resolveType(data);
    if (type == null) return;
    await open(type, data);
  }

  static Future<void> open(NotificationType type, Map<String, dynamic> input) async {
    if (!await _waitForNavigator()) return;
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    final data = normalizePayload(input);
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
          await _ensureUser();
          await _openCommunity(nav, s('communityId'), postId: s('postId'));
        case NotificationType.communityJoinRequest:
          await _openJoinRequests(nav, s('communityId'), s('communityName'));
        case NotificationType.communityJoinAccepted:
          await _openCommunity(nav, s('communityId'));
        case NotificationType.communityJoinRejected:
          final reason = s('reason');
          final name = s('communityName');
          _snack(
            reason.isNotEmpty
                ? 'Your join request was declined: $reason'
                : 'Your request to join ${name.isEmpty ? 'the community' : name} was declined.',
          );
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
          await MeetingLauncher.joinCode(code);
        case NotificationType.directMessage:
          await _ensureUser();
          if (s('teamId').isNotEmpty) {
            if (await _openTeamChat(nav, s('organizationId'), teamId: s('teamId'))) return;
          }
          var conversationId = s('conversationId');
          if (conversationId.isEmpty) {
            final peer = s('senderId').isNotEmpty ? s('senderId') : s('actorId');
            if (peer.isEmpty || peer == CurrentUser.id) return;
            conversationId = await ChatRepository.instance.startDm(peer);
          }
          final conv = await ChatRepository.instance.conversationById(conversationId, CurrentUser.id);
          if (conv == null) {
            if (await _openTeamChat(nav, s('organizationId'), conversationId: conversationId)) return;
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
        case NotificationType.orgFeedPost:
        case NotificationType.orgFeedComment:
          if (s('organizationId').isEmpty) return;
          final feedOrg = await OrganizationRepository.instance.detail(s('organizationId'), role: 'MEMBER');
          nav.push(MaterialPageRoute(
            builder: (_) => OrganizationDetailScreen(organization: feedOrg, initialTab: 2),
          ));
        case NotificationType.system:
          nav.popUntil((r) => r.isFirst);
      }
    } catch (e) {
      _snack(errorText(e));
    }
  }

  static Future<bool> _openTeamChat(
    NavigatorState nav,
    String organizationId, {
    String teamId = '',
    String conversationId = '',
  }) async {
    final repo = OrganizationRepository.instance;
    final orgIds = <String>[];
    if (organizationId.isNotEmpty) {
      orgIds.add(organizationId);
    } else {
      final orgs = await repo.organizations();
      orgIds.addAll(orgs.map((o) => o.id));
    }
    for (final orgId in orgIds) {
      final teams = await repo.teams(orgId);
      OrgTeam? match;
      for (final t in teams) {
        if (teamId.isNotEmpty) {
          if (t.id == teamId) match = t;
        } else if (conversationId.isNotEmpty) {
          try {
            final history = await repo.teamMessages(orgId, t.id);
            if (history.conversationId == conversationId) match = t;
          } catch (_) {}
        }
        if (match != null) break;
      }
      if (match == null) continue;
      final org = await repo.detail(orgId, role: 'MEMBER');
      final members = await repo.members(orgId);
      nav.push(MaterialPageRoute(
        builder: (_) => TeamChatScreen(organization: org, team: match!, members: members),
      ));
      return true;
    }
    return false;
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

  static Future<void> _openJoinRequests(NavigatorState nav, String communityId, String communityName) async {
    if (communityId.isEmpty) return;
    var name = communityName;
    if (name.isEmpty) {
      name = (await CommunityRepository.instance.detail(communityId)).name;
    }
    nav.push(MaterialPageRoute(
      builder: (_) => CommunityJoinRequestsScreen(communityId: communityId, communityName: name),
    ));
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
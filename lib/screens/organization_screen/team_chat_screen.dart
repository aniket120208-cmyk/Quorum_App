import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_room_screen.dart';
import 'package:quorum_app/screens/chat_screen/team_chat_context.dart';
import 'organization_widgets.dart';

class TeamChatScreen extends StatefulWidget {
  const TeamChatScreen({
    super.key,
    required this.organization,
    required this.team,
    this.members = const [],
  });

  final Organization organization;
  final OrgTeam team;
  final List<OrgMember> members;

  @override
  State<TeamChatScreen> createState() => _TeamChatScreenState();
}

class _TeamChatScreenState extends State<TeamChatScreen> {
  final _repo = OrganizationRepository.instance;
  Conversation? _conversation;
  TeamChatContext? _context;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final history = await _repo.teamMessages(widget.organization.id, widget.team.id);
      if (history.conversationId.isEmpty) throw ApiException('Team chat is not available yet');
      TeamConversations.ids.add(history.conversationId);
      var people = widget.members;
      try {
        final fetched = await _repo.teamMembers(widget.organization.id, widget.team.id);
        if (fetched.isNotEmpty) people = fetched;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _context = TeamChatContext(organization: widget.organization, team: widget.team, members: people);
        _conversation = Conversation(
          id: history.conversationId,
          isTeam: true,
          isGroup: true,
          groupTitle: widget.team.name,
          updatedAt: DateTime.now(),
          members: [
            for (final m in people)
              ChatUser(id: m.userId, name: m.name, email: m.email, avatarUrl: m.avatar, role: m.teamDisplayRole),
          ],
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversation = _conversation;
    final team = _context;
    if (conversation != null && team != null) {
      return ChatRoomScreen(
        key: ValueKey(conversation.id),
        conversation: conversation,
        currentUserId: CurrentUser.id,
        currentUserName: CurrentUser.name,
        team: team,
      );
    }
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(widget.team.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator(color: orgTeal)
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: orgMuted, size: 42),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted)),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Retry', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
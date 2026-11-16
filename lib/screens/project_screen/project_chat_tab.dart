import 'package:flutter/material.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'package:quorum_app/models/project_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_room_screen.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';

class ProjectChatTab extends StatefulWidget {
  const ProjectChatTab({
    super.key,
    required this.project,
    required this.active,
    required this.onRetry,
  });

  final Project project;
  final bool active;
  final Future<void> Function() onRetry;

  @override
  State<ProjectChatTab> createState() => _ProjectChatTabState();
}

class _ProjectChatTabState extends State<ProjectChatTab>
    with AutomaticKeepAliveClientMixin {
  bool _started = false;

  @override
  bool get wantKeepAlive => _started;

  Conversation _conversation() {
    final project = widget.project;

    return Conversation(
      id: project.conversationId!,
      isTeam: true,
      isGroup: true,
      groupTitle: project.name,
      updatedAt: DateTime.now(),
      members: [
        for (final m in project.members)
          ChatUser(
            id: m.user.id,
            name: m.user.name,
            email: m.user.email,
            avatarUrl: m.user.avatar,
            role: m.role.label,
          ),
      ],
    );
  }

  Future<void> _showInfo(BuildContext context, List<ChatUser> people) {
    final project = widget.project;

    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 18),
              Text(
                project.name,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${people.length} ${people.length == 1 ? 'member' : 'members'}'
                '${project.organization == null ? '' : ' · ${project.organization!.name}'}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 8),
              const Divider(
                color: AppColors.surfaceBorder,
                height: 1,
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final u in people)
                      ListTile(
                        leading: ChatAvatar(
                          name: u.name,
                          imageUrl: u.avatarUrl,
                          radius: 20,
                          userId: u.id,
                        ),
                        title: Text(
                          u.name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        subtitle: u.email == null
                            ? null
                            : Text(
                                u.email!,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                        trailing: u.role == null
                            ? null
                            : Text(
                                u.role!,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11.5,
                                ),
                              ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.active && !_started) {
      _started = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) updateKeepAlive();
      });
    }

    final id = widget.project.conversationId;

    if (id == null || id.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline_rounded,
              color: orgMuted,
              size: 42,
            ),
            const SizedBox(height: 12),
            const Text(
              'Project chat is not available yet',
              style: TextStyle(color: orgMuted),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: widget.onRetry,
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!_started) {
      return const SizedBox.shrink();
    }

    return ChatRoomScreen(
      key: ValueKey('project_chat_$id'),
      conversation: _conversation(),
      currentUserId: CurrentUser.id,
      currentUserName: CurrentUser.name,
      embedded: true,
      showGroupAvatar: true,
      onInfo: _showInfo,
    );
  }
}
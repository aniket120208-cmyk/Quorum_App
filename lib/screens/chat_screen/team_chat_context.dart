import 'package:flutter/material.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/screens/github_screen/team_github_screen.dart';
import 'package:quorum_app/screens/jira_screen/team_jira_board_screen.dart';
import 'package:quorum_app/screens/meetings_screen/meetings_list_screen.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'package:quorum_app/screens/profile_screen/user_profile_screen.dart';
import 'chat_widgets.dart';
import 'package:quorum_app/widgets/presence_widgets.dart';

class TeamChatContext {
  const TeamChatContext({required this.organization, required this.team, required this.members});
  final Organization organization;
  final OrgTeam team;
  final List<OrgMember> members;

  bool get isLead => orgCanInvite(organization.role);

  void openMeetings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MeetingsListScreen.team(organization: organization, team: team)),
    );
  }

  void openJira(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TeamJiraBoardScreen(organization: organization, team: team)),
    );
  }

  void openGithub(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TeamGithubScreen(organization: organization, team: team)),
    );
  }

  Future<void> openInfo(BuildContext context, List<ChatUser> people) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 18),
              ChatAvatar(name: team.name, isGroup: true, radius: 36),
              const SizedBox(height: 10),
              Text(
                team.name,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 19, fontWeight: FontWeight.w700),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${people.length} ${people.length == 1 ? 'member' : 'members'} · ${organization.name}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                  const SizedBox(width: 8),
                  PresenceCountPill(userIds: [for (final u in people) u.id]),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(color: AppColors.surfaceBorder, height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final u in people)
                      ListTile(
                        leading: ChatAvatar(name: u.name, imageUrl: u.avatarUrl, radius: 20, userId: u.id),
                        title: Text(u.name, style: const TextStyle(color: AppColors.textPrimary)),
                        subtitle: PresenceLine(
                          userId: u.id,
                          ringColor: AppColors.surface,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        trailing: u.role == null
                            ? null
                            : Text(
                                orgRoleLabel(u.role!),
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                              ),
                        onTap: () => openUserProfile(
                          sheetContext,
                          userId: u.id,
                          name: u.name,
                          email: u.email,
                          avatarUrl: u.avatarUrl,
                          role: u.role,
                          roleLabel: 'Team role',
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
}
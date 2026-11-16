import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/widgets/id_dialog.dart';
import 'package:quorum_app/screens/office_screen/virtual_office_screen.dart';
import 'package:quorum_app/screens/project_screen/projects_list_screen.dart';
import 'package:quorum_app/screens/profile_screen/user_profile_screen.dart';
import 'org_feed_tab.dart';
import 'org_ownership_sheets.dart';
import 'organization_sheets.dart';
import 'organization_widgets.dart';
import 'package:quorum_app/widgets/presence_widgets.dart';
import 'my_tasks_screen.dart';
import 'team_chat_screen.dart';
import 'team_tasks_screen.dart';
import 'organization_profile_screen.dart';
import 'organization_settings_screen.dart';
import 'package:quorum_app/screens/jira_screen/jira_settings_screen.dart';
import 'package:quorum_app/screens/jira_screen/team_jira_board_screen.dart';
import 'package:quorum_app/screens/github_screen/team_github_screen.dart';
import 'package:quorum_app/screens/meetings_screen/meetings_list_screen.dart';
import 'package:quorum_app/screens/whiteboard_screen/whiteboard_list_screen.dart';
import 'package:quorum_app/screens/document_screen/document_list_screen.dart';
import 'package:quorum_app/models/document_models.dart';

class OrganizationDetailScreen extends StatefulWidget {
  const OrganizationDetailScreen({super.key, required this.organization, this.initialTab = 0});
  final Organization organization;
  final int initialTab;

  @override
  State<OrganizationDetailScreen> createState() => _OrganizationDetailScreenState();
}

class _OrganizationDetailScreenState extends State<OrganizationDetailScreen> {
  final _repo = OrganizationRepository.instance;
  final _memberSearch = TextEditingController();
  String _memberQuery = '';
  late Organization _org = widget.organization;
  List<OrgMember> _members = const [];
  List<OrgTeam> _teams = const [];
  bool _loading = true;
  String? _error;
  Timer? _poller;
  bool _fetching = false;
  bool _queued = false;

  @override
  void initState() {
    super.initState();
    _load();
    _poller = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_loading) _load();
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    _memberSearch.dispose();
    super.dispose();
  }

  Future<List<OrgTeam>> _teamsWithCounts(List<OrgTeam> teams) {
    return Future.wait(teams.map((team) async {
      try {
        final people = await _repo.teamMembers(_org.id, team.id);
        final joined = people.any((m) => m.userId.isNotEmpty && m.userId == CurrentUser.id);
        return team.copyWith(membersCount: people.length, isMember: joined);
      } catch (_) {
        return team;
      }
    }));
  }

  Future<void> _load() async {
    if (_fetching) {
      _queued = true;
      return;
    }
    _fetching = true;
    try {
      final results = await Future.wait<Object>([
        _repo.detail(_org.id, role: _org.role),
        _repo.members(_org.id),
        _repo.teams(_org.id),
      ]);
      if (!mounted) return;
      var org = results[0] as Organization;
      final members = results[1] as List<OrgMember>;
      final teams = await _teamsWithCounts(results[2] as List<OrgTeam>);
      if (!mounted) return;
      final mine = members.where((m) => m.userId.isNotEmpty && m.userId == CurrentUser.id);
      if (mine.isNotEmpty) org = org.copyWith(role: mine.first.role);
      org = org.copyWith(membersCount: members.length, teamsCount: teams.length);
      setState(() {
        _org = org;
        _members = members;
        _teams = teams;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.statusCode == 404) {
        _poller?.cancel();
        if (ModalRoute.of(context)?.isCurrent ?? false) {
          orgToast(context, e.message, error: true);
          Navigator.pop(context, true);
        }
        return;
      }
      setState(() {
        _loading = false;
        if (_members.isEmpty && _teams.isEmpty) _error = errorText(e);
      });
    } finally {
      _fetching = false;
      if (_queued && mounted) {
        _queued = false;
        _load();
      }
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    try {
      await action();
      await _load();
      if (mounted) orgToast(context, success);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _edit() async {
    final saved = await showOrgSheet<bool>(context, EditOrganizationSheet(organization: _org));
    if (saved == true) {
      await _load();
      if (mounted) orgToast(context, 'Organization updated');
    }
  }

  Future<void> _editTeam(OrgTeam team) async {
    final saved = await showOrgSheet<bool>(
      context,
      EditTeamSheet(organizationId: _org.id, team: team),
    );
    if (saved == true) {
      await _load();
      if (mounted) orgToast(context, 'Team updated');
    }
  }

  Future<void> _createTeam() async {
    final created = await showOrgSheet<bool>(context, CreateTeamSheet(organizationId: _org.id));
    if (created == true) {
      await _load();
      if (mounted) orgToast(context, 'Team created');
    }
  }

  Future<void> _openChat(OrgTeam team) async {
    if (!team.isMember) {
      orgToast(context, 'Only members of this team can open its chat', error: true);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeamChatScreen(
          organization: _org,
          team: team,
          members: _members,
        ),
      ),
    );
  }

  Future<void> _openTasks(OrgTeam team) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeamTasksScreen(organization: _org, team: team),
      ),
    );
  }

  Future<void> _openOffice(OrgTeam team) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VirtualOfficeScreen(organization: _org, teams: _teams, initialTeam: team),
      ),
    );
  }

  Future<void> _openTeamJira(OrgTeam team) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeamJiraBoardScreen(organization: _org, team: team),
      ),
    );
  }

  Future<void> _openTeamGithub(OrgTeam team) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeamGithubScreen(organization: _org, team: team),
      ),
    );
  }

  Future<void> _transferLeadAndLeave(OrgTeam team, List<OrgMember> people, {String? prompt}) async {
    final message = await showOrgSheet<String>(
      context,
      TransferLeadSheet(organization: _org, team: team, members: people, prompt: prompt),
    );
    if (message == null || !mounted) return;
    await _load();
    if (mounted) orgToast(context, message);
  }

  Future<void> _leaveTeam(OrgTeam team) async {
    try {
      final people = await _repo.teamMembers(_org.id, team.id);
      if (!mounted) return;
      final mine = people.where((m) => m.userId == CurrentUser.id);
      if (mine.isEmpty) {
        orgToast(context, 'You are not a member of ${team.name}', error: true);
        return;
      }
      final leads = people.where((m) => m.isTeamLead).length;
      if (mine.first.isTeamLead && leads <= 1) {
        await _transferLeadAndLeave(team, people);
        return;
      }
      final ok = await orgConfirm(
        context,
        title: 'Leave team',
        body: 'Leave ${team.name}? You will lose access to its chat and tasks.',
        action: 'Leave',
      );
      if (!ok || !mounted) return;
      try {
        final message = await _repo.leaveTeam(_org.id, team.id);
        await _load();
        if (mounted) orgToast(context, message);
      } on ApiException catch (e) {
        if (e.statusCode == 400 && e.message.toLowerCase().contains('sole')) {
          if (!mounted) return;
          await _transferLeadAndLeave(
            team,
            people,
            prompt: 'You are the sole team head of this team. Please select a successor before leaving.',
          );
          return;
        }
        rethrow;
      }
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OrganizationProfileScreen(organization: _org)),
    );
  }

  Future<void> _openProjects() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectsListScreen(organization: _org),
      ),
    );
  }

  Future<void> _openMyTasks() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyTasksScreen(organization: _org),
      ),
    );
  }

  Future<void> _openSettings() async {
    _poller?.cancel();
    final exited = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OrganizationSettingsScreen(organization: _org),
      ),
    );
    if (!mounted) return;
    if (exited == true) {
      Navigator.pop(context, true);
      return;
    }
    _poller = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_loading) _load();
    });
    _load();
  }

  Future<void> _openMeetings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeetingsListScreen.organization(organization: _org),
      ),
    );
  }

  Future<void> _openJira() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JiraSettingsScreen(organization: _org),
      ),
    );
  }

  Future<void> _openDocuments() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentListScreen(
          title: '${_org.name} documents',
          scope: DocumentScope.organization,
          organizationId: _org.id,
        ),
      ),
    );
  }

  Future<void> _openWhiteboards() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WhiteboardListScreen(organization: _org),
      ),
    );
  }

  Future<void> _addToTeam(OrgTeam team) async {
    var joinedIds = <String>{};
    try {
      final current = await _repo.teamMembers(_org.id, team.id);
      joinedIds = {for (final m in current) m.userId};
    } catch (_) {}
    if (!mounted) return;
    final picked = await showOrgSheet<TeamMemberSelection>(
      context,
      AddTeamMemberSheet(title: 'Add to ${team.name}', members: _members, joinedIds: joinedIds),
    );
    if (picked == null) return;
    await _run(
      () => _repo.addTeamMember(_org.id, team.id, picked.member.userId, teamRole: picked.teamRole),
      '${picked.member.name} added to ${team.name}',
    );
  }

  Future<void> _changeRole(OrgMember member, String role) {
    return _run(
      () => _repo.updateMemberRole(_org.id, member.userId, role),
      '${member.name} is now ${orgRoleLabel(role)}',
    );
  }

  Future<void> _removeMember(OrgMember member) async {
    final ok = await orgConfirm(
      context,
      title: 'Remove member',
      body: 'Remove ${member.name} from ${_org.name}?',
      action: 'Remove',
    );
    if (!ok) return;
    await _run(() => _repo.removeMember(_org.id, member.userId), '${member.name} removed');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        foregroundColor: Colors.white,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _openProfile,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                OrgAvatar(name: _org.name, logo: _org.logo, size: 36, circular: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _org.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (!_loading && _error == null && orgIsAdmin(_org.role))
            IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
          if (!_loading && _error == null)
            IconButton(
              tooltip: 'Organization settings',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: orgTeal))
          : _error != null
              ? _errorView()
              : DefaultTabController(
                  length: 3,
                  initialIndex: widget.initialTab.clamp(0, 2),
                  child: Column(
                    children: [
                      _header(),
                      TabBar(
                        indicatorColor: orgTeal,
                        labelColor: Colors.white,
                        unselectedLabelColor: orgMuted,
                        dividerColor: orgBorder,
                        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                        tabs: [
                          Tab(text: 'Members (${_members.length})'),
                          Tab(text: 'Teams (${_teams.length})'),
                          const Tab(text: 'Feed'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _membersTab(),
                            _teamsTab(),
                            OrgFeedTab(organization: _org, members: _members, teams: _teams),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: orgMuted, size: 42),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _load();
              },
              child: const Text('Retry', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Row(
            children: [
              _quickAction(Icons.task_alt_rounded, 'My tasks', _openMyTasks),
              const SizedBox(width: 10),
              _quickAction(Icons.handshake_outlined, 'Projects & collaborators', _openProjects),
              const SizedBox(width: 10),
              _quickAction(Icons.draw_rounded, 'Whiteboards', _openWhiteboards),
              const SizedBox(width: 10),
              _quickAction(Icons.description_outlined, 'Documents', _openDocuments),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickAction(IconData icon, String tooltip, VoidCallback onTap) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: orgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: orgBorder),
            ),
            child: Icon(icon, size: 20, color: orgTeal),
          ),
        ),
      ),
    );
  }

  Widget _emptyList(String text) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 60),
        Center(child: Text(text, style: const TextStyle(color: orgMuted))),
      ],
    );
  }

  List<OrgMember> get _filteredMembers {
    final q = _memberQuery.trim().toLowerCase();
    final base = q.isEmpty
        ? [..._members]
        : _members
            .where((m) =>
                m.name.toLowerCase().contains(q) ||
                (m.email ?? '').toLowerCase().contains(q) ||
                orgRoleLabel(m.role).toLowerCase().contains(q))
            .toList();
    final ranked = [for (var i = 0; i < base.length; i++) (i, base[i])]
      ..sort((a, b) {
        final byRole = orgRoleRank(a.$2.role).compareTo(orgRoleRank(b.$2.role));
        return byRole != 0 ? byRole : a.$1.compareTo(b.$1);
      });
    return [for (final e in ranked) e.$2];
  }

  Widget _memberSearchField() {
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: TextField(
        controller: _memberSearch,
        onChanged: (v) => setState(() => _memberQuery = v),
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        cursorColor: orgTeal,
        decoration: InputDecoration(
          hintText: 'Search members',
          hintStyle: const TextStyle(color: Color(0xFF5A5E6B)),
          prefixIcon: const Icon(Icons.search_rounded, color: orgMuted, size: 20),
          suffixIcon: _memberQuery.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _memberSearch.clear();
                    setState(() => _memberQuery = '');
                  },
                  icon: const Icon(Icons.close_rounded, color: orgMuted, size: 18),
                ),
          filled: true,
          fillColor: orgField,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: border(orgBorder),
          enabledBorder: border(orgBorder),
          focusedBorder: border(orgTeal),
        ),
      ),
    );
  }

  Widget _membersTab() {
    final list = _filteredMembers;
    return Column(
      children: [
        _memberSearchField(),
        Expanded(
          child: RefreshIndicator(
            color: orgTeal,
            backgroundColor: orgCard,
            onRefresh: _load,
            child: list.isEmpty
                ? _emptyList(_members.isEmpty ? 'No members yet' : 'No members match your search')
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    itemCount: list.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _memberTile(list[index]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _memberTile(OrgMember m) {
    final isMe = m.userId == CurrentUser.id;
    final canManage = orgIsAdmin(_org.role) && !isMe && !m.isOwner;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openUserProfile(
        context,
        userId: m.userId,
        name: m.name,
        email: m.email,
        avatarUrl: m.avatar,
        role: m.role,
        roleLabel: 'Organization role',
        joinedAt: m.joinedAt,
      ),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: orgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: orgBorder),
      ),
      child: Row(
        children: [
          OrgAvatar(name: m.name, logo: m.avatar, size: 42, circular: true, presenceUserId: m.userId),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '${m.name} (You)' : m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                PresenceLine(
                  userId: m.userId,
                  ringColor: orgCard,
                  style: const TextStyle(color: orgMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OrgRoleBadge(role: m.role),
          if (canManage)
            PopupMenuButton<String>(
              color: orgCard,
              icon: const Icon(Icons.more_vert_rounded, color: orgMuted, size: 20),
              onSelected: (value) {
                if (value == 'remove') {
                  _removeMember(m);
                } else {
                  _changeRole(m, value);
                }
              },
              itemBuilder: (context) => [
                for (final role in const ['ORG_ADMIN', 'MEMBER'])
                  if (role != m.role)
                    PopupMenuItem<String>(
                      value: role,
                      child: Text('Make ${orgRoleLabel(role)}', style: const TextStyle(color: Colors.white)),
                    ),
                const PopupMenuItem<String>(
                  value: 'remove',
                  child: Text('Remove from organization', style: TextStyle(color: Color(0xFFEF4444))),
                ),
              ],
            ),
        ],
      ),
      ),
    );
  }

  Widget _teamsTab() {
    final canManage = orgIsAdmin(_org.role);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _createTeam,
              backgroundColor: orgAccent,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('New team', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      body: RefreshIndicator(
        color: orgTeal,
        backgroundColor: orgCard,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, 14, 20, canManage ? 96 : 24),
          children: [
            if (_teams.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: Text('No teams yet', style: TextStyle(color: orgMuted))),
              )
            else
              for (final team in _teams) ...[
                _teamTile(team, canManage),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _showTeamId(OrgTeam team) {
    return showIdDialog(
      context,
      title: team.name,
      label: 'Team ID',
      value: team.id,
      background: orgCard,
      titleColor: Colors.white,
      mutedColor: orgMuted,
      valueColor: Colors.white,
      borderColor: orgBorder,
      accentColor: orgTeal,
    );
  }

  Widget _teamTile(OrgTeam team, bool canManage) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openChat(team),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: orgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: orgBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                (team.avatar ?? '').isNotEmpty
                    ? OrgAvatar(name: team.name, logo: team.avatar, size: 40)
                    : Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF16302F),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.groups_rounded, color: orgTeal, size: 21),
                      ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        team.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${team.membersCount} ${team.membersCount == 1 ? 'member' : 'members'}',
                        style: const TextStyle(color: orgMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  color: orgCard,
                  icon: const Icon(Icons.more_vert_rounded, color: orgMuted, size: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onSelected: (v) {
                    switch (v) {
                      case 'edit':
                        _editTeam(team);
                      case 'add':
                        _addToTeam(team);
                      case 'leave':
                        _leaveTeam(team);
                      case 'id':
                        _showTeamId(team);
                    }
                  },
                  itemBuilder: (_) => [
                    if (canManage)
                      const PopupMenuItem(value: 'edit', child: Text('Edit team', style: TextStyle(color: Colors.white))),
                    if (canManage)
                      const PopupMenuItem(value: 'add', child: Text('Add member', style: TextStyle(color: Colors.white))),
                    const PopupMenuItem(value: 'id', child: Text('Team ID', style: TextStyle(color: Colors.white))),
                    const PopupMenuItem(value: 'leave', child: Text('Leave team', style: TextStyle(color: Color(0xFFEF4444)))),
                  ],
                ),
              ],
            ),
            if (team.description != null) ...[
              const SizedBox(height: 10),
              Text(
                team.description!,
                style: const TextStyle(color: orgMuted, fontSize: 12.5, height: 1.4),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  tooltip: 'Tasks',
                  onPressed: () => _openTasks(team),
                  icon: const Icon(Icons.task_alt_rounded, color: orgTeal, size: 22),
                ),
                IconButton(
                  tooltip: 'Chat',
                  onPressed: () => _openChat(team),
                  icon: Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: team.isMember ? orgTeal : orgMuted,
                    size: 22,
                  ),
                ),
                IconButton(
                  tooltip: 'Jira tickets',
                  onPressed: () => _openTeamJira(team),
                  icon: const Icon(Icons.confirmation_number_outlined, color: orgTeal, size: 22),
                ),
                IconButton(
                  tooltip: 'GitHub',
                  onPressed: () => _openTeamGithub(team),
                  icon: const Icon(Icons.code_rounded, color: orgTeal, size: 22),
                ),
                IconButton(
                  tooltip: 'Virtual office',
                  onPressed: () => _openOffice(team),
                  icon: const Icon(Icons.apartment_rounded, color: orgTeal, size: 22),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
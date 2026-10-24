import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'organization_sheets.dart';
import 'organization_widgets.dart';
import 'my_tasks_screen.dart';
import 'team_chat_screen.dart';
import 'team_tasks_screen.dart';

class OrganizationDetailScreen extends StatefulWidget {
  const OrganizationDetailScreen({super.key, required this.organization});
  final Organization organization;

  @override
  State<OrganizationDetailScreen> createState() => _OrganizationDetailScreenState();
}

class _OrganizationDetailScreenState extends State<OrganizationDetailScreen> {
  final _repo = OrganizationRepository.instance;
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
    super.dispose();
  }

  Future<List<OrgTeam>> _teamsWithCounts(List<OrgTeam> teams) {
    return Future.wait(teams.map((team) async {
      try {
        final people = await _repo.teamMembers(_org.id, team.id);
        return team.copyWith(membersCount: people.length);
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
        orgToast(context, e.message, error: true);
        Navigator.pop(context);
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

  Future<void> _invite() async {
    await showOrgSheet<void>(context, InviteSheet(organization: _org));
  }

  Future<void> _createTeam() async {
    final created = await showOrgSheet<bool>(context, CreateTeamSheet(organizationId: _org.id));
    if (created == true) {
      await _load();
      if (mounted) orgToast(context, 'Team created');
    }
  }

  Future<void> _openChat(OrgTeam team) async {
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

  Future<void> _openMyTasks() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyTasksScreen(organization: _org),
      ),
    );
  }

  Future<void> _addToTeam(OrgTeam team) async {
    final member = await showOrgSheet<OrgMember>(
      context,
      MemberPickerSheet(title: 'Add to ${team.name}', members: _members),
    );
    if (member == null) return;
    await _run(
      () => _repo.addTeamMember(_org.id, team.id, member.userId),
      '${member.name} added to ${team.name}',
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
        title: const Text('Organization', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        actions: [
          if (!_loading && _error == null && orgIsAdmin(_org.role))
            IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: orgTeal))
          : _error != null
              ? _errorView()
              : DefaultTabController(
                  length: 2,
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
                        ],
                      ),
                      Expanded(
                        child: TabBarView(children: [_membersTab(), _teamsTab()]),
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OrgAvatar(name: _org.name, logo: _org.logo, size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _org.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    OrgRoleBadge(role: _org.role),
                  ],
                ),
              ),
            ],
          ),
          if (_org.description != null) ...[
            const SizedBox(height: 14),
            Text(
              _org.description!,
              style: const TextStyle(color: orgMuted, fontSize: 13, height: 1.4),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _openMyTasks,
              icon: const Icon(Icons.task_alt_rounded, size: 18, color: orgTeal),
              label: const Text('My tasks', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: orgBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          if (orgCanInvite(_org.role)) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _invite,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Invite people', style: TextStyle(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: orgAccent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ],
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

  Widget _membersTab() {
    return RefreshIndicator(
      color: orgTeal,
      backgroundColor: orgCard,
      onRefresh: _load,
      child: _members.isEmpty
          ? _emptyList('No members yet')
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              itemCount: _members.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _memberTile(_members[index]),
            ),
    );
  }

  Widget _memberTile(OrgMember m) {
    final isMe = m.userId == CurrentUser.id;
    final canManage = orgIsAdmin(_org.role) && !isMe;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: orgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: orgBorder),
      ),
      child: Row(
        children: [
          OrgAvatar(name: m.name, logo: m.avatar, size: 42, circular: true),
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
                if (m.email != null)
                  Text(
                    m.email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                for (final role in const ['ORG_ADMIN', 'TEAM_HEAD', 'MEMBER'])
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
    );
  }

  Widget _teamsTab() {
    final canManage = orgCanInvite(_org.role);
    return RefreshIndicator(
      color: orgTeal,
      backgroundColor: orgCard,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        children: [
          if (canManage)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _createTeam,
                icon: const Icon(Icons.add_rounded, color: orgTeal, size: 18),
                label: const Text('New team', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
              ),
            ),
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
              Container(
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
              if (canManage)
                IconButton(
                  tooltip: 'Add member',
                  onPressed: () => _addToTeam(team),
                  icon: const Icon(Icons.person_add_alt_1_rounded, color: orgTeal, size: 20),
                ),
              IconButton(
                onPressed: () => _openTasks(team),
                icon: const Icon(Icons.task_alt_rounded, color: orgTeal, size: 20),
              ),
              IconButton(
                onPressed: () => _openChat(team),
                icon: const Icon(Icons.chat_bubble_outline_rounded, color: orgTeal, size: 20),
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
        ],
      ),
      ),
    );
  }
}
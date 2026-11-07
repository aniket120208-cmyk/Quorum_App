import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/github_repository.dart';
import 'package:quorum_app/models/github_models.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_sheets.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'github_repo_sheet.dart';
import 'github_settings_screen.dart';
import 'github_tabs.dart';
import 'github_widgets.dart';

class TeamGithubScreen extends StatefulWidget {
  const TeamGithubScreen({super.key, required this.organization, required this.team});
  final Organization organization;
  final OrgTeam team;

  @override
  State<TeamGithubScreen> createState() => _TeamGithubScreenState();
}

class _TeamGithubScreenState extends State<TeamGithubScreen> {
  final _repo = GithubRepository.instance;
  GithubStatus? _status;
  TeamRepoStatus? _repoStatus;
  bool _loading = true;
  String? _error;

  bool get _canManage => orgCanInvite(widget.organization.role);
  bool get _connected => _status?.connected == true;
  bool get _linked => _repoStatus?.linked == true;
  LinkedRepo? get _linkedRepo => _repoStatus?.repository;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final status = await _repo.status().catchError((_) => const GithubStatus(connected: false));
      final repoStatus = await _repo.teamRepo(widget.team.id);
      if (!mounted) return;
      setState(() {
        _status = status;
        _repoStatus = repoStatus;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _repoStatus == null) _error = errorText(e);
      });
    }
  }

  Future<void> _openAccount() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const GithubSettingsScreen()));
    if (mounted) _load();
  }

  Future<void> _pickRepo() async {
    if (!_connected) {
      await _openAccount();
      return;
    }
    final linked = await showOrgSheet<LinkedRepo>(
      context,
      GithubRepoPickerSheet(teamId: widget.team.id, currentFullName: _linkedRepo?.fullName),
    );
    if (linked == null || !mounted) return;
    await _load();
    if (mounted) orgToast(context, 'Repository linked to team successfully');
  }

  Future<void> _unlink() async {
    final repo = _linkedRepo;
    if (repo == null) return;
    final ok = await orgConfirm(
      context,
      title: 'Unlink repository',
      body: '${repo.fullName} will no longer be tracked by ${widget.team.name}.',
      action: 'Unlink',
    );
    if (!ok) return;
    try {
      await _repo.unlinkRepo(widget.team.id, repo.fullName);
      await _load();
      if (mounted) orgToast(context, 'Repository unlinked');
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  PreferredSizeWidget _appBar(bool showTabs) {
    final repo = _linkedRepo;
    return AppBar(
      backgroundColor: orgBg,
      elevation: 0,
      foregroundColor: Colors.white,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('GitHub', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text(
            repo != null ? '${widget.team.name} · ${repo.name}' : widget.team.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: orgMuted),
          ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'More',
          color: orgField,
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (value) {
            switch (value) {
              case 'open':
                openGithubUrl(context, repo == null ? null : 'https://github.com/${repo.fullName}');
              case 'change':
                _pickRepo();
              case 'unlink':
                _unlink();
              case 'account':
                _openAccount();
            }
          },
          itemBuilder: (_) => [
            if (_linked)
              const PopupMenuItem(value: 'open', child: Text('Open on GitHub', style: TextStyle(color: Colors.white))),
            if (_linked && _canManage)
              const PopupMenuItem(value: 'change', child: Text('Change repository', style: TextStyle(color: Colors.white))),
            if (_linked && _canManage)
              const PopupMenuItem(
                value: 'unlink',
                child: Text('Unlink repository', style: TextStyle(color: Color(0xFFEF4444))),
              ),
            const PopupMenuItem(value: 'account', child: Text('GitHub account', style: TextStyle(color: Colors.white))),
          ],
        ),
      ],
      bottom: showTabs
          ? const TabBar(
              indicatorColor: orgTeal,
              labelColor: Colors.white,
              unselectedLabelColor: orgMuted,
              dividerColor: orgBorder,
              labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: [
                Tab(text: 'Issues'),
                Tab(text: 'Pull requests'),
                Tab(text: 'Commits'),
              ],
            )
          : null,
    );
  }

  Widget _connectBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFBBF24).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFFBBF24), size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Connect your GitHub account to create and update issues.',
              style: TextStyle(color: Colors.white, fontSize: 12.5, height: 1.35),
            ),
          ),
          TextButton(
            onPressed: _openAccount,
            child: const Text('Connect', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _unlinkedView() {
    if (_canManage) {
      return GithubMessageView(
        icon: Icons.link_off_rounded,
        message: _connected
            ? 'No repository is linked to ${widget.team.name} yet. Link one to see its issues, pull requests and commits.'
            : 'Connect your GitHub account first, then link a repository to ${widget.team.name}.',
        actionLabel: _connected ? 'Link repository' : 'Connect GitHub',
        onAction: _pickRepo,
      );
    }
    return GithubMessageView(
      icon: Icons.link_off_rounded,
      message: 'No repository is linked to this team. Ask a team lead or admin to link one.',
      actionLabel: 'Refresh',
      onAction: _load,
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: orgTeal));
    if (_error != null) {
      return GithubMessageView(
        icon: Icons.error_outline_rounded,
        message: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    if (!_linked) return _unlinkedView();
    final repo = _linkedRepo!;
    return Column(
      children: [
        if (!_connected) _connectBanner(),
        Expanded(
          child: TabBarView(
            children: [
              GithubIssuesTab(teamId: widget.team.id),
              GithubPullsTab(teamId: widget.team.id),
              GithubCommitsTab(teamId: widget.team.id, defaultBranch: repo.defaultBranch),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final showTabs = !_loading && _error == null && _linked;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: orgBg,
        appBar: _appBar(showTabs),
        body: _body(),
      ),
    );
  }
}
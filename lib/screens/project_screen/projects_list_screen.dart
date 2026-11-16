import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/api/project_repository.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/models/project_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'accept_project_invite_screen.dart';
import 'project_detail_screen.dart';
import 'project_sheets.dart';
import 'project_widgets.dart';

class ProjectsListScreen extends StatefulWidget {
  const ProjectsListScreen({super.key, this.organization});
  final Organization? organization;

  @override
  State<ProjectsListScreen> createState() => _ProjectsListScreenState();
}

class _ProjectsListScreenState extends State<ProjectsListScreen> {
  final _repo = ProjectRepository.instance;
  List<Project> _projects = [];
  Map<String, String> _orgRoles = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _canCreate => widget.organization != null && orgIsAdmin(widget.organization!.role);

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _repo.projects(),
        OrganizationRepository.instance
            .organizations()
            .then((orgs) => {for (final o in orgs) o.id: o.role})
            .catchError((_) => <String, String>{}),
      ]);
      if (!mounted) return;
      var projects = results[0] as List<Project>;
      final org = widget.organization;
      if (org != null) {
        projects = projects.where((p) => p.organization?.id == org.id).toList();
      }
      setState(() {
        _projects = projects;
        _orgRoles = results[1] as Map<String, String>;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _projects.isEmpty) _error = errorText(e);
      });
    }
  }

  Future<void> _create() async {
    final org = widget.organization;
    if (org == null) return;
    final project = await showProjectSheet<Project>(context, CreateProjectSheet(organizationId: org.id));
    if (project == null || !mounted) return;
    orgToast(context, 'Project created');
    await _load(silent: true);
  }

  Future<void> _acceptInvite() async {
    final joined = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AcceptProjectInviteScreen()),
    );
    if (joined == true && mounted) await _load(silent: true);
  }

  Future<void> _open(Project project) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectDetailScreen(
          project: project,
          orgAdmin: orgIsAdmin(_orgRoles[project.organization?.id] ?? ''),
        ),
      ),
    );
    if (mounted) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Projects', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (widget.organization != null)
              Text(widget.organization!.name, style: const TextStyle(fontSize: 12, color: orgMuted)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Accept invitation',
            onPressed: _acceptInvite,
            icon: const Icon(Icons.mail_outline_rounded, color: orgTeal),
          ),
        ],
      ),
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              onPressed: _create,
              backgroundColor: orgAccent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New project'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: orgTeal))
          : _error != null
              ? _errorView()
              : RefreshIndicator(
                  color: orgTeal,
                  backgroundColor: orgCard,
                  onRefresh: () => _load(silent: true),
                  child: _projects.isEmpty ? _empty() : _list(),
                ),
    );
  }

  Widget _list() {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: _projects.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _ProjectCard(project: _projects[i], onTap: () => _open(_projects[i])),
    );
  }

  Widget _empty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.workspaces_outline, color: orgMuted, size: 44),
        const SizedBox(height: 12),
        const Center(child: Text('No projects yet', style: TextStyle(color: orgMuted))),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _acceptInvite,
            child: const Text(
              'Have an invitation? Join a project',
              style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
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
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _load(),
              child: const Text('Retry', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});
  final Project project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final org = project.organization;
    final external = project.members.where((m) => m.role.isExternal).toList();
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: orgCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: orgBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (org != null) ...[
                  OrgAvatar(name: org.name, logo: org.logo, size: 40),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      if (org != null)
                        Text(org.name, style: const TextStyle(color: orgMuted, fontSize: 12.5)),
                    ],
                  ),
                ),
                ProjChip(
                  label: project.status.replaceAll('_', ' '),
                  color: project.status == 'ACTIVE' ? projGreen : orgMuted,
                ),
              ],
            ),
            if (project.description != null) ...[
              const SizedBox(height: 10),
              Text(
                project.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: orgMuted, fontSize: 13, height: 1.4),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ProjChip(label: '${project.tasksCount} tasks', color: projBlue, icon: Icons.task_alt_rounded),
                ProjChip(label: '${project.membersCount} members', color: orgTeal, icon: Icons.group_rounded),
                if (project.dueDate != null)
                  ProjChip(label: projDate(project.dueDate!), color: orgMuted, icon: Icons.event_rounded),
              ],
            ),
            if (external.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  for (var i = 0; i < external.length && i < 4; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: OrgAvatar(
                        name: external[i].user.name,
                        logo: external[i].user.avatar,
                        size: 26,
                        circular: true,
                      ),
                    ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      external.map((m) => m.companyName ?? m.user.name).toSet().join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: orgMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
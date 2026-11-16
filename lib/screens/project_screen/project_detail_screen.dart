import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quorum_app/api/deep_link_router.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/project_repository.dart';
import 'package:quorum_app/api/socket_service.dart';
import 'package:quorum_app/models/project_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'project_chat_tab.dart';
import 'project_sheets.dart';
import 'project_widgets.dart';

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.project, this.orgAdmin = false});
  final Project project;
  final bool orgAdmin;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> with SingleTickerProviderStateMixin {
  final _repo = ProjectRepository.instance;
  final _socket = SocketService.instance;
  late final TabController _tabs = TabController(length: 4, vsync: this);

  late Project _project = widget.project;
  List<ProjectTask> _tasks = [];
  List<ProjectResource> _resources = [];
  ProjectTaskStatus? _filter;
  bool _mineOnly = false;
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};
  String? _joinedConversation;
  bool _chatActive = false;

  late final Map<String, SocketHandler> _handlers = {
    'project:task_created': (d) => _onTask(d),
    'project:task_updated': (d) => _onTask(d),
    'project:task_status_changed': (d) => _onTask(d),
    'project:deliverable_submitted': (d) => _onTask(d),
    'project:deliverable_reviewed': (d) => _onReviewed(d),
    'project:member_joined': (d) => _onMembersChanged(d),
    'project:member_removed': (d) => _onMemberRemoved(d),
    'project:resource_added': (d) => _onResource(d),
  };

  ProjectMember? get _me => _project.memberFor(CurrentUser.id);
  bool get _isManager {
    final role = _me?.role;
    if (role == null) return widget.orgAdmin;
    if (role == ProjectRole.projectManager) return true;
    return role == ProjectRole.internalMember && widget.orgAdmin;
  }
  bool get _isFreelancer => _me?.role == ProjectRole.freelancer;
  bool get _canAddFiles => _isManager || _isFreelancer;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      final active = _tabs.index == 3;
      if (active != _chatActive && mounted) setState(() => _chatActive = active);
    });
    _load();
    _connectSocket();
  }

  @override
  void dispose() {
    _handlers.forEach(_socket.off);
    final conv = _joinedConversation;
    if (conv != null) _socket.leave(conv);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _connectSocket() async {
    await _socket.ensureConnected();
    if (!mounted) return;
    _handlers.forEach(_socket.on);
    _joinConversation(_project.conversationId);
  }

  void _joinConversation(String? id) {
    if (id == null || id.isEmpty || id == _joinedConversation) return;
    _joinedConversation = id;
    _socket.join(id);
  }

  bool _forThisProject(Map<String, dynamic>? m) {
    if (m == null) return false;
    final id = (m['projectId'] ?? '').toString();
    return id.isEmpty || id == _project.id;
  }

  void _upsertTask(ProjectTask task) {
    final i = _tasks.indexWhere((t) => t.id == task.id);
    if (i == -1) {
      _tasks = [task, ..._tasks];
    } else {
      _tasks = [..._tasks]..[i] = task;
    }
  }

  void _onTask(dynamic d) {
    final m = asMap(d);
    if (!mounted || !_forThisProject(m) || m!['task'] is! Map) return;
    final task = ProjectTask.fromJson(Map<String, dynamic>.from(m['task'] as Map), projectId: _project.id);
    setState(() => _upsertTask(task));
  }

  void _onReviewed(dynamic d) {
    final m = asMap(d);
    if (!mounted || !_forThisProject(m)) return;
    _onTask(d);
    final task = m!['task'] is Map ? ProjectTask.fromJson(Map<String, dynamic>.from(m['task'] as Map)) : null;
    if (task != null && task.assigneeId == CurrentUser.id) {
      final approved = m['approved'] == true;
      orgToast(context, approved ? '"${task.title}" was approved' : 'Changes requested on "${task.title}"');
    }
  }

  Future<void> _onMembersChanged(dynamic d) async {
    final m = asMap(d);
    if (!mounted || !_forThisProject(m)) return;
    await _reloadProject();
  }

  void _onMemberRemoved(dynamic d) {
    final m = asMap(d);
    if (!mounted || !_forThisProject(m)) return;
    final userId = (m!['userId'] ?? '').toString();
    if (userId == CurrentUser.id) {
      orgToast(context, 'You were removed from this project', error: true);
      Navigator.pop(context);
      return;
    }
    setState(() {
      _project = _project.copyWith(members: _project.members.where((x) => x.user.id != userId).toList());
    });
  }

  void _onResource(dynamic d) {
    final m = asMap(d);
    if (!mounted || !_forThisProject(m) || m!['resource'] is! Map) return;
    final resource = ProjectResource.fromJson(Map<String, dynamic>.from(m['resource'] as Map));
    if (_resources.any((r) => r.id == resource.id)) return;
    setState(() => _resources = [resource, ..._resources]);
  }

  Future<void> _reloadProject() async {
    try {
      final p = await _repo.project(_project.id);
      if (!mounted) return;
      setState(() => _project = p);
      _joinConversation(p.conversationId);
    } catch (_) {}
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _repo.project(_project.id),
        _repo.tasks(_project.id),
        _repo.resources(_project.id).catchError((_) => <ProjectResource>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _project = results[0] as Project;
        _tasks = results[1] as List<ProjectTask>;
        _resources = results[2] as List<ProjectResource>;
        _loading = false;
        _error = null;
      });
      _joinConversation(_project.conversationId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _tasks.isEmpty) _error = errorText(e);
      });
    }
  }

  Future<void> _guarded(String taskId, Future<ProjectTask> Function() run, {String? success}) async {
    if (_busy.contains(taskId)) return;
    setState(() => _busy.add(taskId));
    try {
      final task = await run();
      if (!mounted) return;
      setState(() => _upsertTask(task));
      if (success != null) orgToast(context, success);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(taskId));
    }
  }

  Future<void> _start(ProjectTask t) => _guarded(
        t.id,
        () => _repo.updateTaskStatus(_project.id, t.id, ProjectTaskStatus.inProgress),
      );

  Future<void> _submit(ProjectTask t) async {
    final updated = await showProjectSheet<ProjectTask>(
      context,
      SubmitDeliverableSheet(projectId: _project.id, task: t),
    );
    if (updated == null || !mounted) return;
    setState(() => _upsertTask(updated));
    orgToast(context, 'Deliverable submitted for review');
  }

  Future<void> _review(ProjectTask t, {required bool approve}) async {
    final updated = await showProjectSheet<ProjectTask>(
      context,
      ReviewDeliverableSheet(projectId: _project.id, task: t, approve: approve),
    );
    if (updated == null || !mounted) return;
    setState(() => _upsertTask(updated));
    orgToast(context, approve ? 'Task approved' : 'Changes requested');
  }

  Future<void> _newTask() async {
    final task = await showProjectSheet<ProjectTask>(
      context,
      TaskFormSheet(projectId: _project.id, members: _project.members),
    );
    if (task == null || !mounted) return;
    setState(() => _upsertTask(task));
    orgToast(context, 'Task created');
  }

  Future<void> _editTask(ProjectTask t) async {
    if (!_isManager) return;
    final task = await showProjectSheet<ProjectTask>(
      context,
      TaskFormSheet(projectId: _project.id, members: _project.members, task: t),
    );
    if (task == null || !mounted) return;
    setState(() => _upsertTask(task));
    orgToast(context, 'Task updated');
  }

  Future<void> _openUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await DeepLinkRouter.tryOpen(uri)) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) orgToast(context, 'Could not open the link', error: true);
  }

  Future<void> _editProject() async {
    final saved = await showProjectSheet<bool>(context, EditProjectSheet(project: _project));
    if (saved == true && mounted) {
      await _reloadProject();
      if (mounted) orgToast(context, 'Project updated');
    }
  }

  Future<void> _deleteProject() async {
    final ok = await orgConfirm(
      context,
      title: 'Delete project?',
      body: 'This permanently removes "${_project.name}", its tasks, files and workspace chat.',
      action: 'Delete',
    );
    if (!ok) return;
    try {
      await _repo.deleteProject(_project.id);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _invite() async {
    final sent = await showProjectSheet<bool>(context, InviteCollaboratorSheet(project: _project));
    if (sent == true && mounted) await _reloadProject();
  }

  Future<void> _editMember(ProjectMember m) async {
    if (!_isManager) return;
    final saved = await showProjectSheet<bool>(
      context,
      EditMemberSheet(projectId: _project.id, member: m),
    );
    if (saved == true && mounted) {
      await _reloadProject();
      if (mounted) orgToast(context, 'Member updated');
    }
  }

  Future<void> _removeMember(ProjectMember m) async {
    final ok = await orgConfirm(
      context,
      title: 'Remove member?',
      body: '${m.user.name} will lose access to this project and its workspace chat.',
      action: 'Remove',
    );
    if (!ok) return;
    try {
      await _repo.removeMember(_project.id, m.user.id);
      if (!mounted) return;
      setState(() {
        _project = _project.copyWith(members: _project.members.where((x) => x.user.id != m.user.id).toList());
      });
      orgToast(context, '${m.user.name} removed');
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _addResource() async {
    final resource = await showProjectSheet<ProjectResource>(context, AddResourceSheet(projectId: _project.id));
    if (resource == null || !mounted) return;
    setState(() {
      if (!_resources.any((r) => r.id == resource.id)) _resources = [resource, ..._resources];
    });
    orgToast(context, 'Resource added');
  }

  Future<void> _deleteResource(ProjectResource r) async {
    final ok = await orgConfirm(
      context,
      title: 'Delete resource?',
      body: '"${r.title}" will be removed for everyone in this project.',
      action: 'Delete',
    );
    if (!ok) return;
    try {
      await _repo.deleteResource(_project.id, r.id);
      if (!mounted) return;
      setState(() => _resources = _resources.where((x) => x.id != r.id).toList());
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: orgBg,
      resizeToAvoidBottomInset: !_chatActive,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (_project.organization != null)
              Text(_project.organization!.name, style: const TextStyle(fontSize: 12, color: orgMuted)),
          ],
        ),
        actions: [
          if (_isManager)
            PopupMenuButton<String>(
              color: orgCard,
              iconColor: Colors.white,
              onSelected: (v) {
                if (v == 'edit') _editProject();
                if (v == 'delete') _deleteProject();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit project', style: TextStyle(color: Colors.white))),
                PopupMenuItem(value: 'delete', child: Text('Delete project', style: TextStyle(color: projRed))),
              ],
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: orgTeal,
          labelColor: Colors.white,
          unselectedLabelColor: orgMuted,
          tabs: [
            const Tab(text: 'Tasks'),
            Tab(text: 'Members (${_project.members.length})'),
            Tab(text: 'Files (${_resources.length})'),
            const Tab(text: 'Chat'),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabs,
        builder: (context, _) => _fab() ?? const SizedBox.shrink(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: orgTeal))
          : _error != null
              ? _errorView()
              : TabBarView(
                  controller: _tabs,
                  physics: _chatActive ? const NeverScrollableScrollPhysics() : null,
                  children: [
                    _tasksTab(),
                    _membersTab(),
                    _filesTab(),
                    ProjectChatTab(project: _project, active: _chatActive, onRetry: _reloadProject),
                  ],
                ),
    );
  }

  Widget? _fab() {
    if (_loading || _error != null) return null;
    switch (_tabs.index) {
      case 0:
        if (!_isManager) return null;
        return FloatingActionButton.extended(
          onPressed: _newTask,
          backgroundColor: orgAccent,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: const Text('New task'),
        );
      case 1:
        if (!_isManager) return null;
        return FloatingActionButton.extended(
          onPressed: _invite,
          backgroundColor: orgAccent,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Invite'),
        );
      case 3:
        return null;
      default:
        if (!_canAddFiles) return null;
        return FloatingActionButton.extended(
          onPressed: _addResource,
          backgroundColor: orgAccent,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Add file'),
        );
    }
  }

  Widget _tasksTab() {
    final visible = _tasks.where((t) {
      if (_filter != null && t.status != _filter) return false;
      if (_mineOnly && t.assigneeId != CurrentUser.id) return false;
      return true;
    }).toList();

    return RefreshIndicator(
      color: orgTeal,
      backgroundColor: orgCard,
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _summary(),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('All', _filter == null, () => setState(() => _filter = null)),
                for (final s in ProjectTaskStatus.values)
                  _filterChip(s.label, _filter == s, () => setState(() => _filter = _filter == s ? null : s)),
                _filterChip('Mine', _mineOnly, () => setState(() => _mineOnly = !_mineOnly), icon: Icons.person_rounded),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(child: Text('No tasks to show', style: TextStyle(color: orgMuted))),
            )
          else
            for (final t in visible)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ProjTaskCard(
                  task: t,
                  isManager: _isManager,
                  isAssignee: _isFreelancer && t.assigneeId == CurrentUser.id,
                  busy: _busy.contains(t.id),
                  onTap: () => _editTask(t),
                  onStart: () => _start(t),
                  onSubmit: () => _submit(t),
                  onApprove: () => _review(t, approve: true),
                  onRequestChanges: () => _review(t, approve: false),
                  onOpenDeliverable: () => _openUrl(t.deliverableUrl),
                  onOpenFeedbackFile: () => _openUrl(t.reviewFeedbackUrl),
                ),
              ),
        ],
      ),
    );
  }

  Widget _summary() {
    final p = _project;
    final done = _tasks.where((t) => t.status == ProjectTaskStatus.completed).length;
    final progress = _tasks.isEmpty ? 0.0 : done / _tasks.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: orgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: orgBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p.description != null) ...[
            Text(p.description!, style: const TextStyle(color: orgMuted, fontSize: 13, height: 1.4)),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ProjChip(
                label: p.status.replaceAll('_', ' '),
                color: p.status == 'ACTIVE' ? projGreen : orgMuted,
              ),
              if (p.dueDate != null) ProjChip(label: projDate(p.dueDate!), color: orgMuted, icon: Icons.event_rounded),
              if (_me != null) ProjChip(label: 'You: ${_me!.role.label}', color: projRoleColor(_me!.role)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: orgTeal,
              backgroundColor: orgField,
            ),
          ),
          const SizedBox(height: 6),
          Text('$done of ${_tasks.length} tasks completed', style: const TextStyle(color: orgMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 14, color: Colors.white), const SizedBox(width: 4)],
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
          ],
        ),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: orgAccent,
        backgroundColor: orgField,
        side: const BorderSide(color: orgBorder),
      ),
    );
  }

  Widget _membersTab() {
    final members = _project.members;
    return RefreshIndicator(
      color: orgTeal,
      backgroundColor: orgCard,
      onRefresh: () => _load(silent: true),
      child: members.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No members yet', style: TextStyle(color: orgMuted))),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: members.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final m = members[i];
                final isMe = m.user.id == CurrentUser.id;
                return ProjMemberCard(
                  member: m,
                  showRate: _isManager,
                  onTap: _isManager ? () => _editMember(m) : null,
                  trailing: _isManager && !isMe
                      ? IconButton(
                          tooltip: 'Remove member',
                          onPressed: () => _removeMember(m),
                          icon: const Icon(Icons.person_remove_alt_1_rounded, color: projRed, size: 20),
                        )
                      : null,
                );
              },
            ),
    );
  }

  Widget _filesTab() {
    return RefreshIndicator(
      color: orgTeal,
      backgroundColor: orgCard,
      onRefresh: () => _load(silent: true),
      child: _resources.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No files shared yet', style: TextStyle(color: orgMuted))),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: _resources.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final r = _resources[i];
                final canDelete = _isManager || (_isFreelancer && r.uploadedById == CurrentUser.id);
                final meta = [
                  if (r.fileSize != null) projFileSize(r.fileSize),
                  if (r.uploadedBy != null) r.uploadedBy!.name,
                  if (r.createdAt != null) projDate(r.createdAt!),
                ].join(' · ');
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _openUrl(r.fileUrl),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: orgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: orgBorder),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: orgTeal.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.insert_drive_file_rounded, color: orgTeal, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                              if (meta.isNotEmpty)
                                Text(
                                  meta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: orgMuted, fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                        if (canDelete)
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: () => _deleteResource(r),
                            icon: const Icon(Icons.delete_outline_rounded, color: projRed, size: 20),
                          ),
                      ],
                    ),
                  ),
                );
              },
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
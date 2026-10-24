import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'organization_sheets.dart';
import 'organization_widgets.dart';
import 'task_widgets.dart';

class TeamTasksScreen extends StatefulWidget {
  const TeamTasksScreen({super.key, required this.organization, required this.team});
  final Organization organization;
  final OrgTeam team;

  @override
  State<TeamTasksScreen> createState() => _TeamTasksScreenState();
}

class _TeamTasksScreenState extends State<TeamTasksScreen> {
  final _repo = OrganizationRepository.instance;
  List<TeamTask> _tasks = [];
  bool _loading = true;
  String? _error;

  bool get _canCreate => orgCanInvite(widget.organization.role);

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
      final tasks = await _repo.teamTasks(widget.organization.id, widget.team.id);
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _tasks.isEmpty) _error = errorText(e);
      });
    }
  }

  bool _canChange(TeamTask task) => task.assigneeId == CurrentUser.id || orgCanInvite(widget.organization.role);

  Future<void> _changeStatus(TeamTask task, TaskStatus status) async {
    final previous = task.status;
    setState(() {
      _tasks = [for (final t in _tasks) t.id == task.id ? t.copyWith(status: status) : t];
    });
    try {
      final confirmed = await _repo.updateTaskStatus(
        widget.organization.id,
        widget.team.id,
        task.id,
        status,
      );
      if (!mounted) return;
      setState(() {
        _tasks = [for (final t in _tasks) t.id == task.id ? t.copyWith(status: confirmed) : t];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tasks = [for (final t in _tasks) t.id == task.id ? t.copyWith(status: previous) : t];
      });
      orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _create() async {
    final created = await showOrgSheet<bool>(
      context,
      CreateTaskSheet(organization: widget.organization, team: widget.team),
    );
    if (created == true) {
      await _load(silent: true);
      if (mounted) orgToast(context, 'Task created and assigned');
    }
  }

  List<TeamTask> _byStatus(TaskStatus status) => _tasks.where((t) => t.status == status).toList();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: TaskStatus.values.length,
      child: Scaffold(
        backgroundColor: orgBg,
        appBar: AppBar(
          backgroundColor: orgBg,
          elevation: 0,
          foregroundColor: Colors.white,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text(widget.team.name, style: const TextStyle(fontSize: 12, color: orgMuted)),
            ],
          ),
          actions: [
            IconButton(onPressed: _loading ? null : () => _load(), icon: const Icon(Icons.refresh_rounded)),
          ],
          bottom: TabBar(
            indicatorColor: orgTeal,
            labelColor: Colors.white,
            unselectedLabelColor: orgMuted,
            dividerColor: orgBorder,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: [
              for (final status in TaskStatus.values)
                Tab(text: '${status.label} (${_byStatus(status).length})'),
            ],
          ),
        ),
        floatingActionButton: _canCreate && !_loading && _error == null
            ? FloatingActionButton.extended(
                onPressed: _create,
                backgroundColor: orgAccent,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New task', style: TextStyle(fontWeight: FontWeight.w700)),
              )
            : null,
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: orgTeal))
            : _error != null
                ? _errorView()
                : TabBarView(
                    children: [for (final status in TaskStatus.values) _column(status)],
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

  Widget _column(TaskStatus status) {
    final tasks = _byStatus(status);
    return RefreshIndicator(
      color: orgTeal,
      backgroundColor: orgCard,
      onRefresh: () => _load(silent: true),
      child: tasks.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                Center(
                  child: Text('No ${status.label.toLowerCase()} tasks', style: const TextStyle(color: orgMuted)),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
              itemCount: tasks.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final task = tasks[index];
                return TaskCard(
                  task: task,
                  onStatusChange: _canChange(task) ? (next) => _changeStatus(task, next) : null,
                );
              },
            ),
    );
  }
}

class CreateTaskSheet extends StatefulWidget {
  const CreateTaskSheet({super.key, required this.organization, required this.team});
  final Organization organization;
  final OrgTeam team;

  @override
  State<CreateTaskSheet> createState() => _CreateTaskSheetState();
}

class _CreateTaskSheetState extends State<CreateTaskSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  List<OrgMember> _members = [];
  OrgMember? _assignee;
  DateTime? _dueDate;
  bool _membersLoading = true;
  String? _membersError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _membersLoading = true;
      _membersError = null;
    });
    try {
      final members = await OrganizationRepository.instance.teamMembers(
        widget.organization.id,
        widget.team.id,
      );
      if (!mounted) return;
      setState(() {
        _members = members.where((m) => m.userId.isNotEmpty).toList();
        _membersLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _membersLoading = false;
        _membersError = errorText(e);
      });
    }
  }

  Future<void> _pickAssignee() async {
    final member = await showOrgSheet<OrgMember>(
      context,
      MemberPickerSheet(title: 'Assign to', members: _members),
    );
    if (member != null && mounted) setState(() => _assignee = member);
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueDate ?? DateTime(now.year, now.month, now.day, 18)),
    );
    if (!mounted) return;
    setState(() {
      _dueDate = DateTime(date.year, date.month, date.day, time?.hour ?? 18, time?.minute ?? 0);
    });
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      orgToast(context, 'Task title is required', error: true);
      return;
    }
    if (_assignee == null) {
      orgToast(context, 'Choose who this task is assigned to', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await OrganizationRepository.instance.createTask(
        widget.organization.id,
        widget.team.id,
        title: title,
        description: _descCtrl.text.trim(),
        dueDate: _dueDate,
        assigneeId: _assignee!.userId,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback? onTap,
    Widget? trailing,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: orgField,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2C3246)),
        ),
        child: Row(
          children: [
            Icon(icon, color: orgMuted, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: orgMuted, fontSize: 11.5)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final due = _dueDate;
    final time = due == null ? null : MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(due));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 18),
            child: Text(
              'New task',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          TextField(
            controller: _titleCtrl,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.sentences,
            decoration: orgInputDecoration('Title', hint: 'e.g. Implement login page UI'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _descCtrl,
            style: const TextStyle(color: Colors.white),
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: orgInputDecoration('Description (optional)'),
          ),
          const SizedBox(height: 14),
          if (_membersError != null)
            _pickerTile(
              icon: Icons.error_outline_rounded,
              label: 'Assignee',
              value: _membersError!,
              onTap: _loadMembers,
              trailing: const Icon(Icons.refresh_rounded, color: orgTeal, size: 20),
            )
          else
            _pickerTile(
              icon: Icons.person_outline_rounded,
              label: 'Assignee',
              value: _membersLoading ? 'Loading team members...' : _assignee?.name ?? 'Choose a team member',
              onTap: _membersLoading ? null : _pickAssignee,
              trailing: _membersLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: orgTeal),
                    ) : const Icon(Icons.keyboard_arrow_down_rounded, color: orgMuted),
            ),
          const SizedBox(height: 14),
          _pickerTile(
            icon: Icons.event_rounded,
            label: 'Due date (optional)',
            value: due == null ? 'No due date' : '${taskDueLabel(due)}, $time',
            onTap: _pickDueDate,
            trailing: due == null
                ? null
                : IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, color: orgMuted, size: 18),
                    onPressed: () => setState(() => _dueDate = null),
                  ),
          ),
          const SizedBox(height: 22),
          OrgPrimaryButton(label: 'Create and assign', loading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}
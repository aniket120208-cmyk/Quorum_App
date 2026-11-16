import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:quorum_app/widgets/char_limit.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/project_repository.dart';
import 'package:quorum_app/api/upload_service.dart';
import 'package:quorum_app/models/project_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_sheets.dart' show showOrgSheet;
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'project_widgets.dart';

Future<T?> showProjectSheet<T>(BuildContext context, Widget child) => showOrgSheet<T>(context, child);

class CreateProjectSheet extends StatefulWidget {
  const CreateProjectSheet({super.key, required this.organizationId});
  final String organizationId;

  @override
  State<CreateProjectSheet> createState() => _CreateProjectSheetState();
}

class _CreateProjectSheetState extends State<CreateProjectSheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  DateTime? _due;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      orgToast(context, 'Project name is required', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final project = await ProjectRepository.instance.createProject(
        widget.organizationId,
        name: name,
        description: _desc.text.trim(),
        dueDate: _due,
      );
      if (!mounted) return;
      Navigator.pop(context, project);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProjSheetTitle('New project'),
          TextField(
            controller: _name,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.words,
            decoration: orgInputDecoration('Project name'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _desc,
            style: const TextStyle(color: Colors.white),
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: orgInputDecoration('Description (optional)'),
          ),
          const SizedBox(height: 14),
          ProjDateField(label: 'Due date (optional)', value: _due, onChanged: (d) => setState(() => _due = d)),
          const SizedBox(height: 22),
          OrgPrimaryButton(label: 'Create project', loading: _loading, onPressed: _create),
        ],
      ),
    );
  }
}

class EditProjectSheet extends StatefulWidget {
  const EditProjectSheet({super.key, required this.project});
  final Project project;

  @override
  State<EditProjectSheet> createState() => _EditProjectSheetState();
}

class _EditProjectSheetState extends State<EditProjectSheet> {
  static const _statuses = ['ACTIVE', 'ON_HOLD', 'COMPLETED', 'CANCELLED'];
  late final _name = TextEditingController(text: widget.project.name);
  late final _desc = TextEditingController(text: widget.project.description ?? '');
  late DateTime? _due = widget.project.dueDate;
  late String _status = _statuses.contains(widget.project.status) ? widget.project.status : 'ACTIVE';
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  String _statusLabel(String s) => s.split('_').map((w) => w[0] + w.substring(1).toLowerCase()).join(' ');

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      orgToast(context, 'Project name is required', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await ProjectRepository.instance.updateProject(
        widget.project.id,
        name: name,
        description: _desc.text.trim(),
        status: _status,
        dueDate: _due,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProjSheetTitle('Edit project'),
          TextField(
            controller: _name,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.words,
            decoration: orgInputDecoration('Project name'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _desc,
            style: const TextStyle(color: Colors.white),
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: orgInputDecoration('Description'),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _status,
            dropdownColor: orgCard,
            style: const TextStyle(color: Colors.white),
            decoration: orgInputDecoration('Status'),
            items: [for (final s in _statuses) DropdownMenuItem(value: s, child: Text(_statusLabel(s)))],
            onChanged: (v) => setState(() => _status = v ?? _status),
          ),
          const SizedBox(height: 14),
          ProjDateField(label: 'Due date', value: _due, onChanged: (d) => setState(() => _due = d)),
          const SizedBox(height: 22),
          OrgPrimaryButton(label: 'Save changes', loading: _loading, onPressed: _save),
        ],
      ),
    );
  }
}

class InviteCollaboratorSheet extends StatefulWidget {
  const InviteCollaboratorSheet({super.key, required this.project});
  final Project project;

  @override
  State<InviteCollaboratorSheet> createState() => _InviteCollaboratorSheetState();
}

class _InviteCollaboratorSheetState extends State<InviteCollaboratorSheet> {
  final _email = TextEditingController();
  final _rate = TextEditingController();
  final _company = TextEditingController();
  ProjectRole _role = ProjectRole.freelancer;
  bool _loading = false;
  ProjectInviteResult? _result;

  @override
  void dispose() {
    _email.dispose();
    _rate.dispose();
    _company.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      orgToast(context, 'Enter a valid email address', error: true);
      return;
    }
    final rateText = _rate.text.trim();
    final rate = rateText.isEmpty ? null : double.tryParse(rateText);
    if (rateText.isNotEmpty && rate == null) {
      orgToast(context, 'Enter a valid hourly rate', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await ProjectRepository.instance.invite(
        widget.project.id,
        email: email,
        role: _role,
        hourlyRate: rate,
        companyName: _company.text.trim(),
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: result != null ? _sent(result) : _form(),
    );
  }

  Widget _sent(ProjectInviteResult result) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ProjSheetTitle('Invitation sent'),
        Text(
          'An invitation was emailed to ${result.email}.',
          style: const TextStyle(color: orgMuted, fontSize: 14),
        ),
        if (result.expiresAt != null) ...[
          const SizedBox(height: 6),
          Text('Expires ${projDate(result.expiresAt!)}', style: const TextStyle(color: orgMuted, fontSize: 12.5)),
        ],
        const SizedBox(height: 16),
        if (result.token.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: orgField,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: orgBorder),
            ),
            child: SelectableText(
              result.token,
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
            ),
          ),
        const SizedBox(height: 20),
        OrgPrimaryButton(label: 'Done', onPressed: () => Navigator.pop(context, true)),
      ],
    );
  }

  Widget _form() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ProjSheetTitle('Invite collaborator'),
        TextField(
          controller: _email,
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          maxLength: kEmailMaxLength,
          buildCounter: charLimitCounter,
          decoration: orgInputDecoration('Email', hint: 'name@company.com'),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<ProjectRole>(
          value: _role,
          dropdownColor: orgCard,
          style: const TextStyle(color: Colors.white),
          decoration: orgInputDecoration('Role'),
          items: [for (final r in ProjectRole.selectable) DropdownMenuItem(value: r, child: Text(r.label))],
          onChanged: (v) => setState(() => _role = v ?? _role),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _company,
          style: const TextStyle(color: Colors.white),
          textCapitalization: TextCapitalization.words,
          decoration: orgInputDecoration('Company (optional)', hint: 'e.g. PixelCraft Studio'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _rate,
          style: const TextStyle(color: Colors.white),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: orgInputDecoration('Hourly rate (optional)', hint: 'e.g. 60'),
        ),
        const SizedBox(height: 22),
        OrgPrimaryButton(label: 'Send invitation', loading: _loading, onPressed: _send),
      ],
    );
  }
}

class EditMemberSheet extends StatefulWidget {
  const EditMemberSheet({super.key, required this.projectId, required this.member});
  final String projectId;
  final ProjectMember member;

  @override
  State<EditMemberSheet> createState() => _EditMemberSheetState();
}

class _EditMemberSheetState extends State<EditMemberSheet> {
  late final ProjectRole _initialRole =
      ProjectRole.selectable.contains(widget.member.role) ? widget.member.role : ProjectRole.projectManager;
  late ProjectRole _role = _initialRole;
  late final _rate = TextEditingController(
    text: widget.member.hourlyRate == null ? '' : projMoney(widget.member.hourlyRate!).substring(1),
  );
  late final _company = TextEditingController(text: widget.member.companyName ?? '');
  bool _loading = false;

  @override
  void dispose() {
    _rate.dispose();
    _company.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final rateText = _rate.text.trim();
    final rate = rateText.isEmpty ? null : double.tryParse(rateText);
    if (rateText.isNotEmpty && rate == null) {
      orgToast(context, 'Enter a valid hourly rate', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await ProjectRepository.instance.updateMember(
        widget.projectId,
        widget.member.user.id,
        role: _role == _initialRole ? null : _role,
        hourlyRate: rate,
        companyName: _company.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProjSheetTitle(widget.member.user.name),
          DropdownButtonFormField<ProjectRole>(
            value: _role,
            dropdownColor: orgCard,
            style: const TextStyle(color: Colors.white),
            decoration: orgInputDecoration('Role'),
            items: [for (final r in ProjectRole.selectable) DropdownMenuItem(value: r, child: Text(r.label))],
            onChanged: (v) => setState(() => _role = v ?? _role),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _company,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.words,
            decoration: orgInputDecoration('Company'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _rate,
            style: const TextStyle(color: Colors.white),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: orgInputDecoration('Hourly rate'),
          ),
          const SizedBox(height: 22),
          OrgPrimaryButton(label: 'Save changes', loading: _loading, onPressed: _save),
        ],
      ),
    );
  }
}

class TaskFormSheet extends StatefulWidget {
  const TaskFormSheet({
    super.key,
    required this.projectId,
    required this.members,
    this.task,
  });
  final String projectId;
  final List<ProjectMember> members;
  final ProjectTask? task;

  @override
  State<TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends State<TaskFormSheet> {
  late final _title = TextEditingController(text: widget.task?.title ?? '');
  late final _desc = TextEditingController(text: widget.task?.description ?? '');
  late ProjectTaskPriority? _priority = widget.task?.priority;
  late String? _assigneeId = widget.task?.assigneeId;
  late DateTime? _due = widget.task?.dueDate;
  bool _loading = false;

  bool get _editing => widget.task != null;

  List<ProjectMember> get _freelancers =>
      widget.members.where((m) => m.role == ProjectRole.freelancer).toList();

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final priority = _priority;
    final assigneeId = _assigneeId;
    final due = _due;
    if (title.isEmpty) {
      orgToast(context, 'Task title is required', error: true);
      return;
    }
    if (priority == null) {
      orgToast(context, 'Select a priority', error: true);
      return;
    }
    if (assigneeId == null) {
      orgToast(context, 'Select a freelancer to assign this task to', error: true);
      return;
    }
    if (due == null) {
      orgToast(context, 'Select a due date', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final repo = ProjectRepository.instance;
      final ProjectTask saved;
      if (_editing) {
        saved = await repo.updateTask(
          widget.projectId,
          widget.task!.id,
          title: title,
          description: _desc.text.trim(),
          priority: priority,
          assigneeId: assigneeId,
          dueDate: due,
        );
      } else {
        saved = await repo.createTask(
          widget.projectId,
          title: title,
          description: _desc.text.trim(),
          priority: priority,
          assigneeId: assigneeId,
          dueDate: due,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final freelancers = _freelancers;
    final ids = freelancers.map((m) => m.user.id).toSet();
    final assigneeValue = ids.contains(_assigneeId) ? _assigneeId : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProjSheetTitle(_editing ? 'Edit task' : 'New task'),
          TextField(
            controller: _title,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.sentences,
            decoration: orgInputDecoration('Title'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _desc,
            style: const TextStyle(color: Colors.white),
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: orgInputDecoration('Description (optional)'),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<ProjectTaskPriority>(
            value: _priority,
            dropdownColor: orgCard,
            style: const TextStyle(color: Colors.white),
            decoration: orgInputDecoration('Priority'),
            items: [for (final p in ProjectTaskPriority.values) DropdownMenuItem(value: p, child: Text(p.label))],
            onChanged: (v) => setState(() => _priority = v),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: assigneeValue,
            dropdownColor: orgCard,
            isExpanded: true,
            style: const TextStyle(color: Colors.white),
            decoration: orgInputDecoration('Assignee'),
            items: [
              for (final m in freelancers)
                DropdownMenuItem<String>(
                  value: m.user.id,
                  child: Text(m.user.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _assigneeId = v),
          ),
          if (freelancers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'No freelancers in this project yet. Invite one from the Members tab.',
                style: TextStyle(color: orgMuted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 14),
          ProjDateField(label: 'Due date', value: _due, onChanged: (d) => setState(() => _due = d)),
          const SizedBox(height: 22),
          OrgPrimaryButton(label: _editing ? 'Save changes' : 'Create task', loading: _loading, onPressed: _save),
        ],
      ),
    );
  }
}

class SubmitDeliverableSheet extends StatefulWidget {
  const SubmitDeliverableSheet({super.key, required this.projectId, required this.task});
  final String projectId;
  final ProjectTask task;

  @override
  State<SubmitDeliverableSheet> createState() => _SubmitDeliverableSheetState();
}

class _SubmitDeliverableSheetState extends State<SubmitDeliverableSheet> {
  final _url = TextEditingController();
  final _note = TextEditingController();
  bool _loading = false;
  bool _uploading = false;
  double _progress = 0;
  String? _fileName;

  @override
  void dispose() {
    _url.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final f = await FilePicker.pickFile(type: FileType.any);
      final path = f?.path;
      final name = f?.name;
      if (path == null || name == null) return;
      await UploadService.ensureWithinLimit(path, name);
      setState(() {
        _uploading = true;
        _progress = 0;
      });
      final result = await UploadService.instance.upload(
        path: path,
        fileName: name,
        folder: 'project_deliverables',
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _url.text = result.url;
        _fileName = name;
      });
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    final url = _url.text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      orgToast(context, 'Provide a valid deliverable link or upload a file', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final task = await ProjectRepository.instance.submitDeliverable(
        widget.projectId,
        widget.task.id,
        url: url,
        note: _note.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, task);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProjSheetTitle('Submit deliverable'),
          Text(widget.task.title, style: const TextStyle(color: orgMuted, fontSize: 13)),
          const SizedBox(height: 14),
          TextField(
            controller: _url,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: orgInputDecoration('Deliverable URL', hint: 'https://...'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _uploading ? null : _pickFile,
            icon: _uploading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, value: _progress > 0 ? _progress : null, color: orgTeal),
                  )
                : const Icon(Icons.upload_file_rounded, size: 18, color: orgTeal),
            label: Text(
              _fileName ?? 'Upload a file instead',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              side: const BorderSide(color: orgBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            style: const TextStyle(color: Colors.white),
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: orgInputDecoration('Notes for the reviewer (optional)'),
          ),
          const SizedBox(height: 22),
          OrgPrimaryButton(label: 'Submit for review', loading: _loading || _uploading, onPressed: _submit),
        ],
      ),
    );
  }
}

class ReviewDeliverableSheet extends StatefulWidget {
  const ReviewDeliverableSheet({super.key, required this.projectId, required this.task, required this.approve});
  final String projectId;
  final ProjectTask task;
  final bool approve;

  @override
  State<ReviewDeliverableSheet> createState() => _ReviewDeliverableSheetState();
}

class _ReviewDeliverableSheetState extends State<ReviewDeliverableSheet> {
  final _feedback = TextEditingController();
  bool _loading = false;
  bool _uploading = false;
  double _progress = 0;
  String? _fileName;
  String? _fileUrl;

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final f = await FilePicker.pickFile(type: FileType.any);
      final path = f?.path;
      final name = f?.name;
      if (path == null || name == null) return;
      await UploadService.ensureWithinLimit(path, name);
      setState(() {
        _uploading = true;
        _progress = 0;
      });
      final result = await UploadService.instance.upload(
        path: path,
        fileName: name,
        folder: 'project_feedback',
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _fileUrl = result.url;
        _fileName = name;
      });
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    final feedback = _feedback.text.trim();
    if (!widget.approve && feedback.isEmpty && _fileUrl == null) {
      orgToast(context, 'Tell the assignee what needs to change', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final task = await ProjectRepository.instance.reviewDeliverable(
        widget.projectId,
        widget.task.id,
        approved: widget.approve,
        feedback: feedback,
        fileUrl: _fileUrl,
      );
      if (!mounted) return;
      Navigator.pop(context, task);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProjSheetTitle(widget.approve ? 'Approve deliverable' : 'Request changes'),
          Text(widget.task.title, style: const TextStyle(color: orgMuted, fontSize: 13)),
          const SizedBox(height: 14),
          TextField(
            controller: _feedback,
            style: const TextStyle(color: Colors.white),
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: orgInputDecoration(widget.approve ? 'Feedback (optional)' : 'What needs to change?'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _uploading || _loading ? null : _pickFile,
            icon: _uploading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, value: _progress > 0 ? _progress : null, color: orgTeal),
                  )
                : const Icon(Icons.attach_file_rounded, size: 18, color: Colors.white),
            label: Text(
              _fileName ?? 'Attach a file (optional)',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              side: const BorderSide(color: orgBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _loading || _uploading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.approve ? projGreen : projRed,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      widget.approve ? 'Approve' : 'Request changes',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class AddResourceSheet extends StatefulWidget {
  const AddResourceSheet({super.key, required this.projectId});
  final String projectId;

  @override
  State<AddResourceSheet> createState() => _AddResourceSheetState();
}

class _AddResourceSheetState extends State<AddResourceSheet> {
  final _title = TextEditingController();
  String? _path;
  String? _fileName;
  bool _loading = false;
  double _progress = 0;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final f = await FilePicker.pickFile(type: FileType.any);
      final path = f?.path;
      final name = f?.name;
      if (path == null || name == null) return;
      await UploadService.ensureWithinLimit(path, name);
      setState(() {
        _path = path;
        _fileName = name;
        if (_title.text.trim().isEmpty) {
          final dot = name.lastIndexOf('.');
          _title.text = dot > 0 ? name.substring(0, dot) : name;
        }
      });
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  String _mime(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'zip':
        return 'application/zip';
      case 'txt':
        return 'text/plain';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'mp4':
        return 'video/mp4';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _add() async {
    final path = _path;
    final name = _fileName;
    if (path == null || name == null) {
      orgToast(context, 'Choose a file first', error: true);
      return;
    }
    final title = _title.text.trim().isEmpty ? name : _title.text.trim();
    setState(() {
      _loading = true;
      _progress = 0;
    });
    try {
      final size = await File(path).length();
      final uploaded = await UploadService.instance.upload(
        path: path,
        fileName: name,
        folder: 'project_resources',
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      final resource = await ProjectRepository.instance.addResource(
        widget.projectId,
        title: title,
        fileUrl: uploaded.url,
        fileName: name,
        fileType: _mime(name),
        fileSize: size,
      );
      if (!mounted) return;
      Navigator.pop(context, resource);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProjSheetTitle('Add resource'),
          OutlinedButton.icon(
            onPressed: _loading ? null : _pick,
            icon: const Icon(Icons.attach_file_rounded, size: 18, color: orgTeal),
            label: Text(
              _fileName ?? 'Choose a file',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: orgBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _title,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.sentences,
            decoration: orgInputDecoration('Title', hint: 'e.g. Brand Guidelines'),
          ),
          if (_loading) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              color: orgTeal,
              backgroundColor: orgField,
            ),
          ],
          const SizedBox(height: 22),
          OrgPrimaryButton(label: 'Upload', loading: _loading, onPressed: _add),
        ],
      ),
    );
  }
}
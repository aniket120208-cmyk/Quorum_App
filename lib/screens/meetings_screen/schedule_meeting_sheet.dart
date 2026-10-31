import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/meeting_api.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/models/meeting_models.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_sheets.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'meeting_widgets.dart';

class ScheduleMeetingSheet extends StatefulWidget {
  const ScheduleMeetingSheet({super.key, this.organization, this.team});
  final Organization? organization;
  final OrgTeam? team;

  @override
  State<ScheduleMeetingSheet> createState() => _ScheduleMeetingSheetState();
}

class _ScheduleMeetingSheetState extends State<ScheduleMeetingSheet> {
  final _titleCtrl = TextEditingController();
  late MeetingScope _scope = _scopes.isEmpty ? MeetingScope.personal : _scopes.first;
  late Organization? _org = widget.organization;
  late OrgTeam? _team = widget.team;
  List<Organization>? _orgs;
  bool _scheduled = false;
  DateTime? _start;
  String? _titleError;
  String? _formError;
  bool _loadingPicker = false;
  bool _saving = false;

  List<MeetingScope> get _scopes {
    if (widget.team != null) return const [MeetingScope.team];
    final org = widget.organization;
    if (org != null) {
      return [
        if (orgIsAdmin(org.role)) MeetingScope.organization,
        if (orgCanInvite(org.role)) MeetingScope.team,
      ];
    }
    return MeetingScope.values;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<List<Organization>> _eligibleOrgs() async {
    _orgs ??= await OrganizationRepository.instance.organizations();
    return _orgs!.where((o) => _scope == MeetingScope.team ? orgCanInvite(o.role) : orgIsAdmin(o.role)).toList();
  }

  Future<void> _pickOrganization() async {
    if (_loadingPicker) return;
    setState(() => _loadingPicker = true);
    try {
      final orgs = await _eligibleOrgs();
      if (!mounted) return;
      if (orgs.isEmpty) {
        orgToast(
          context,
          _scope == MeetingScope.team
              ? 'You need to lead a team or be an admin to schedule team meetings'
              : 'You need to be an organization admin to schedule organization meetings',
          error: true,
        );
        return;
      }
      final picked = await showOrgSheet<Organization>(
        context,
        _ChoiceSheet<Organization>(title: 'Choose organization', items: orgs, label: (o) => o.name),
      );
      if (picked == null || !mounted) return;
      setState(() {
        if (_org?.id != picked.id) _team = null;
        _org = picked;
        _formError = null;
      });
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingPicker = false);
    }
  }

  Future<void> _pickTeam() async {
    final org = _org;
    if (org == null) {
      setState(() => _formError = 'Choose an organization first');
      return;
    }
    if (_loadingPicker) return;
    setState(() => _loadingPicker = true);
    try {
      final teams = await OrganizationRepository.instance.teams(org.id);
      if (!mounted) return;
      if (teams.isEmpty) {
        orgToast(context, 'This organization has no teams yet', error: true);
        return;
      }
      final picked = await showOrgSheet<OrgTeam>(
        context,
        _ChoiceSheet<OrgTeam>(title: 'Choose team', items: teams, label: (t) => t.name),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _team = picked;
        _formError = null;
      });
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingPicker = false);
    }
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final initial = _start ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return;
    setState(() {
      _start = DateTime(date.year, date.month, date.day, time?.hour ?? initial.hour, time?.minute ?? initial.minute);
      _formError = null;
    });
  }

  void _toggleScheduled(bool value) {
    setState(() {
      _scheduled = value;
      _formError = null;
      if (value && _start == null) {
        final now = DateTime.now();
        _start = DateTime(now.year, now.month, now.day, now.hour + 1);
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleCtrl.text.trim();
    String? titleError;
    String? formError;
    if (title.length > 200) {
      titleError = 'Meeting title cannot exceed 200 characters';
    }
    if (_scope != MeetingScope.personal && _org == null) {
      formError = 'Choose an organization';
    } else if (_scope == MeetingScope.team && _team == null) {
      formError = 'Choose a team';
    } else if (_scheduled && (_start == null || !_start!.isAfter(DateTime.now()))) {
      formError = 'Choose a start time in the future';
    }
    if (titleError != null || formError != null) {
      setState(() {
        _titleError = titleError;
        _formError = formError;
      });
      return;
    }
    setState(() {
      _titleError = null;
      _formError = null;
      _saving = true;
    });
    try {
      final meeting = await MeetingApi.instance.createScopedMeeting(
        title: title,
        scope: _scope,
        organizationId: _org?.id,
        teamId: _team?.id,
        scheduledStartTime: _scheduled ? _start : null,
      );
      if (!mounted) return;
      Navigator.pop(context, meeting);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _tile({
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
            trailing ?? const Icon(Icons.keyboard_arrow_down_rounded, color: orgMuted),
          ],
        ),
      ),
    );
  }

  Widget _scopeRow() {
    final scopes = _scopes;
    if (scopes.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final scope in scopes)
            ChoiceChip(
              avatar: Icon(meetingScopeIcon(scope), size: 16, color: Colors.white),
              label: Text(scope.label),
              selected: scope == _scope,
              onSelected: _saving
                  ? null
                  : (_) => setState(() {
                        _scope = scope;
                        _formError = null;
                        if (scope == MeetingScope.personal) {
                          _org = widget.organization;
                          _team = widget.team;
                        }
                        if (scope != MeetingScope.team && widget.team == null) _team = null;
                      }),
              showCheckmark: false,
              selectedColor: orgAccent,
              backgroundColor: orgField,
              side: const BorderSide(color: orgBorder),
              labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final start = _start;
    final needsOrg = _scope != MeetingScope.personal;
    final needsTeam = _scope == MeetingScope.team;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 18),
            child: Text(
              'New meeting',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          TextField(
            controller: _titleCtrl,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.sentences,
            decoration: orgInputDecoration('Title (optional)', hint: 'e.g. Quarterly roadmap').copyWith(errorText: _titleError),
          ),
          const SizedBox(height: 14),
          _scopeRow(),
          if (needsOrg) ...[
            _tile(
              icon: Icons.business_rounded,
              label: 'Organization',
              value: _org?.name ?? 'Choose an organization',
              onTap: widget.organization != null || _saving ? null : _pickOrganization,
              trailing: widget.organization != null
                  ? const SizedBox.shrink()
                  : _loadingPicker
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: orgTeal),
                        )
                      : null,
            ),
            const SizedBox(height: 14),
          ],
          if (needsTeam) ...[
            _tile(
              icon: Icons.groups_2_outlined,
              label: 'Team',
              value: _team?.name ?? 'Choose a team',
              onTap: widget.team != null || _saving ? null : _pickTeam,
              trailing: widget.team != null ? const SizedBox.shrink() : null,
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              const Expanded(
                child: Text('Schedule for later', style: TextStyle(color: Colors.white, fontSize: 14)),
              ),
              Switch(
                value: _scheduled,
                activeColor: orgTeal,
                onChanged: _saving ? null : _toggleScheduled,
              ),
            ],
          ),
          if (_scheduled) ...[
            const SizedBox(height: 6),
            _tile(
              icon: Icons.event_rounded,
              label: 'Starts',
              value: start == null ? 'Choose date and time' : meetingStartLabel(context, start),
              onTap: _saving ? null : _pickStart,
              trailing: const Icon(Icons.edit_calendar_outlined, color: orgMuted, size: 20),
            ),
            const SizedBox(height: 8),
            const Text(
              'Members can join up to 15 minutes before the start time. You can join anytime as host.',
              style: TextStyle(color: orgMuted, fontSize: 11.5),
            ),
          ],
          if (_formError != null) ...[
            const SizedBox(height: 12),
            Text(_formError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
          ],
          const SizedBox(height: 22),
          OrgPrimaryButton(
            label: _scheduled ? 'Schedule meeting' : 'Start meeting now',
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

class _ChoiceSheet<T> extends StatelessWidget {
  const _ChoiceSheet({required this.title, required this.items, required this.label});
  final String title;
  final List<T> items;
  final String Function(T) label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(label(items[index]), style: const TextStyle(color: Colors.white)),
                trailing: const Icon(Icons.chevron_right_rounded, color: orgMuted),
                onTap: () => Navigator.pop(context, items[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
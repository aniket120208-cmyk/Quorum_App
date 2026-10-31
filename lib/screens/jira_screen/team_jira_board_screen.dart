import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/jira_repository.dart';
import 'package:quorum_app/models/jira_models.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_sheets.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'jira_settings_screen.dart';
import 'jira_widgets.dart';

class TeamJiraBoardScreen extends StatefulWidget {
  const TeamJiraBoardScreen({super.key, required this.organization, required this.team});
  final Organization organization;
  final OrgTeam team;

  @override
  State<TeamJiraBoardScreen> createState() => _TeamJiraBoardScreenState();
}

class _TeamJiraBoardScreenState extends State<TeamJiraBoardScreen> {
  final _repo = JiraRepository.instance;
  List<JiraTicket> _tickets = [];
  OrgJiraStatus? _orgStatus;
  bool _loading = true;
  String? _error;
  Timer? _poller;
  int _inFlight = 0;
  String? _myAccountId;
  bool _onlyMine = false;

  bool get _configured => _orgStatus?.isConnected == true;

  List<JiraTicket> get _visible => _onlyMine && _myAccountId != null
      ? _tickets.where((t) => t.assigneeAccountId == _myAccountId).toList()
      : _tickets;

  @override
  void initState() {
    super.initState();
    _load();
    unawaited(_resolveAccount());
    _poller = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_loading && _inFlight == 0) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _resolveAccount() async {
    if (_myAccountId != null) return;
    try {
      final id = await _repo.myAccountId();
      if (!mounted || id == _myAccountId) return;
      setState(() => _myAccountId = id);
    } catch (_) {}
  }

  String _signature(bool configured, List<JiraTicket> tickets) =>
      '$configured#${tickets.map((t) => '${t.jiraKey}|${t.jiraStatus}|${t.jiraSummary}|${t.priority}').join(';')}';

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final status = await _repo.orgStatus(widget.organization.id);
      final tickets = status.isConnected
          ? await _repo.teamTickets(widget.organization.id, widget.team.id)
          : <JiraTicket>[];
      if (!mounted) return;
      if (silent && _inFlight > 0) return;
      if (silent && !_loading && _error == null && _signature(status.isConnected, tickets) == _signature(_configured, _tickets)) {
        return;
      }
      setState(() {
        _orgStatus = status;
        _tickets = tickets;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _orgStatus == null) _error = errorText(e);
      });
    }
  }

  Future<void> _changeStatus(JiraTicket ticket, JiraColumn column) async {
    final previous = ticket;
    _inFlight++;
    setState(() {
      _tickets = [
        for (final t in _tickets)
          t.jiraKey == ticket.jiraKey ? t.copyWith(jiraStatus: column.label, statusCategory: column.category) : t,
      ];
    });
    try {
      final confirmed = await _repo.transition(
        widget.organization.id,
        widget.team.id,
        ticket.jiraKey,
        column.label,
      );
      _inFlight--;
      if (!mounted) return;
      setState(() {
        _tickets = [
          for (final t in _tickets)
            t.jiraKey == ticket.jiraKey
                ? t.copyWith(jiraStatus: confirmed ?? column.label, statusCategory: column.category)
                : t,
        ];
      });
    } catch (e) {
      _inFlight--;
      if (!mounted) return;
      setState(() {
        _tickets = [for (final t in _tickets) t.jiraKey == ticket.jiraKey ? previous : t];
      });
      orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _create() async {
    final created = await showOrgSheet<bool>(
      context,
      CreateJiraTicketSheet(
        organization: widget.organization,
        team: widget.team,
        myAccountId: _myAccountId,
      ),
    );
    if (created == true) {
      await _load(silent: true);
      if (mounted) orgToast(context, 'Jira ticket created');
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => JiraSettingsScreen(organization: widget.organization)),
    );
    if (mounted) _load();
  }

  List<JiraTicket> _byColumn(JiraColumn column) => _visible.where((t) => t.column == column).toList();

  @override
  Widget build(BuildContext context) {
    final showBoard = !_loading && _error == null && _configured;
    return DefaultTabController(
      length: JiraColumn.values.length,
      child: Scaffold(
        backgroundColor: orgBg,
        appBar: AppBar(
          backgroundColor: orgBg,
          elevation: 0,
          foregroundColor: Colors.white,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Jira Tickets', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text(
                _orgStatus?.projectKey != null ? '${widget.team.name} · ${_orgStatus!.projectKey}' : widget.team.name,
                style: const TextStyle(fontSize: 12, color: orgMuted),
              ),
            ],
          ),
          bottom: showBoard
              ? TabBar(
                  indicatorColor: orgTeal,
                  labelColor: Colors.white,
                  unselectedLabelColor: orgMuted,
                  dividerColor: orgBorder,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  tabs: [
                    for (final column in JiraColumn.values) Tab(text: '${column.label} (${_byColumn(column).length})'),
                  ],
                )
              : null,
        ),
        floatingActionButton: showBoard
            ? FloatingActionButton.extended(
                onPressed: _create,
                backgroundColor: orgAccent,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New ticket', style: TextStyle(fontWeight: FontWeight.w700)),
              )
            : null,
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: orgTeal))
            : _error != null
                ? JiraMessageView(
                    icon: Icons.error_outline_rounded,
                    message: _error!,
                    actionLabel: 'Retry',
                    onAction: _load,
                  )
                : !_configured
                    ? JiraMessageView(
                        icon: Icons.link_off_rounded,
                        message: 'Jira is not configured for this organization. Ask an Org Admin to set up Jira in Org Settings.',
                        actionLabel: orgIsAdmin(widget.organization.role) ? 'Set up Jira' : 'Refresh',
                        onAction: orgIsAdmin(widget.organization.role) ? _openSettings : _load,
                      )
                    : Column(
                        children: [
                          if (_myAccountId != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                                child: FilterChip(
                                  label: const Text('Assigned to me'),
                                  selected: _onlyMine,
                                  onSelected: (value) => setState(() => _onlyMine = value),
                                  showCheckmark: false,
                                  avatar: const Icon(Icons.person_rounded, size: 16, color: Colors.white),
                                  selectedColor: orgAccent,
                                  backgroundColor: orgField,
                                  side: const BorderSide(color: orgBorder),
                                  labelStyle: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          Expanded(
                            child: TabBarView(
                              children: [for (final column in JiraColumn.values) _column(column)],
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }

  Widget _column(JiraColumn column) {
    final tickets = _byColumn(column);
    return RefreshIndicator(
      color: orgTeal,
      backgroundColor: orgCard,
      onRefresh: () => _load(silent: true),
      child: tickets.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                Center(
                  child: Text('No ${column.label.toLowerCase()} tickets', style: const TextStyle(color: orgMuted)),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
              itemCount: tickets.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final ticket = tickets[index];
                return JiraTicketCard(
                  ticket: ticket,
                  myAccountId: _myAccountId,
                  onMove: (next) => _changeStatus(ticket, next),
                );
              },
            ),
    );
  }
}

class CreateJiraTicketSheet extends StatefulWidget {
  const CreateJiraTicketSheet({
    super.key,
    required this.organization,
    required this.team,
    this.myAccountId,
  });
  final Organization organization;
  final OrgTeam team;
  final String? myAccountId;

  @override
  State<CreateJiraTicketSheet> createState() => _CreateJiraTicketSheetState();
}

class _CreateJiraTicketSheetState extends State<CreateJiraTicketSheet> {
  final _summaryCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _issueType = 'Task';
  String _priority = 'Medium';
  String? _assigneeId;
  List<JiraAssignee> _assignees = const [];
  bool _loadingAssignees = true;
  String? _assigneesError;
  String? _summaryError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadAssignees();
  }

  Future<void> _loadAssignees() async {
    setState(() {
      _loadingAssignees = true;
      _assigneesError = null;
    });
    try {
      final list = await JiraRepository.instance.assignees(widget.organization.id, widget.team.id);
      if (!mounted) return;
      setState(() {
        _assignees = list;
        _loadingAssignees = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _assigneesError = errorText(e);
        _loadingAssignees = false;
      });
    }
  }

  @override
  void dispose() {
    _summaryCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final summary = _summaryCtrl.text.trim();
    if (summary.isEmpty) {
      setState(() => _summaryError = 'Ticket summary is required');
      return;
    }
    setState(() {
      _summaryError = null;
      _saving = true;
    });
    try {
      await JiraRepository.instance.createTicket(
        widget.organization.id,
        widget.team.id,
        summary: summary,
        description: _descCtrl.text.trim(),
        issueType: _issueType,
        priority: _priority,
        assigneeAccountId: _assigneeId,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _choiceRow(String label, List<String> options, String value, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: orgMuted, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(option),
                selected: option == value,
                onSelected: _saving ? null : (_) => onChanged(option),
                showCheckmark: false,
                selectedColor: orgAccent,
                backgroundColor: orgField,
                side: const BorderSide(color: orgBorder),
                labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
              ),
          ],
        ),
      ],
    );
  }

  Widget _assigneeTile({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    String? subtitle,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? orgAccent.withValues(alpha: 0.18) : orgField,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? orgAccent : orgBorder),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 20,
              color: selected ? orgAccent : orgMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: orgMuted, fontSize: 11.5),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _assigneePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Assignee', style: TextStyle(color: orgMuted, fontSize: 12)),
        const SizedBox(height: 8),
        _assigneeTile(
          label: 'Unassigned',
          selected: _assigneeId == null,
          onTap: _saving ? null : () => setState(() => _assigneeId = null),
        ),
        if (_loadingAssignees)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: orgAccent),
              ),
            ),
          )
        else if (_assigneesError != null) ...[
          const SizedBox(height: 8),
          Text(_assigneesError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          TextButton(onPressed: _loadAssignees, child: const Text('Retry')),
        ] else if (_assignees.isEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'No team members with a connected Jira account yet.',
            style: TextStyle(color: orgMuted, fontSize: 11.5),
          ),
        ] else
          for (final person in _assignees) ...[
            const SizedBox(height: 8),
            _assigneeTile(
              label: person.accountId == widget.myAccountId ? '${person.name} (Me)' : person.name,
              subtitle: person.email,
              selected: _assigneeId == person.accountId,
              onTap: _saving ? null : () => setState(() => _assigneeId = person.accountId),
            ),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 18),
            child: Text(
              'New Jira ticket',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          TextField(
            controller: _summaryCtrl,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.sentences,
            decoration: orgInputDecoration('Summary', hint: 'e.g. Fix layout overflow on board').copyWith(errorText: _summaryError),
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
          const SizedBox(height: 16),
          _choiceRow('Issue type', const ['Task', 'Bug', 'Story'], _issueType, (v) => setState(() => _issueType = v)),
          const SizedBox(height: 16),
          _choiceRow('Priority', const ['High', 'Medium', 'Low'], _priority, (v) => setState(() => _priority = v)),
          const SizedBox(height: 16),
          _assigneePicker(),
          const SizedBox(height: 22),
          OrgPrimaryButton(label: 'Create ticket', loading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/github_repository.dart';
import 'package:quorum_app/models/github_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_sheets.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'github_paged_list.dart';
import 'github_widgets.dart';

class GithubIssuesTab extends StatefulWidget {
  const GithubIssuesTab({super.key, required this.teamId});
  final String teamId;

  @override
  State<GithubIssuesTab> createState() => _GithubIssuesTabState();
}

class _GithubIssuesTabState extends State<GithubIssuesTab> with AutomaticKeepAliveClientMixin {
  final _repo = GithubRepository.instance;
  final _listKey = GlobalKey<GithubPagedListState<GithubIssue>>();
  String _filter = 'open';

  @override
  bool get wantKeepAlive => true;

  Future<void> _toggle(GithubIssue issue) async {
    final next = issue.isOpen ? 'closed' : 'open';
    final list = _listKey.currentState;
    if (_filter == 'all') {
      list?.updateWhere((i) => i.number == issue.number, (i) => i.copyWith(state: next));
    } else {
      list?.removeWhere((i) => i.number == issue.number);
    }
    try {
      await _repo.setIssueState(widget.teamId, issue.number, next);
      if (mounted) orgToast(context, next == 'closed' ? 'Issue #${issue.number} closed' : 'Issue #${issue.number} reopened');
    } catch (e) {
      if (!mounted) return;
      orgToast(context, errorText(e), error: true);
      list?.reload(silent: true);
    }
  }

  Future<void> _create() async {
    final created = await showOrgSheet<bool>(context, CreateGithubIssueSheet(teamId: widget.teamId));
    if (created == true) {
      _listKey.currentState?.reload(silent: true);
      if (mounted) orgToast(context, 'GitHub issue created');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Stack(
      children: [
        Column(
          children: [
            GithubStateFilter(
              value: _filter,
              onChanged: (value) {
                if (value == _filter) return;
                setState(() => _filter = value);
                _listKey.currentState?.reload();
              },
            ),
            Expanded(
              child: GithubPagedList<GithubIssue>(
                key: _listKey,
                bottomPadding: 96,
                emptyText: _filter == 'all' ? 'No issues yet' : 'No $_filter issues',
                fetch: (page, perPage) => _repo.issues(widget.teamId, state: _filter, page: page, perPage: perPage),
                itemBuilder: (context, issue) => GithubIssueCard(
                  issue: issue,
                  onToggleState: () => _toggle(issue),
                  onOpen: () => openGithubUrl(context, issue.htmlUrl),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'github_new_issue',
            onPressed: _create,
            backgroundColor: orgAccent,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New issue', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

class GithubPullsTab extends StatefulWidget {
  const GithubPullsTab({super.key, required this.teamId});
  final String teamId;

  @override
  State<GithubPullsTab> createState() => _GithubPullsTabState();
}

class _GithubPullsTabState extends State<GithubPullsTab> with AutomaticKeepAliveClientMixin {
  final _repo = GithubRepository.instance;
  final _listKey = GlobalKey<GithubPagedListState<GithubPull>>();
  String _filter = 'open';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        GithubStateFilter(
          value: _filter,
          onChanged: (value) {
            if (value == _filter) return;
            setState(() => _filter = value);
            _listKey.currentState?.reload();
          },
        ),
        Expanded(
          child: GithubPagedList<GithubPull>(
            key: _listKey,
            emptyText: _filter == 'all' ? 'No pull requests yet' : 'No $_filter pull requests',
            fetch: (page, perPage) => _repo.pulls(widget.teamId, state: _filter, page: page, perPage: perPage),
            itemBuilder: (context, pull) => GithubPullCard(
              pull: pull,
              onOpen: () => openGithubUrl(context, pull.htmlUrl),
            ),
          ),
        ),
      ],
    );
  }
}

class GithubCommitsTab extends StatefulWidget {
  const GithubCommitsTab({super.key, required this.teamId, this.defaultBranch});
  final String teamId;
  final String? defaultBranch;

  @override
  State<GithubCommitsTab> createState() => _GithubCommitsTabState();
}

class _GithubCommitsTabState extends State<GithubCommitsTab> with AutomaticKeepAliveClientMixin {
  final _repo = GithubRepository.instance;
  final _listKey = GlobalKey<GithubPagedListState<GithubCommit>>();
  List<String> _branches = const [];
  String? _branch;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final list = await _repo.branches(widget.teamId);
      if (!mounted) return;
      setState(() => _branches = list);
    } catch (_) {}
  }

  Widget _branchPicker() {
    final options = <String>{..._branches};
    final current = _branch != null && options.contains(_branch) ? _branch : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: orgField,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: orgBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.account_tree_outlined, size: 18, color: orgTeal),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: current,
                  isExpanded: true,
                  dropdownColor: orgField,
                  iconEnabledColor: orgMuted,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        widget.defaultBranch == null ? 'Default branch' : '${widget.defaultBranch} (default)',
                      ),
                    ),
                    for (final name in options.where((n) => n != widget.defaultBranch))
                      DropdownMenuItem<String?>(value: name, child: Text(name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (value) {
                    if (value == _branch) return;
                    setState(() => _branch = value);
                    _listKey.currentState?.reload();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _branchPicker(),
        Expanded(
          child: GithubPagedList<GithubCommit>(
            key: _listKey,
            emptyText: 'No commits found',
            fetch: (page, perPage) => _repo.commits(widget.teamId, branch: _branch, page: page, perPage: perPage),
            itemBuilder: (context, commit) => GithubCommitTile(
              commit: commit,
              onOpen: () => openGithubUrl(context, commit.htmlUrl),
            ),
          ),
        ),
      ],
    );
  }
}

class CreateGithubIssueSheet extends StatefulWidget {
  const CreateGithubIssueSheet({super.key, required this.teamId});
  final String teamId;

  @override
  State<CreateGithubIssueSheet> createState() => _CreateGithubIssueSheetState();
}

class _CreateGithubIssueSheetState extends State<CreateGithubIssueSheet> {
  static const List<String> _suggestedLabels = ['bug', 'enhancement', 'documentation', 'frontend', 'backend'];

  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _labelsCtrl = TextEditingController();
  final Set<String> _labels = {};
  final Set<String> _assignees = {};
  List<GithubUser> _collaborators = const [];
  bool _loadingPeople = true;
  String? _peopleError;
  String? _titleError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _labelsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPeople() async {
    setState(() {
      _loadingPeople = true;
      _peopleError = null;
    });
    try {
      final list = await GithubRepository.instance.collaborators(widget.teamId);
      if (!mounted) return;
      setState(() {
        _collaborators = list;
        _loadingPeople = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _peopleError = errorText(e);
        _loadingPeople = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Issue title is required');
      return;
    }
    final extra = _labelsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
    final labels = <String>{..._labels, ...extra}.toList();
    setState(() {
      _titleError = null;
      _saving = true;
    });
    try {
      await GithubRepository.instance.createIssue(
        widget.teamId,
        title: title,
        body: _bodyCtrl.text.trim(),
        assignees: _assignees.toList(),
        labels: labels,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _label(String text) => Text(text, style: const TextStyle(color: orgMuted, fontSize: 12));

  Widget _labelPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Labels'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in _suggestedLabels)
              FilterChip(
                label: Text(name),
                selected: _labels.contains(name),
                onSelected: _saving
                    ? null
                    : (value) => setState(() => value ? _labels.add(name) : _labels.remove(name)),
                showCheckmark: false,
                selectedColor: orgAccent,
                backgroundColor: orgField,
                side: const BorderSide(color: orgBorder),
                labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _labelsCtrl,
          enabled: !_saving,
          style: const TextStyle(color: Colors.white),
          decoration: orgInputDecoration('Other labels (comma separated)', hint: 'e.g. ui, urgent'),
        ),
      ],
    );
  }

  Widget _assigneePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Assignees'),
        const SizedBox(height: 8),
        if (_loadingPeople)
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
        else if (_peopleError != null) ...[
          Text(_peopleError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          TextButton(onPressed: _loadPeople, child: const Text('Retry')),
        ] else if (_collaborators.isEmpty)
          const Text('No collaborators available to assign.', style: TextStyle(color: orgMuted, fontSize: 11.5))
        else
          for (final person in _collaborators) ...[
            _personTile(person),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _personTile(GithubUser person) {
    final selected = _assignees.contains(person.login);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _saving
          ? null
          : () => setState(() => selected ? _assignees.remove(person.login) : _assignees.add(person.login)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? orgAccent.withValues(alpha: 0.18) : orgField,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? orgAccent : orgBorder),
        ),
        child: Row(
          children: [
            GithubAvatar(login: person.login, url: person.avatarUrl, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                person.login,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? orgAccent : orgMuted,
            ),
          ],
        ),
      ),
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
              'New GitHub issue',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          TextField(
            controller: _titleCtrl,
            enabled: !_saving,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.sentences,
            decoration: orgInputDecoration('Title', hint: 'e.g. Fix navbar alignment on mobile').copyWith(errorText: _titleError),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _bodyCtrl,
            enabled: !_saving,
            style: const TextStyle(color: Colors.white),
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: orgInputDecoration('Description (optional)'),
          ),
          const SizedBox(height: 16),
          _labelPicker(),
          const SizedBox(height: 16),
          _assigneePicker(),
          const SizedBox(height: 14),
          OrgPrimaryButton(label: 'Create issue', loading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}
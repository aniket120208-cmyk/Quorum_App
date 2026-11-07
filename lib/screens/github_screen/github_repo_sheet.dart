import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/github_repository.dart';
import 'package:quorum_app/models/github_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'github_widgets.dart';

class GithubRepoPickerSheet extends StatefulWidget {
  const GithubRepoPickerSheet({super.key, required this.teamId, this.currentFullName});
  final String teamId;
  final String? currentFullName;

  @override
  State<GithubRepoPickerSheet> createState() => _GithubRepoPickerSheetState();
}

class _GithubRepoPickerSheetState extends State<GithubRepoPickerSheet> {
  static const int _perPage = 30;

  final _repo = GithubRepository.instance;
  final _search = TextEditingController();
  List<GithubRepoOption> _repos = [];
  String? _selected;
  String _query = '';
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _linking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentFullName;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.userRepos(page: 1, perPage: _perPage);
      if (!mounted) return;
      setState(() {
        _repos = list;
        _page = 1;
        _hasMore = list.length >= _perPage;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final list = await _repo.userRepos(page: _page + 1, perPage: _perPage);
      if (!mounted) return;
      final known = _repos.map((r) => r.fullName).toSet();
      setState(() {
        _repos = [..._repos, ...list.where((r) => !known.contains(r.fullName))];
        _page += 1;
        _hasMore = list.length >= _perPage;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _link() async {
    final name = _selected;
    if (name == null || _linking) return;
    setState(() => _linking = true);
    try {
      final linked = await _repo.linkRepo(widget.teamId, name);
      if (!mounted) return;
      Navigator.pop(context, linked);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  Widget _tile(GithubRepoOption repo) {
    final selected = repo.fullName == _selected;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _linking ? null : () => setState(() => _selected = repo.fullName),
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
              repo.isPrivate ? Icons.lock_outline_rounded : Icons.folder_open_rounded,
              size: 20,
              color: selected ? orgAccent : orgMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    repo.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  if (repo.defaultBranch != null)
                    Text(
                      'Default branch: ${repo.defaultBranch}',
                      style: const TextStyle(color: orgMuted, fontSize: 11.5),
                    ),
                ],
              ),
            ),
            if (repo.isPrivate) const GithubChip(label: 'Private', color: githubDraft),
            const SizedBox(width: 8),
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 20,
              color: selected ? orgAccent : orgMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: orgTeal)),
      );
    }
    if (_error != null) {
      return SizedBox(
        height: 200,
        child: GithubMessageView(
          icon: Icons.error_outline_rounded,
          message: _error!,
          actionLabel: 'Retry',
          onAction: _load,
        ),
      );
    }
    final q = _query.trim().toLowerCase();
    final visible = _repos.where((r) => q.isEmpty || r.fullName.toLowerCase().contains(q)).toList();
    if (visible.isEmpty && !_hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text('No repositories found', style: TextStyle(color: orgMuted))),
      );
    }
    return ListView(
      shrinkWrap: true,
      children: [
        for (final repo in visible) ...[
          _tile(repo),
          const SizedBox(height: 8),
        ],
        if (_hasMore)
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: _loadingMore ? null : _loadMore,
              child: _loadingMore
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: orgTeal),
                    )
                  : const Text('Load more', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.55;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Link a repository',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose the GitHub repository this team will track.',
            style: TextStyle(color: orgMuted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(color: Colors.white),
            decoration: orgInputDecoration('Search repositories').copyWith(
              prefixIcon: const Icon(Icons.search, color: orgMuted, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(constraints: BoxConstraints(maxHeight: maxHeight), child: _list()),
          const SizedBox(height: 14),
          OrgPrimaryButton(
            label: 'Link repository',
            loading: _linking,
            onPressed: _selected == null ? null : _link,
          ),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'package:quorum_app/screens/organization_screen/team_chat_screen.dart';

class MyTeamsScreen extends StatefulWidget {
  const MyTeamsScreen({super.key, required this.organizations});

  final List<Organization> organizations;

  @override
  State<MyTeamsScreen> createState() => _MyTeamsScreenState();
}

class _MyTeamsScreenState extends State<MyTeamsScreen> {
  final _repo = OrganizationRepository.instance;
  final Map<String, List<OrgTeam>> _teams = {};
  bool _loading = true;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait(
        widget.organizations.map((o) async {
          try {
            final list = await _repo.teams(o.id);
            return MapEntry(o.id, list.where((t) => t.isMember).toList());
          } catch (_) {
            return MapEntry(o.id, <OrgTeam>[]);
          }
        }),
      );
      if (!mounted) return;
      setState(() {
        _teams
          ..clear()
          ..addEntries(results);
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

  Future<void> _open(Organization org, OrgTeam team) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final members = await _repo.members(org.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TeamChatScreen(organization: org, team: team, members: members),
        ),
      );
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Widget _tile(Organization org, OrgTeam team) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(org, team),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: orgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: orgBorder),
          ),
          child: Row(
            children: [
              (team.avatar ?? '').isNotEmpty
                  ? OrgAvatar(name: team.name, logo: team.avatar, size: 40)
                  : Container(
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
                      style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      team.membersCount == 1 ? '1 member' : '${team.membersCount} members',
                      style: const TextStyle(color: orgMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: orgMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: orgTeal));
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted)),
            TextButton(
              onPressed: _load,
              child: const Text('Retry', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }
    final orgs = widget.organizations.where((o) => (_teams[o.id] ?? const []).isNotEmpty).toList();
    if (orgs.isEmpty) {
      return const Center(child: Text('You are not part of any team yet.', style: TextStyle(color: orgMuted)));
    }
    return RefreshIndicator(
      color: orgTeal,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          for (final org in orgs) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 10),
              child: Text(
                org.name,
                style: const TextStyle(color: orgMuted, fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
            for (final team in _teams[org.id]!) _tile(org, team),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('My teams', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: _body(),
    );
  }
}
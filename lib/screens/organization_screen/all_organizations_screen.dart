import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_detail_screen.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';

class AllOrganizationsScreen extends StatefulWidget {
  const AllOrganizationsScreen({super.key, this.organizations = const []});

  final List<Organization> organizations;

  @override
  State<AllOrganizationsScreen> createState() => _AllOrganizationsScreenState();
}

class _AllOrganizationsScreenState extends State<AllOrganizationsScreen> {
  late List<Organization> _orgs = widget.organizations;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = OrganizationRepository.instance;
      final orgs = await repo.organizations(limit: 50);
      if (!mounted) return;
      setState(() {
        _orgs = orgs;
        _loading = false;
        _error = null;
      });
      final withCounts = await Future.wait(orgs.map(_withCounts));
      if (!mounted) return;
      setState(() => _orgs = withCounts);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_orgs.isEmpty) _error = errorText(e);
      });
    }
  }

  Future<Organization> _withCounts(Organization org) async {
    final repo = OrganizationRepository.instance;
    var members = org.membersCount;
    var teams = org.teamsCount;
    try {
      members = (await repo.members(org.id)).length;
    } catch (_) {}
    try {
      teams = (await repo.teams(org.id)).length;
    } catch (_) {}
    return org.copyWith(membersCount: members, teamsCount: teams);
  }

  Future<void> _open(Organization org) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OrganizationDetailScreen(organization: org)),
    );
    if (!mounted) return;
    await _load();
  }

  Widget _body() {
    if (_loading && _orgs.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: orgTeal));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: orgMuted, size: 42),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
                child: const Text('Retry', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }
    if (_orgs.isEmpty) {
      return const Center(
        child: Text('No organizations yet', style: TextStyle(color: orgMuted, fontSize: 14)),
      );
    }
    return RefreshIndicator(
      color: orgTeal,
      backgroundColor: orgCard,
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).padding.bottom),
        itemCount: _orgs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => OrgListTile(
          organization: _orgs[i],
          onTap: () => _open(_orgs[i]),
        ),
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
        title: Text(
          _orgs.length > 1 ? 'Your Organizations (${_orgs.length})' : 'Your Organizations',
          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: _body(),
    );
  }
}
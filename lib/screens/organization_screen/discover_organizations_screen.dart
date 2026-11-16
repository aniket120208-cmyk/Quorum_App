import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'join_organization_screen.dart';
import 'organization_detail_screen.dart';
import 'organization_sheets.dart';
import 'organization_widgets.dart';

class DiscoverOrganizationsScreen extends StatefulWidget {
  const DiscoverOrganizationsScreen({super.key, this.initialScope = OrgSearchScope.all});

  final OrgSearchScope initialScope;

  @override
  State<DiscoverOrganizationsScreen> createState() => _DiscoverOrganizationsScreenState();
}

class _DiscoverOrganizationsScreenState extends State<DiscoverOrganizationsScreen> {
  final _repo = OrganizationRepository.instance;
  final _ctrl = TextEditingController();
  Timer? _debounce;
  late OrgSearchScope _scope = widget.initialScope;
  List<Organization> _items = const [];
  bool _loading = true;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
    setState(() {});
  }

  Future<void> _search() async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.search(query: _ctrl.text, scope: _scope, limit: 50);
      if (!mounted || token != _token) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _error = errorText(e);
        _loading = false;
      });
    }
  }

  void _setScope(OrgSearchScope scope) {
    if (scope == _scope) return;
    setState(() => _scope = scope);
    _search();
  }

  Future<void> _open(Organization org) async {
    if (org.isMember) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OrganizationDetailScreen(organization: org)),
      );
      if (mounted) _search();
      return;
    }
    final join = await showOrgSheet<bool>(context, _OrganizationInfoSheet(org: org));
    if (join != true || !mounted) return;
    final joined = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const JoinOrganizationScreen()),
    );
    if (joined == true && mounted) Navigator.pop(context, true);
  }

  Widget _scopeChip(String label, OrgSearchScope scope) {
    final selected = _scope == scope;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setScope(scope),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? orgAccent : orgField,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : orgMuted,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  String _meta(Organization o) {
    final parts = <String>[
      if (o.industry != null) o.industry!,
      if (o.teamSize != null) '${o.teamSize} people',
      '${o.membersCount} ${o.membersCount == 1 ? 'member' : 'members'}',
    ];
    return parts.join(' • ');
  }

  Widget _tile(Organization o) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _open(o),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: orgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: orgBorder),
        ),
        child: Row(
          children: [
            OrgAvatar(name: o.name, logo: o.logo, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700),
                  ),
                  if (o.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      o.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: orgMuted, fontSize: 12.5, height: 1.3),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(_meta(o), style: const TextStyle(color: orgMuted, fontSize: 11.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (o.isMember)
              OrgRoleBadge(role: o.role)
            else
              const Icon(Icons.chevron_right_rounded, color: orgMuted),
          ],
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
              onPressed: _search,
              child: const Text('Try again', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          _ctrl.text.trim().isEmpty ? 'No organizations to show yet.' : 'No organizations match your search.',
          style: const TextStyle(color: orgMuted),
        ),
      );
    }
    return RefreshIndicator(
      color: orgTeal,
      onRefresh: _search,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [for (final o in _items) _tile(o)],
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
        title: const Text('Organizations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _ctrl,
              onChanged: _onChanged,
              onSubmitted: (_) => _search(),
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by name or description',
                hintStyle: const TextStyle(color: orgMuted),
                prefixIcon: const Icon(Icons.search_rounded, color: orgMuted),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, color: orgMuted, size: 18),
                        onPressed: () {
                          _ctrl.clear();
                          _search();
                        },
                      ),
                isDense: true,
                filled: true,
                fillColor: orgField,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                _scopeChip('Discover', OrgSearchScope.all),
                const SizedBox(width: 8),
                _scopeChip('My organizations', OrgSearchScope.mine),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }
}

class _OrganizationInfoSheet extends StatelessWidget {
  const _OrganizationInfoSheet({required this.org});

  final Organization org;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OrgAvatar(name: org.name, logo: org.logo, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  org.name,
                  style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if (org.description != null) ...[
            const SizedBox(height: 14),
            Text(org.description!, style: const TextStyle(color: orgMuted, fontSize: 14, height: 1.4)),
          ],
          const SizedBox(height: 14),
          Text(
            [
              if (org.industry != null) org.industry!,
              if (org.teamSize != null) '${org.teamSize} people',
              '${org.membersCount} ${org.membersCount == 1 ? 'member' : 'members'}',
            ].join(' • '),
            style: const TextStyle(color: orgMuted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          const Text(
            'Joining is by invitation. Ask an admin of this organization for an invite link.',
            style: TextStyle(color: orgMuted, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 20),
          OrgPrimaryButton(
            label: 'I have an invite link',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
  }
}
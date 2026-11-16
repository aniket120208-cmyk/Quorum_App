import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'organization_sheets.dart';
import 'organization_widgets.dart';

class OrganizationInvitesScreen extends StatefulWidget {
  const OrganizationInvitesScreen({super.key, required this.organization});

  final Organization organization;

  @override
  State<OrganizationInvitesScreen> createState() => _OrganizationInvitesScreenState();
}

class _OrganizationInvitesScreenState extends State<OrganizationInvitesScreen> {
  final _repo = OrganizationRepository.instance;
  List<OrgInvite> _invites = const [];
  bool _loading = true;
  String? _error;
  String? _revoking;

  bool get _isAdmin => orgIsAdmin(widget.organization.role);

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
      final invites = await _repo.invites(widget.organization.id);
      invites.sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
      if (!mounted) return;
      setState(() {
        _invites = invites;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorText(e);
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    await showOrgSheet<void>(context, InviteSheet(organization: widget.organization));
    if (mounted) _load();
  }

  Future<void> _revoke(OrgInvite invite) async {
    final ok = await orgConfirm(
      context,
      title: 'Revoke invite',
      body: invite.email == null
          ? 'This invite link will stop working immediately.'
          : 'The invitation for ${invite.email} will stop working immediately.',
      action: 'Revoke',
    );
    if (!ok || !mounted) return;
    setState(() => _revoking = invite.inviteId);
    try {
      await _repo.revokeInvite(widget.organization.id, invite.inviteId);
      if (!mounted) return;
      orgToast(context, 'Invite revoked');
      await _load();
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _revoking = null);
    }
  }

  String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Widget _status(OrgInvite invite) {
    final color = invite.isActive ? orgTeal : const Color(0xFF9AA0B8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(
        invite.statusLabel,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _tile(OrgInvite invite) {
    final details = <String>[
      orgRoleLabel(invite.role),
      if (invite.teamName != null) '${invite.teamName} (${orgTeamRoleLabel(invite.teamRole ?? 'MEMBER')})',
      '${invite.usedCount}/${invite.maxUses} used',
      if (invite.expiresAt != null) 'expires ${_date(invite.expiresAt!)}',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: orgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: orgBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invite.email ?? 'Shareable link',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              _status(invite),
            ],
          ),
          const SizedBox(height: 6),
          Text(details.join(' • '), style: const TextStyle(color: orgMuted, fontSize: 12.5)),
          if (invite.inviterName != null) ...[
            const SizedBox(height: 2),
            Text('Invited by ${invite.inviterName}', style: const TextStyle(color: orgMuted, fontSize: 12)),
          ],
          if (invite.isActive) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: invite.url));
                    if (mounted) orgToast(context, 'Link copied');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16, color: orgTeal),
                  label: const Text('Copy', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  onPressed: () => Share.share('Join "${widget.organization.name}" on Quorum: ${invite.url}'),
                  icon: const Icon(Icons.share_rounded, size: 16, color: orgTeal),
                  label: const Text('Share', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                if (_isAdmin)
                  _revoking == invite.inviteId
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEF4444)),
                        )
                      : TextButton(
                          onPressed: () => _revoke(invite),
                          child: const Text(
                            'Revoke',
                            style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700),
                          ),
                        ),
              ],
            ),
          ],
        ],
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
              child: const Text('Try again', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }
    if (_invites.isEmpty) {
      return const Center(child: Text('No invites yet.', style: TextStyle(color: orgMuted)));
    }
    return RefreshIndicator(
      color: orgTeal,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        children: [for (final i in _invites) _tile(i)],
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
        title: const Text('Invites', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: orgAccent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('New invite', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _body(),
    );
  }
}
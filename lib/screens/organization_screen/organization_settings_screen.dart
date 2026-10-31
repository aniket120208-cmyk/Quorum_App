import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/widgets/copyable_id_tile.dart';
import 'organization_widgets.dart';

class OrganizationSettingsScreen extends StatefulWidget {
  const OrganizationSettingsScreen({super.key, required this.organization});
  final Organization organization;

  @override
  State<OrganizationSettingsScreen> createState() => _OrganizationSettingsScreenState();
}

class _OrganizationSettingsScreenState extends State<OrganizationSettingsScreen> {
  static const Color _danger = Color(0xFFEF4444);
  final _repo = OrganizationRepository.instance;
  bool _busy = false;
  Organization get _org => widget.organization;

  Future<void> _leave() async {
    if (_busy) return;
    final ok = await orgConfirm(
      context,
      title: 'Leave organization',
      body: 'You will lose access to ${_org.name}, its teams, tasks and chats.',
      action: 'Leave',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repo.leave(_org.id);
      if (!mounted) return;
      orgToast(context, 'You left ${_org.name}');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        orgToast(context, errorText(e), error: true);
      }
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteOrganizationDialog(name: _org.name),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repo.delete(_org.id);
      if (!mounted) return;
      orgToast(context, '${_org.name} was deleted');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        orgToast(context, errorText(e), error: true);
      }
    }
  }

  Widget _section({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: orgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: orgBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _dangerButton({required String label, required VoidCallback onPressed, required bool filled}) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: filled
          ? FilledButton(
              onPressed: _busy ? null : onPressed,
              style: FilledButton.styleFrom(backgroundColor: _danger, shape: shape),
              child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            )
          : OutlinedButton(
              onPressed: _busy ? null : onPressed,
              style: OutlinedButton.styleFrom(side: const BorderSide(color: _danger), shape: shape),
              child: Text(label, style: const TextStyle(color: _danger, fontWeight: FontWeight.w700)),
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
        title: const Text('Organization settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: orgCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: orgBorder),
            ),
            child: Row(
              children: [
                OrgAvatar(name: _org.name, logo: _org.logo, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _org.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      OrgRoleBadge(role: _org.role),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _section(
            title: 'Organization ID',
            children: [
              CopyableIdTile(
                label: 'Organization ID',
                value: _org.id,
                labelColor: orgMuted,
                valueColor: Colors.white,
                borderColor: orgBorder,
                accentColor: orgTeal,
              ),
              const SizedBox(height: 8),
              const Text(
                'Paste this ID into the AI assistant to scope questions to this organization.',
                style: TextStyle(color: orgMuted, fontSize: 12, height: 1.4),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _section(
            title: 'Leave organization',
            children: [
              const Text(
                'You will lose access to its teams, tasks and chats. You can rejoin only with a new invite.',
                style: TextStyle(color: orgMuted, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              _dangerButton(label: 'Leave organization', onPressed: _leave, filled: false),
            ],
          ),
          if (orgIsAdmin(_org.role)) ...[
            const SizedBox(height: 14),
            _section(
              title: 'Delete organization',
              children: [
                const Text(
                  'Permanently deletes the organization with all of its teams and data for every member. This cannot be undone.',
                  style: TextStyle(color: orgMuted, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 14),
                _dangerButton(label: 'Delete organization', onPressed: _delete, filled: true),
              ],
            ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Center(child: CircularProgressIndicator(color: orgTeal)),
            ),
        ],
      ),
    );
  }
}

class _DeleteOrganizationDialog extends StatefulWidget {
  const _DeleteOrganizationDialog({required this.name});
  final String name;

  @override
  State<_DeleteOrganizationDialog> createState() => _DeleteOrganizationDialogState();
}

class _DeleteOrganizationDialogState extends State<_DeleteOrganizationDialog> {
  final _ctrl = TextEditingController();

  bool get _matches => _ctrl.text.trim() == widget.name.trim();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: orgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Delete organization', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This permanently deletes ${widget.name}. Type its name to confirm.',
            style: const TextStyle(color: orgMuted, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            onChanged: (_) => setState(() {}),
            decoration: orgInputDecoration('Organization name'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: orgMuted)),
        ),
        TextButton(
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          child: Text(
            'Delete',
            style: TextStyle(color: _matches ? const Color(0xFFEF4444) : orgMuted),
          ),
        ),
      ],
    );
  }
}
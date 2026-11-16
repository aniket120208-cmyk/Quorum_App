import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'organization_widgets.dart';

class OwnershipTransferResult {
  final String message;
  final bool leftOrganization;

  const OwnershipTransferResult(this.message, this.leftOrganization);
}

class _SuccessorPicker extends StatefulWidget {
  const _SuccessorPicker({
    required this.members,
    required this.selectedId,
    required this.onSelected,
    this.teamView = false,
  });
  final List<OrgMember> members;
  final bool teamView;
  final String? selectedId;
  final ValueChanged<OrgMember> onSelected;

  @override
  State<_SuccessorPicker> createState() => _SuccessorPickerState();
}

class _SuccessorPickerState extends State<_SuccessorPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.members
        : widget.members
            .where((m) => m.name.toLowerCase().contains(q) || (m.email ?? '').toLowerCase().contains(q))
            .toList();
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          cursorColor: orgTeal,
          decoration: InputDecoration(
            hintText: 'Search member name or email',
            hintStyle: const TextStyle(color: Color(0xFF5A5E6B)),
            prefixIcon: const Icon(Icons.search_rounded, color: orgMuted, size: 20),
            filled: true,
            fillColor: orgField,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: border(orgBorder),
            enabledBorder: border(orgBorder),
            focusedBorder: border(orgTeal),
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: list.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No members found', style: TextStyle(color: orgMuted))),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final m = list[i];
                    final on = m.userId == widget.selectedId;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: OrgAvatar(name: m.name, logo: m.avatar, size: 40, circular: true),
                      title: Text(m.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      subtitle: m.email == null
                          ? null
                          : Text(m.email!, style: const TextStyle(color: orgMuted, fontSize: 12)),
                      trailing: on
                          ? const Icon(Icons.check_circle_rounded, color: orgTeal)
                          : OrgRoleBadge(role: widget.teamView ? m.teamDisplayRole : m.role),
                      onTap: () => widget.onSelected(m),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class TransferOwnershipSheet extends StatefulWidget {
  const TransferOwnershipSheet({super.key, required this.organization, required this.members});
  final Organization organization;
  final List<OrgMember> members;

  @override
  State<TransferOwnershipSheet> createState() => _TransferOwnershipSheetState();
}

class _TransferOwnershipSheetState extends State<TransferOwnershipSheet> {
  OrgMember? _successor;
  bool _leave = false;
  bool _busy = false;

  List<OrgMember> get _candidates =>
      widget.members.where((m) => m.userId.isNotEmpty && m.userId != CurrentUser.id && !m.isOwner).toList();

  Future<void> _submit() async {
    final s = _successor;
    if (s == null || _busy) return;
    if (_leave) {
      final ok = await orgConfirm(
        context,
        title: 'Transfer and leave',
        body: 'Ownership goes to ${s.name} and you will exit ${widget.organization.name} and all of its teams.',
        action: 'Proceed',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final message = await OrganizationRepository.instance.transferOwnership(
        widget.organization.id,
        s.userId,
        leaveOrganization: _leave,
      );
      if (!mounted) return;
      Navigator.pop(context, OwnershipTransferResult(message, _leave));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      orgToast(context, errorText(e), error: true);
    }
  }

  Widget _option({required bool value, required String title, required String body}) {
    final on = _leave == value;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _busy ? null : () => setState(() => _leave = value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: on ? orgTeal.withValues(alpha: 0.1) : orgField,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? orgTeal : orgBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: on ? orgTeal : orgMuted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(body, style: const TextStyle(color: orgMuted, fontSize: 12.5, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final org = widget.organization;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Transfer Primary Ownership',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Transfer primary ownership of ${org.name} to another member.',
              style: const TextStyle(color: orgMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            const Text('Select successor', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Flexible(
              child: _SuccessorPicker(
                members: _candidates,
                selectedId: _successor?.userId,
                onSelected: (m) => setState(() => _successor = m),
              ),
            ),
            const SizedBox(height: 12),
            const Text('After transferring', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _option(
              value: false,
              title: 'Step down to Admin',
              body: 'You stay in ${org.name} as an Organization Admin.',
            ),
            const SizedBox(height: 8),
            _option(
              value: true,
              title: 'Leave organization',
              body: 'You exit ${org.name} and all associated teams.',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: orgBorder),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _successor == null || _busy ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: orgAccent,
                      disabledBackgroundColor: orgAccent.withValues(alpha: 0.4),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white54,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Transfer & Proceed', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TransferLeadSheet extends StatefulWidget {
  const TransferLeadSheet({
    super.key,
    required this.organization,
    required this.team,
    required this.members,
    this.prompt,
  });
  final Organization organization;
  final OrgTeam team;
  final List<OrgMember> members;
  final String? prompt;

  @override
  State<TransferLeadSheet> createState() => _TransferLeadSheetState();
}

class _TransferLeadSheetState extends State<TransferLeadSheet> {
  OrgMember? _successor;
  bool _busy = false;

  List<OrgMember> get _candidates =>
      widget.members.where((m) => m.userId.isNotEmpty && m.userId != CurrentUser.id).toList();

  Future<void> _submit() async {
    final s = _successor;
    if (s == null || _busy) return;
    setState(() => _busy = true);
    try {
      final message = await OrganizationRepository.instance.transferLeadAndLeave(
        widget.organization.id,
        widget.team.id,
        s.userId,
      );
      if (!mounted) return;
      Navigator.pop(context, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      orgToast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Transfer Team Head Role & Exit',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              widget.prompt ??
                  'You are the sole team head of ${widget.team.name}. Select a successor before leaving.',
              style: const TextStyle(color: orgMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: _SuccessorPicker(
                teamView: true,
                members: _candidates,
                selectedId: _successor?.userId,
                onSelected: (m) => setState(() => _successor = m),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: orgBorder),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _successor == null || _busy ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: orgAccent,
                      disabledBackgroundColor: orgAccent.withValues(alpha: 0.4),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white54,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Transfer & Exit', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
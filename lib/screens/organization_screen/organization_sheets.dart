import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/api/upload_service.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'organization_widgets.dart';

Future<T?> showOrgSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: orgCard,
    shape: orgSheetShape,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(child: child),
    ),
  );
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class EditOrganizationSheet extends StatefulWidget {
  const EditOrganizationSheet({super.key, required this.organization});
  final Organization organization;

  @override
  State<EditOrganizationSheet> createState() => _EditOrganizationSheetState();
}

class _EditOrganizationSheetState extends State<EditOrganizationSheet> {
  late final _nameCtrl = TextEditingController(text: widget.organization.name);
  late final _descCtrl = TextEditingController(text: widget.organization.description ?? '');
  String? _logoPath;
  String? _logoName;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picked = await pickOrgLogo();
    if (picked == null || !mounted) return;
    setState(() {
      _logoPath = picked.path;
      _logoName = picked.name;
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      orgToast(context, 'Organization name is required', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      String? logoUrl;
      if (_logoPath != null) {
        final res = await UploadService.instance.upload(path: _logoPath!, fileName: _logoName ?? 'logo.jpg');
        logoUrl = res.url;
      }
      await OrganizationRepository.instance.update(
        widget.organization.id,
        name: name,
        description: _descCtrl.text.trim(),
        logo: logoUrl,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetTitle('Edit organization'),
          Center(
            child: OrgLogoPicker(
              name: _nameCtrl.text,
              currentLogo: widget.organization.logo,
              pickedPath: _logoPath,
              onTap: _pickLogo,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.words,
            decoration: orgInputDecoration('Organization name'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _descCtrl,
            style: const TextStyle(color: Colors.white),
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: orgInputDecoration('Description'),
          ),
          const SizedBox(height: 22),
          OrgPrimaryButton(label: 'Save changes', loading: _loading, onPressed: _save),
        ],
      ),
    );
  }
}

class CreateTeamSheet extends StatefulWidget {
  const CreateTeamSheet({super.key, required this.organizationId});
  final String organizationId;

  @override
  State<CreateTeamSheet> createState() => _CreateTeamSheetState();
}

class _CreateTeamSheetState extends State<CreateTeamSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      orgToast(context, 'Team name is required', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await OrganizationRepository.instance.createTeam(
        widget.organizationId,
        name: name,
        description: _descCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetTitle('New team'),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.words,
            decoration: orgInputDecoration('Team name', hint: 'e.g. Frontend Engineering'),
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
          const SizedBox(height: 22),
          OrgPrimaryButton(label: 'Create team', loading: _loading, onPressed: _create),
        ],
      ),
    );
  }
}

class MemberPickerSheet extends StatelessWidget {
  const MemberPickerSheet({super.key, required this.title, required this.members});
  final String title;
  final List<OrgMember> members;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetTitle(title),
            if (members.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No members to choose from', style: TextStyle(color: orgMuted))),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final m = members[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: OrgAvatar(name: m.name, logo: m.avatar, size: 40, circular: true),
                      title: Text(m.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      subtitle: m.email == null
                          ? null
                          : Text(m.email!, style: const TextStyle(color: orgMuted, fontSize: 12)),
                      onTap: () => Navigator.pop(context, m),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class InviteSheet extends StatefulWidget {
  const InviteSheet({super.key, required this.organization});
  final Organization organization;

  @override
  State<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<InviteSheet> {
  static const List<int> _useOptions = [1, 5, 10, 50];
  static const List<int> _dayOptions = [1, 3, 7, 14, 30];

  final _emailCtrl = TextEditingController();
  String _role = 'MEMBER';
  int _maxUses = 1;
  int _days = 7;
  bool _loading = false;
  OrgInvite? _invite;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty && !email.contains('@')) {
      orgToast(context, 'Enter a valid email address', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final invite = await OrganizationRepository.instance.createInvite(
        widget.organization.id,
        email: email,
        role: _role,
        maxUses: _maxUses,
        expiresInDays: _days,
      );
      if (!mounted) return;
      setState(() => _invite = invite);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _expiryText(DateTime d) =>
      '${d.day}/${d.month}/${d.year} at ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _chips<T>({
    required String label,
    required List<T> options,
    required T selected,
    required String Function(T) text,
    required ValueChanged<T> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: orgMuted, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((o) {
            final isSelected = o == selected;
            return GestureDetector(
              onTap: () => onSelected(o),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? orgAccent.withValues(alpha: 0.2) : orgField,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isSelected ? const Color(0xFF5663F6) : const Color(0xFF2C3246)),
                ),
                child: Text(
                  text(o),
                  style: TextStyle(
                    color: isSelected ? Colors.white : orgMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _form() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SheetTitle('Invite people'),
        TextField(
          controller: _emailCtrl,
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: orgInputDecoration('Email (optional)', hint: 'Restrict this link to one email'),
        ),
        const SizedBox(height: 16),
        _chips<String>(
          label: 'Role',
          options: const ['MEMBER', 'TEAM_HEAD'],
          selected: _role,
          text: orgRoleLabel,
          onSelected: (v) => setState(() => _role = v),
        ),
        const SizedBox(height: 16),
        _chips<int>(
          label: 'Max uses',
          options: _useOptions,
          selected: _maxUses,
          text: (v) => '$v',
          onSelected: (v) => setState(() => _maxUses = v),
        ),
        const SizedBox(height: 16),
        _chips<int>(
          label: 'Expires in',
          options: _dayOptions,
          selected: _days,
          text: (v) => v == 1 ? '1 day' : '$v days',
          onSelected: (v) => setState(() => _days = v),
        ),
        const SizedBox(height: 22),
        OrgPrimaryButton(label: 'Create invite link', loading: _loading, onPressed: _create),
      ],
    );
  }

  Widget _result(OrgInvite invite) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SheetTitle('Invite link ready'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: orgField,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2C3246)),
          ),
          child: SelectableText(
            invite.url,
            style: const TextStyle(color: orgTeal, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        if (invite.expiresAt != null) ...[
          const SizedBox(height: 10),
          Text(
            'Expires ${_expiryText(invite.expiresAt!)}',
            style: const TextStyle(color: orgMuted, fontSize: 12),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: invite.url));
                  if (mounted) orgToast(context, 'Link copied');
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF2C3246)),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Share.share(
                  'Join "${widget.organization.name}" on Quorum: ${invite.url}',
                ),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Share'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: orgAccent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: _invite == null ? _form() : _result(_invite!),
    );
  }
}
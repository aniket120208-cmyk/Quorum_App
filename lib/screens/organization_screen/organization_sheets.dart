import 'package:flutter/material.dart';
import 'package:quorum_app/widgets/char_limit.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/api/profile_picture_repository.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'organization_widgets.dart';
import 'package:quorum_app/form_validators.dart';

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
  String? _nameError;
  String? _descError;
  bool _loading = false;
  bool _removeLogo = false;

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
    final problem = await ProfilePictureRepository.validateFile(picked.path, picked.name);
    if (!mounted) return;
    if (problem != null) {
      orgToast(context, problem, error: true);
      return;
    }
    setState(() {
      _logoPath = picked.path;
      _logoName = picked.name;
      _removeLogo = false;
    });
  }

  Future<void> _save() async {
    if (_loading) return;
    final name = _nameCtrl.text.trim();
    final description = _descCtrl.text.trim();
    final nameError = name.isEmpty ? 'Organization name is required' : FormValidators.organizationName(name);
    final descError = FormValidators.organizationDescription(description);
    if (nameError != null || descError != null) {
      setState(() {
        _nameError = nameError;
        _descError = descError;
      });
      return;
    }
    setState(() {
      _nameError = null;
      _descError = null;
      _loading = true;
    });
    try {
      await OrganizationRepository.instance.update(
        widget.organization.id,
        name: name,
        description: description,
      );
      final pictures = ProfilePictureRepository.instance;
      if (_logoPath != null) {
        await pictures.uploadFile(
          ProfilePictureTarget.organization,
          widget.organization.id,
          path: _logoPath!,
          fileName: _logoName ?? 'logo.jpg',
        );
      } else if (_removeLogo) {
        await pictures.remove(ProfilePictureTarget.organization, widget.organization.id);
      }
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
              currentLogo: _removeLogo ? null : widget.organization.logo,
              pickedPath: _logoPath,
              onTap: _pickLogo,
            ),
          ),
          if (_logoPath != null || (!_removeLogo && (widget.organization.logo ?? '').isNotEmpty))
            Center(
              child: TextButton(
                onPressed: () => setState(() {
                  if (_logoPath != null) {
                    _logoPath = null;
                    _logoName = null;
                  } else {
                    _removeLogo = true;
                  }
                }),
                child: Text(
                  _logoPath != null ? 'Discard new logo' : 'Remove logo',
                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.words,
            maxLength: 100,
            buildCounter: charLimitCounter,
            decoration: orgInputDecoration('Organization name').copyWith(errorText: _nameError),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _descCtrl,
            style: const TextStyle(color: Colors.white),
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 250,
            buildCounter: charLimitCounter,
            decoration: orgInputDecoration('Description').copyWith(errorText: _descError),
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
            maxLength: kNameMaxLength,
            buildCounter: charLimitCounter,
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

class EditTeamSheet extends StatefulWidget {
  const EditTeamSheet({super.key, required this.organizationId, required this.team});
  final String organizationId;
  final OrgTeam team;

  @override
  State<EditTeamSheet> createState() => _EditTeamSheetState();
}

class _EditTeamSheetState extends State<EditTeamSheet> {
  late final _nameCtrl = TextEditingController(text: widget.team.name);
  late final _descCtrl = TextEditingController(text: widget.team.description ?? '');
  String? _logoPath;
  String? _logoName;
  bool _removeLogo = false;
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
    final problem = await ProfilePictureRepository.validateFile(picked.path, picked.name);
    if (!mounted) return;
    if (problem != null) {
      orgToast(context, problem, error: true);
      return;
    }
    setState(() {
      _logoPath = picked.path;
      _logoName = picked.name;
      _removeLogo = false;
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      orgToast(context, 'Team name is required', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await OrganizationRepository.instance.updateTeam(
        widget.organizationId,
        widget.team.id,
        name: name,
        description: _descCtrl.text.trim(),
      );
      final pictures = ProfilePictureRepository.instance;
      if (_logoPath != null) {
        await pictures.uploadFile(
          ProfilePictureTarget.team,
          widget.team.id,
          parentId: widget.organizationId,
          path: _logoPath!,
          fileName: _logoName ?? 'team.jpg',
        );
      } else if (_removeLogo) {
        await pictures.remove(ProfilePictureTarget.team, widget.team.id, parentId: widget.organizationId);
      }
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
    final hasCurrent = !_removeLogo && (widget.team.avatar ?? '').isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetTitle('Edit team'),
          Center(
            child: OrgLogoPicker(
              name: _nameCtrl.text,
              currentLogo: _removeLogo ? null : widget.team.avatar,
              pickedPath: _logoPath,
              onTap: _pickLogo,
            ),
          ),
          if (_logoPath != null || hasCurrent)
            Center(
              child: TextButton(
                onPressed: () => setState(() {
                  if (_logoPath != null) {
                    _logoPath = null;
                    _logoName = null;
                  } else {
                    _removeLogo = true;
                  }
                }),
                child: Text(
                  _logoPath != null ? 'Discard new photo' : 'Remove photo',
                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.words,
            maxLength: kNameMaxLength,
            buildCounter: charLimitCounter,
            decoration: orgInputDecoration('Team name'),
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
          OrgPrimaryButton(label: 'Save', loading: _loading, onPressed: _save),
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
                      leading: OrgAvatar(name: m.name, logo: m.avatar, size: 40, circular: true, presenceUserId: m.userId),
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

class TeamMemberSelection {
  final OrgMember member;
  final String? teamRole;

  const TeamMemberSelection(this.member, this.teamRole);
}

class AddTeamMemberSheet extends StatefulWidget {
  const AddTeamMemberSheet({
    super.key,
    required this.title,
    required this.members,
    this.joinedIds = const {},
  });
  final String title;
  final List<OrgMember> members;
  final Set<String> joinedIds;

  @override
  State<AddTeamMemberSheet> createState() => _AddTeamMemberSheetState();
}

class _AddTeamMemberSheetState extends State<AddTeamMemberSheet> {
  final _search = TextEditingController();
  String _query = '';
  OrgMember? _selected;
  String _teamRole = 'MEMBER';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<OrgMember> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.members;
    return widget.members
        .where((m) => m.name.toLowerCase().contains(q) || (m.email ?? '').toLowerCase().contains(q))
        .toList();
  }

  bool _isJoined(OrgMember m) => widget.joinedIds.contains(m.userId);

  Widget _searchField() {
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: _search,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        cursorColor: orgTeal,
        decoration: InputDecoration(
          hintText: 'Search members',
          hintStyle: const TextStyle(color: Color(0xFF5A5E6B)),
          prefixIcon: const Icon(Icons.search_rounded, color: orgMuted, size: 20),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                  icon: const Icon(Icons.close_rounded, color: orgMuted, size: 18),
                ),
          filled: true,
          fillColor: orgField,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: border(orgBorder),
          enabledBorder: border(orgBorder),
          focusedBorder: border(orgTeal),
        ),
      ),
    );
  }

  Widget _joinedTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: orgTeal.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'Joined',
        style: TextStyle(color: orgTeal, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  bool get _needsRole => _selected != null && !orgIsAdmin(_selected!.role);

  void _submit() {
    final m = _selected;
    if (m == null) return;
    Navigator.pop(context, TeamMemberSelection(m, _needsRole ? _teamRole : null));
  }

  Widget _roleChip(String role) {
    final on = _teamRole == role;
    return GestureDetector(
      onTap: () => setState(() => _teamRole = role),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: on ? orgAccent.withValues(alpha: 0.2) : orgField,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? const Color(0xFF5663F6) : const Color(0xFF2C3246)),
        ),
        child: Text(
          orgTeamRoleLabel(role),
          style: TextStyle(color: on ? Colors.white : orgMuted, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetTitle(widget.title),
            if (widget.members.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No members to choose from', style: TextStyle(color: orgMuted))),
              )
            else ...[
              _searchField(),
              if (_visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No members match your search', style: TextStyle(color: orgMuted))),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: _visible.length,
                    itemBuilder: (context, index) {
                      final m = _visible[index];
                      final joined = _isJoined(m);
                      final on = !joined && _selected?.userId == m.userId;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        enabled: !joined,
                        leading: OrgAvatar(name: m.name, logo: m.avatar, size: 40, circular: true, presenceUserId: m.userId),
                        title: Text(
                          m.name,
                          style: TextStyle(
                            color: joined ? orgMuted : Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: m.email == null
                            ? null
                            : Text(m.email!, style: const TextStyle(color: orgMuted, fontSize: 12)),
                        trailing: joined
                            ? _joinedTag()
                            : on
                                ? const Icon(Icons.check_circle_rounded, color: orgTeal)
                                : OrgRoleBadge(role: m.role),
                        onTap: joined ? null : () => setState(() => _selected = m),
                      );
                    },
                  ),
                ),
            ],
            if (_needsRole) ...[
              const SizedBox(height: 12),
              const Text('Team role', style: TextStyle(color: orgMuted, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final r in orgTeamRoles) _roleChip(r)]),
            ] else if (_selected != null) ...[
              const SizedBox(height: 12),
              Text(
                '${_selected!.name} joins as ${orgRoleLabel(_selected!.role)}.',
                style: const TextStyle(color: orgMuted, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 16),
            OrgPrimaryButton(label: 'Add to team', onPressed: _selected == null ? null : _submit),
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
  String? _teamId;
  String _teamRole = 'MEMBER';
  int _maxUses = 1;
  int _days = 7;
  bool _loading = false;
  List<OrgTeam> _teams = const [];
  OrgInvite? _invite;
  String? _sentTo;

  bool get _isAdmin => orgIsAdmin(widget.organization.role);

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTeams() async {
    try {
      final teams = await OrganizationRepository.instance.teams(widget.organization.id);
      if (!mounted) return;
      setState(() {
        _teams = teams;
        if (!_isAdmin && teams.length == 1) _teamId = teams.first.id;
      });
    } catch (_) {}
  }

  Future<void> _create() async {
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty && !email.contains('@')) {
      orgToast(context, 'Enter a valid email address', error: true);
      return;
    }
    if (!_isAdmin && _teams.isNotEmpty && _teamId == null) {
      orgToast(context, 'Choose the team to invite into', error: true);
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
        teamId: _teamId,
        teamRole: _teamId == null || _role != 'MEMBER' ? null : _teamRole,
      );
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _sentTo = email.isEmpty ? null : email;
      });
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
          maxLength: kEmailMaxLength,
          buildCounter: charLimitCounter,
          decoration: orgInputDecoration('Email (optional)', hint: 'Restrict this link to one email'),
        ),
        const SizedBox(height: 16),
        _chips<String>(
          label: 'Role',
          options: orgInvitableRoles(widget.organization.role),
          selected: _role,
          text: orgRoleLabel,
          onSelected: (v) => setState(() => _role = v),
        ),
        if (_teams.isNotEmpty) ...[
          const SizedBox(height: 16),
          _chips<String?>(
            label: _isAdmin ? 'Add to team (optional)' : 'Team',
            options: [if (_isAdmin) null, ..._teams.map((t) => t.id)],
            selected: _teamId,
            text: (v) => v == null ? 'No team' : _teams.firstWhere((t) => t.id == v).name,
            onSelected: (v) => setState(() => _teamId = v),
          ),
          if (_teamId != null && _role == 'MEMBER') ...[
            const SizedBox(height: 16),
            _chips<String>(
              label: 'Team role',
              options: orgTeamRoles,
              selected: _teamRole,
              text: orgTeamRoleLabel,
              onSelected: (v) => setState(() => _teamRole = v),
            ),
          ],
        ],
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
        if (_sentTo != null) ...[
          const SizedBox(height: 10),
          Text(
            'An email invitation was sent to $_sentTo.',
            style: const TextStyle(color: orgMuted, fontSize: 12),
          ),
        ],
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
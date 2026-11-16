import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/api/profile_picture_repository.dart';
import 'package:quorum_app/api/upload_service.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'organization_sheets.dart';
import 'organization_widgets.dart';
import 'package:quorum_app/form_validators.dart';

class CreateOrganizationScreen extends StatefulWidget {
  const CreateOrganizationScreen({super.key});

  @override
  State<CreateOrganizationScreen> createState() => _CreateOrganizationScreenState();
}

class _CreateOrganizationScreenState extends State<CreateOrganizationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final List<String> _emails = [];
  String _inviteRole = 'MEMBER';
  bool _shareLink = false;
  String? _emailError;
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
    _emailCtrl.dispose();
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
    });
  }

  void _addEmail() {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty) return;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _emailError = 'Enter a valid email address');
      return;
    }
    if (_emails.contains(email)) {
      setState(() => _emailError = 'Already added');
      return;
    }
    setState(() {
      _emails.add(email);
      _emailCtrl.clear();
      _emailError = null;
    });
  }

  Future<int> _sendInvites(Organization org) async {
    var sent = 0;
    for (final email in _emails) {
      try {
        await OrganizationRepository.instance.createInvite(
          org.id,
          email: email,
          role: _inviteRole,
          maxUses: 1,
          expiresInDays: 7,
        );
        sent++;
      } catch (_) {}
    }
    return sent;
  }

  Widget _roleChip(String role) {
    final on = _inviteRole == role;
    return GestureDetector(
      onTap: () => setState(() => _inviteRole = role),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: on ? orgAccent.withValues(alpha: 0.2) : orgField,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? const Color(0xFF5663F6) : const Color(0xFF2C3246)),
        ),
        child: Text(
          orgRoleLabel(role),
          style: TextStyle(color: on ? Colors.white : orgMuted, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _inviteSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Invite people (optional)', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
          'Invite by email or share a link once your organization is created.',
          style: TextStyle(color: orgMuted, fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailCtrl,
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _addEmail(),
          onChanged: (_) {
            if (_emailError != null) setState(() => _emailError = null);
          },
          decoration: orgInputDecoration('Email address', hint: 'name@company.com').copyWith(
            errorText: _emailError,
            suffixIcon: IconButton(
              onPressed: _addEmail,
              icon: const Icon(Icons.add_circle_rounded, color: orgTeal),
            ),
          ),
        ),
        if (_emails.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final email in _emails)
                InputChip(
                  label: Text(email, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                  backgroundColor: orgField,
                  side: const BorderSide(color: Color(0xFF2C3246)),
                  deleteIconColor: orgMuted,
                  onDeleted: () => setState(() => _emails.remove(email)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Invite as', style: TextStyle(color: orgMuted, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final r in orgInvitableRoles('OWNER')) _roleChip(r)]),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _shareLink,
          activeTrackColor: orgTeal,
          onChanged: (v) => setState(() => _shareLink = v),
          title: const Text('Share an invite link', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: const Text('Create a link to copy or share right after creating', style: TextStyle(color: orgMuted, fontSize: 12)),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_loading || !(_formKey.currentState?.validate() ?? false)) return;
    if (_emailCtrl.text.trim().isNotEmpty) {
      _addEmail();
      if (_emailError != null) return;
    }
    setState(() => _loading = true);
    try {
      String? logoUrl;
      if (_logoPath != null) {
        final res = await UploadService.instance.upload(path: _logoPath!, fileName: _logoName ?? 'logo.jpg');
        logoUrl = res.url;
      }
      final org = await OrganizationRepository.instance.create(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        logo: logoUrl,
      );
      if (!mounted) return;
      final total = _emails.length;
      final sent = total == 0 ? 0 : await _sendInvites(org);
      if (!mounted) return;
      if (total == 0) {
        orgToast(context, 'Organization created');
      } else if (sent == total) {
        orgToast(context, 'Organization created, $sent ${sent == 1 ? 'invite' : 'invites'} sent');
      } else {
        orgToast(context, 'Organization created, $sent of $total invites sent', error: sent == 0);
      }
      if (_shareLink) {
        await showOrgSheet<void>(context, InviteSheet(organization: org));
        if (!mounted) return;
      }
      Navigator.pop<Organization>(context, org);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Create Organization', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: OrgLogoPicker(
                    name: _nameCtrl.text,
                    pickedPath: _logoPath,
                    onTap: _pickLogo,
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text('Add a logo (optional)', style: TextStyle(color: orgMuted, fontSize: 12)),
                ),
                if (_logoPath != null)
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() {
                        _logoPath = null;
                        _logoName = null;
                      }),
                      child: const Text(
                        'Remove logo',
                        style: TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.words,
                  decoration: orgInputDecoration('Organization name', hint: 'e.g. Acme Corporation'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Organization name is required' : FormValidators.organizationName(v),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descCtrl,
                  style: const TextStyle(color: Colors.white),
                  minLines: 3,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: orgInputDecoration('Description (optional)', hint: 'What does your organization do?'),
                  validator: FormValidators.organizationDescription,
                ),
                const SizedBox(height: 24),
                _inviteSection(),
                const SizedBox(height: 24),
                OrgPrimaryButton(label: 'Create organization', loading: _loading, onPressed: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
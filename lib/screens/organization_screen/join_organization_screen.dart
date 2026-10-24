import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'organization_widgets.dart';

class JoinOrganizationScreen extends StatefulWidget {
  const JoinOrganizationScreen({super.key, this.initialToken});
  final String? initialToken;

  @override
  State<JoinOrganizationScreen> createState() => _JoinOrganizationScreenState();
}

class _JoinOrganizationScreenState extends State<JoinOrganizationScreen> {
  final _ctrl = TextEditingController();
  InvitePreview? _preview;
  String _token = '';
  bool _checking = false;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
    final initial = widget.initialToken;
    if (initial != null && initial.isNotEmpty) {
      _ctrl.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _tokenFrom(String input) {
    final text = input.trim();
    final uri = Uri.tryParse(text);
    if (uri != null) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) return segments.last;
    }
    return text;
  }

  Future<void> _lookup() async {
    final token = _tokenFrom(_ctrl.text);
    if (token.isEmpty || _checking) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _checking = true;
      _preview = null;
    });
    try {
      final preview = await OrganizationRepository.instance.previewInvite(token);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _token = token;
      });
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _join() async {
    if (_joining) return;
    setState(() => _joining = true);
    try {
      await OrganizationRepository.instance.acceptInvite(_token);
      if (!mounted) return;
      orgToast(context, 'Successfully joined ${_preview?.organizationName ?? 'organization'}');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Join Organization', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste the invite link or code you received.',
                style: TextStyle(color: orgMuted, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ctrl,
                style: const TextStyle(color: Colors.white),
                autocorrect: false,
                textInputAction: TextInputAction.search,
                onChanged: (_) {
                  if (_preview != null) setState(() => _preview = null);
                },
                onSubmitted: (_) => _lookup(),
                decoration: orgInputDecoration('Invite link or code', hint: 'https://newquorum.me/join/...'),
              ),
              const SizedBox(height: 16),
              OrgPrimaryButton(
                label: 'Find organization',
                loading: _checking,
                onPressed: _ctrl.text.trim().isEmpty ? null : _lookup,
              ),
              if (preview != null) ...[
                const SizedBox(height: 28),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: orgCard,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: orgBorder),
                  ),
                  child: Column(
                    children: [
                      OrgAvatar(name: preview.organizationName, logo: preview.organizationLogo, size: 68),
                      const SizedBox(height: 14),
                      Text(
                        preview.organizationName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${preview.membersCount} ${preview.membersCount == 1 ? 'member' : 'members'}',
                        style: const TextStyle(color: orgMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('You will join as ', style: TextStyle(color: orgMuted, fontSize: 13)),
                          OrgRoleBadge(role: preview.role),
                        ],
                      ),
                      if (preview.inviterName != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Invited by ${preview.inviterName}',
                          style: const TextStyle(color: orgMuted, fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 20),
                      OrgPrimaryButton(label: 'Join organization', loading: _joining, onPressed: _join),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
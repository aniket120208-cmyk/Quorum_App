import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/project_repository.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';

class AcceptProjectInviteScreen extends StatefulWidget {
  const AcceptProjectInviteScreen({super.key, this.initialToken});
  final String? initialToken;

  @override
  State<AcceptProjectInviteScreen> createState() => _AcceptProjectInviteScreenState();
}

class _AcceptProjectInviteScreenState extends State<AcceptProjectInviteScreen> {
  final _ctrl = TextEditingController();
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.initialToken ?? '';
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _tokenFrom(String input) {
    final text = input.trim();
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme) {
      final fromQuery = uri.queryParameters['token'];
      if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) return segments.last;
    }
    return text;
  }

  Future<void> _accept() async {
    final token = _tokenFrom(_ctrl.text);
    if (token.isEmpty || _joining) return;
    FocusScope.of(context).unfocus();
    setState(() => _joining = true);
    try {
      await ProjectRepository.instance.acceptInvite(token);
      if (!mounted) return;
      orgToast(context, 'You joined the project');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _joining = false);
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
        title: const Text('Join a project', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Paste the invitation token or link you received by email to join a project as a collaborator.',
            style: TextStyle(color: orgMuted, fontSize: 14, height: 1.45),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _ctrl,
            style: const TextStyle(color: Colors.white),
            autocorrect: false,
            decoration: orgInputDecoration('Invitation token or link'),
          ),
          const SizedBox(height: 22),
          OrgPrimaryButton(
            label: 'Accept invitation',
            loading: _joining,
            onPressed: _ctrl.text.trim().isEmpty ? null : _accept,
          ),
        ],
      ),
    );
  }
}
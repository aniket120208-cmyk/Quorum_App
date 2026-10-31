import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/jira_repository.dart';
import 'package:quorum_app/models/jira_models.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'jira_my_tickets_screen.dart';
import 'jira_widgets.dart';

class JiraSettingsScreen extends StatefulWidget {
  const JiraSettingsScreen({super.key, this.organization});
  final Organization? organization;

  @override
  State<JiraSettingsScreen> createState() => _JiraSettingsScreenState();
}

class _JiraSettingsScreenState extends State<JiraSettingsScreen> with WidgetsBindingObserver {
  final _repo = JiraRepository.instance;
  final _keyCtrl = TextEditingController();
  JiraUserStatus? _user;
  OrgJiraStatus? _org;
  bool _loading = true;
  String? _error;
  bool _connecting = false;
  bool _awaitingReturn = false;
  bool _linking = false;
  String? _keyError;

  bool get _isAdmin => widget.organization != null && orgIsAdmin(widget.organization!.role);
  bool get _userConnected => _user?.isConnected == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingReturn) {
      _awaitingReturn = false;
      _afterConnect();
    }
  }

  Future<void> _afterConnect() async {
    await _load(silent: true);
    if (!mounted) return;
    if (_userConnected) {
      orgToast(context, 'Jira connected successfully!');
    } else {
      orgToast(context, 'Jira connection was not completed', error: true);
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final user = await _repo.userStatus();
      final org = widget.organization == null ? null : await _repo.orgStatus(widget.organization!.id);
      if (!mounted) return;
      setState(() {
        _user = user;
        _org = org;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _user == null) _error = errorText(e);
      });
    }
  }

  Future<void> _connect() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      final url = await _repo.authorizeUrl();
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (opened) {
        _awaitingReturn = true;
      } else {
        orgToast(context, 'Could not open the browser', error: true);
      }
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnectUser() async {
    final ok = await orgConfirm(
      context,
      title: 'Disconnect Jira',
      body: 'Your Atlassian account will be unlinked from Quorum.',
      action: 'Disconnect',
    );
    if (!ok) return;
    try {
      await _repo.disconnectUser();
      await _load(silent: true);
      if (mounted) orgToast(context, 'Jira disconnected successfully');
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _linkProject() async {
    if (_linking) return;
    final key = _keyCtrl.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z][A-Z0-9_]+$').hasMatch(key)) {
      setState(() => _keyError = 'Enter a valid project key, for example DEV');
      return;
    }
    setState(() {
      _keyError = null;
      _linking = true;
    });
    try {
      await _repo.setupOrg(widget.organization!.id, key);
      _keyCtrl.clear();
      await _load(silent: true);
      if (mounted) orgToast(context, 'Organization Jira integration configured');
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  Future<void> _disconnectOrg() async {
    final ok = await orgConfirm(
      context,
      title: 'Remove Jira integration',
      body: 'Teams in ${widget.organization!.name} will no longer see Jira tickets.',
      action: 'Remove',
    );
    if (!ok) return;
    try {
      await _repo.disconnectOrg(widget.organization!.id);
      await _load(silent: true);
      if (mounted) orgToast(context, 'Organization Jira integration removed');
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  void _openMyTickets() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const JiraMyTicketsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Jira integration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: orgTeal))
          : _error != null
              ? JiraMessageView(
                  icon: Icons.error_outline_rounded,
                  message: _error!,
                  actionLabel: 'Retry',
                  onAction: _load,
                )
              : RefreshIndicator(
                  color: orgTeal,
                  backgroundColor: orgCard,
                  onRefresh: () => _load(silent: true),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                    children: [
                      _accountCard(),
                      if (widget.organization != null) ...[
                        const SizedBox(height: 14),
                        _organizationCard(),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _card({required IconData icon, required String title, required List<Widget> children}) {
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
          Row(
            children: [
              Icon(icon, color: orgTeal, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String? value) {
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 78, child: Text(label, style: const TextStyle(color: orgMuted, fontSize: 12.5))),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _accountCard() {
    final user = _user;
    return _card(
      icon: Icons.person_outline_rounded,
      title: 'Your Jira account',
      children: [
        if (_userConnected) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: JiraChip(label: 'Connected', color: orgTeal),
            ),
          ),
          _infoRow('Name', user?.jiraDisplayName),
          _infoRow('Email', user?.jiraEmail),
          _infoRow('Site', user?.siteUrl),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _openMyTickets,
              icon: const Icon(Icons.confirmation_number_outlined, size: 18, color: orgTeal),
              label: const Text('My assigned tickets', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: orgBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _disconnectUser,
              child: const Text('Disconnect', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
            ),
          ),
        ] else ...[
          const Text(
            'Link your Atlassian account to view and update Jira tickets from Quorum.',
            style: TextStyle(color: orgMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          OrgPrimaryButton(label: 'Connect Jira', loading: _connecting, onPressed: _connect),
        ],
      ],
    );
  }

  Widget _organizationCard() {
    final org = _org;
    final connected = org?.isConnected == true;
    return _card(
      icon: Icons.business_rounded,
      title: 'Organization project',
      children: [
        if (connected) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: JiraChip(label: org?.isActive == true ? 'Active' : 'Inactive', color: orgTeal),
            ),
          ),
          _infoRow('Project', org?.projectKey),
          _infoRow('Site', org?.siteUrl),
          if (_isAdmin)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _disconnectOrg,
                child: const Text('Remove integration', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
              ),
            ),
        ] else if (_isAdmin) ...[
          Text(
            _userConnected
                ? 'Enter the Jira project key to link ${widget.organization!.name} to Jira.'
                : 'Connect your own Jira account first, then link a project key.',
            style: const TextStyle(color: orgMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _keyCtrl,
            enabled: _userConnected,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.characters,
            decoration: orgInputDecoration('Project key', hint: 'e.g. DEV').copyWith(errorText: _keyError),
          ),
          const SizedBox(height: 14),
          OrgPrimaryButton(
            label: 'Link project',
            loading: _linking,
            onPressed: _userConnected ? _linkProject : null,
          ),
        ] else
          const Text(
            'Jira is not configured for this organization. Ask an Org Admin to set up Jira.',
            style: TextStyle(color: orgMuted, fontSize: 13, height: 1.4),
          ),
      ],
    );
  }
}
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/github_repository.dart';
import 'package:quorum_app/models/github_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'github_widgets.dart';

class GithubSettingsScreen extends StatefulWidget {
  const GithubSettingsScreen({super.key});

  @override
  State<GithubSettingsScreen> createState() => _GithubSettingsScreenState();
}

class _GithubSettingsScreenState extends State<GithubSettingsScreen> with WidgetsBindingObserver {
  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final _repo = GithubRepository.instance;
  GithubStatus? _status;
  bool _loading = true;
  String? _error;
  bool _connecting = false;
  bool _awaitingReturn = false;

  bool get _connected => _status?.connected == true;

  bool get _expired {
    final expires = _status?.expiresAt;
    return expires != null && expires.isBefore(DateTime.now());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (_connected) {
      orgToast(context, 'GitHub connected successfully!');
    } else {
      orgToast(context, 'GitHub connection was not completed', error: true);
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
      final status = await _repo.status();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _status == null) _error = errorText(e);
      });
    }
  }

  Future<void> _connect() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      final url = await _repo.authorizeUrl();
      if (url.isEmpty) throw ApiException('Could not start GitHub authorization.');
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

  Future<void> _disconnect() async {
    final ok = await orgConfirm(
      context,
      title: 'Disconnect GitHub',
      body: 'Your GitHub account will be unlinked from Quorum.',
      action: 'Disconnect',
    );
    if (!ok) return;
    try {
      await _repo.disconnect();
      await _load(silent: true);
      if (mounted) orgToast(context, 'GitHub account disconnected successfully');
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  String _format(DateTime d) {
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${_months[d.month - 1]} ${d.year}, $hour:$minute';
  }

  Widget _infoRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(color: orgMuted, fontSize: 12.5))),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _accountCard() {
    final status = _status;
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
          const Row(
            children: [
              Icon(Icons.code_rounded, color: orgTeal, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your GitHub account',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_connected) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GithubChip(
                label: _expired ? 'Session expired' : 'Connected',
                color: _expired ? const Color(0xFFFBBF24) : orgTeal,
              ),
            ),
            _infoRow('Username', status?.username == null ? null : '@${status!.username}'),
            _infoRow('Email', status?.email),
            _infoRow('Connected', status?.connectedAt == null ? null : _format(status!.connectedAt!)),
            _infoRow('Expires', status?.expiresAt == null ? null : _format(status!.expiresAt!)),
            if (_expired) ...[
              const SizedBox(height: 4),
              const Text(
                'Your GitHub session has expired. Reconnect to keep using issues, pull requests and commits.',
                style: TextStyle(color: orgMuted, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              OrgPrimaryButton(label: 'Reconnect GitHub', loading: _connecting, onPressed: _connect),
            ],
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _disconnect,
                child: const Text('Disconnect', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
              ),
            ),
          ] else ...[
            const Text(
              'Link your GitHub account to view issues, pull requests and commits for your teams, and to create issues from Quorum.',
              style: TextStyle(color: orgMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            OrgPrimaryButton(label: 'Connect GitHub', loading: _connecting, onPressed: _connect),
          ],
        ],
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
        title: const Text('GitHub integration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: orgTeal))
          : _error != null
              ? GithubMessageView(
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
                    children: [_accountCard()],
                  ),
                ),
    );
  }
}
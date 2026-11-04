import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/community_repository.dart';
import 'package:quorum_app/models/community_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'community_widgets.dart';

class CommunityJoinRequestsScreen extends StatefulWidget {
  const CommunityJoinRequestsScreen({
    super.key,
    required this.communityId,
    required this.communityName,
  });
  final String communityId;
  final String communityName;

  @override
  State<CommunityJoinRequestsScreen> createState() => _CommunityJoinRequestsScreenState();
}

class _CommunityJoinRequestsScreenState extends State<CommunityJoinRequestsScreen> {
  static const Color darkBg = Color(0xFF0A0B14);
  static const Color cardBg = Color(0xFF16172B);
  static const Color cardBorder = Color(0xFF2A2C4A);
  static const Color violet = Color(0xFF7C5CFC);
  static const Color green = Color(0xFF22C55E);
  static const Color muted = Color(0xFF9A9CB8);

  final _repo = CommunityRepository.instance;

  List<CommunityJoinRequest> _items = [];
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _repo.joinRequests(widget.communityId);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = errorText(e);
      });
    }
  }

  void _drop(CommunityJoinRequest r) {
    _items = _items.where((x) => x.id != r.id).toList();
    _busy.remove(r.id);
  }

  Future<void> _accept(CommunityJoinRequest r) async {
    setState(() => _busy.add(r.id));
    try {
      await _repo.acceptJoinRequest(widget.communityId, r.id);
      if (!mounted) return;
      setState(() => _drop(r));
      showCommunityToast(context, '${r.user?.name ?? 'Applicant'} was added to ${widget.communityName}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(r.id));
      showErrorSnack(context, errorText(e));
      _load(silent: true);
    }
  }

  Future<void> _reject(CommunityJoinRequest r) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => TextPromptDialog(
        title: 'Decline request',
        hint: 'Reason for declining (optional)',
        actionLabel: 'Decline',
        maxLines: 4,
        maxLength: 500,
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy.add(r.id));
    try {
      await _repo.rejectJoinRequest(widget.communityId, r.id, reason: reason);
      if (!mounted) return;
      setState(() => _drop(r));
      showCommunityToast(context, 'Request declined');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(r.id));
      showErrorSnack(context, errorText(e));
      _load(silent: true);
    }
  }

  Widget _card(CommunityJoinRequest r) {
    final user = r.user;
    final name = user?.name ?? 'Unknown user';
    final busy = _busy.contains(r.id);
    final created = r.createdAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ChatAvatar(name: name, imageUrl: user?.avatar, radius: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      if (user != null && user.email.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                if (created != null) Text(timeAgo(created), style: const TextStyle(color: muted, fontSize: 11)),
              ],
            ),
            if (r.message != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F101A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  r.message!,
                  style: const TextStyle(color: Color(0xFFD0D2E6), fontSize: 13, height: 1.35),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (busy)
              const Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: violet),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _reject(r),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _accept(r),
                      style: FilledButton.styleFrom(
                        backgroundColor: green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: violet));
    if (_error != null) {
      return CenteredMessage(
        icon: Icons.cloud_off,
        text: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(
            height: 320,
            child: CenteredMessage(
              icon: Icons.how_to_reg_outlined,
              text: 'No pending join requests.',
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: _items.length,
      itemBuilder: (_, i) => _card(_items[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        backgroundColor: darkBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Join requests · ${widget.communityName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: RefreshIndicator(
        color: violet,
        backgroundColor: cardBg,
        onRefresh: () => _load(silent: true),
        child: _body(),
      ),
    );
  }
}
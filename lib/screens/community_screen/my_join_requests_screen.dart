import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/community_repository.dart';
import 'package:quorum_app/models/community_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'community_widgets.dart';

class MyJoinRequestsScreen extends StatefulWidget {
  const MyJoinRequestsScreen({super.key});

  @override
  State<MyJoinRequestsScreen> createState() => _MyJoinRequestsScreenState();
}

class _MyJoinRequestsScreenState extends State<MyJoinRequestsScreen> {
  static const Color darkBg = Color(0xFF0A0B14);
  static const Color cardBg = Color(0xFF16172B);
  static const Color cardBorder = Color(0xFF2A2C4A);
  static const Color violet = Color(0xFF7C5CFC);
  static const Color amber = Color(0xFFF59E0B);
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
      final list = await _repo.myJoinRequests();
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

  Future<void> _cancel(CommunityJoinRequest r) async {
    final name = r.community?.name ?? 'this community';
    final ok = await confirmAction(
      context,
      title: 'Cancel request?',
      body: 'Withdraw your request to join $name?',
      action: 'Cancel request',
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(r.id));
    try {
      await _repo.cancelJoinRequest(r.communityId);
      if (!mounted) return;
      setState(() {
        _items = _items.where((x) => x.id != r.id).toList();
        _busy.remove(r.id);
      });
      showCommunityToast(context, 'Join request cancelled');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(r.id));
      showErrorSnack(context, errorText(e));
    }
  }

  Widget _card(CommunityJoinRequest r) {
    final community = r.community;
    final name = community?.name ?? 'Community';
    final description = community?.description;
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
                CommunityAvatar(name: name, size: 46),
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
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (r.message != null) ...[
              const SizedBox(height: 10),
              Text(
                '"${r.message}"',
                style: const TextStyle(color: muted, fontSize: 12, fontStyle: FontStyle.italic, height: 1.3),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: amber.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Awaiting approval',
                    style: TextStyle(color: amber, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
                if (created != null) ...[
                  const SizedBox(width: 10),
                  Text(timeAgo(created), style: const TextStyle(color: muted, fontSize: 11)),
                ],
                const Spacer(),
                if (busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: violet),
                  )
                else
                  TextButton(
                    onPressed: () => _cancel(r),
                    child: const Text('Cancel', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
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
              icon: Icons.hourglass_empty_rounded,
              text: 'You have no pending join requests.',
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
        title: const Text(
          'My join requests',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
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
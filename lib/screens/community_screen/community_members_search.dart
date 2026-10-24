import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/community_repository.dart';
import 'package:quorum_app/models/community_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'community_invite_screen.dart';
import 'community_widgets.dart';

class CommunityMembersScreen extends StatefulWidget {
  const CommunityMembersScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    required this.myId,
    required this.myRole,
  });

  final String communityId;
  final String communityName;
  final String myId;
  final String myRole;

  @override
  State<CommunityMembersScreen> createState() => _CommunityMembersScreenState();
}

class _CommunityMembersScreenState extends State<CommunityMembersScreen> {
  static const Color darkBg = Color(0xFF0F101A);

  final _repo = CommunityRepository.instance;
  final _scroll = ScrollController();

  List<CommunityMember> _members = [];
  String? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  final Set<String> _removing = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) _loadMore();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await _repo.members(widget.communityId);
      if (!mounted) return;
      setState(() {
        _members = page.items;
        _cursor = page.cursor;
        _hasMore = page.hasMore && page.cursor != null;
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

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.members(widget.communityId, cursor: _cursor);
      if (!mounted) return;
      final known = _members.map((m) => m.id).toSet();
      setState(() {
        _members = [..._members, ...page.items.where((m) => !known.contains(m.id))];
        _cursor = page.cursor;
        _hasMore = page.hasMore && page.cursor != null;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _remove(CommunityMember m) async {
    final ok = await confirmAction(
      context,
      title: 'Remove member?',
      body: 'Remove ${m.user.name} from ${widget.communityName}?',
      action: 'Remove',
    );
    if (!ok || !mounted) return;
    setState(() => _removing.add(m.user.id));
    try {
      await _repo.removeMember(widget.communityId, m.user.id);
      if (!mounted) return;
      setState(() {
        _members = _members.where((x) => x.id != m.id).toList();
        _removing.remove(m.user.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _removing.remove(m.user.id));
      showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _invite() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityInviteScreen(
          communityId: widget.communityId,
          communityName: widget.communityName,
        ),
      ),
    );
  }

  Widget _tile(CommunityMember m) {
    final isMe = m.user.id == widget.myId;
    final removable = !isMe && canRemoveMember(widget.myRole, m.role);
    final removing = _removing.contains(m.user.id);
    final email = m.user.email;
    final joined = m.joinedAt;

    final subtitle = [
      if (email != null && email.isNotEmpty) email,
      if (joined != null) 'Joined ${timeAgo(joined)}',
    ].join(' · ');

    return ListTile(
      leading: ChatAvatar(name: m.user.name, imageUrl: m.user.avatarUrl, radius: 22),
      title: Row(
        children: [
          Flexible(
            child: Text(
              isMe ? '${m.user.name} (You)' : m.user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          RoleBadge(role: m.role),
        ],
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
      trailing: removable
          ? (removing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.person_remove_outlined, color: Colors.redAccent),
                  onPressed: () => _remove(m),
                ))
          : null,
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return CenteredMessage(
        icon: Icons.cloud_off,
        text: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: () => _load(silent: true),
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _members.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _members.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                ),
              ),
            );
          }
          return _tile(_members[i]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        backgroundColor: darkBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text(
          'Members',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (canModerate(widget.myRole))
            IconButton(
              tooltip: 'Invite',
              icon: const Icon(Icons.person_add_alt_1, color: AppColors.textPrimary),
              onPressed: _invite,
            ),
        ],
      ),
      body: _body(),
    );
  }
}
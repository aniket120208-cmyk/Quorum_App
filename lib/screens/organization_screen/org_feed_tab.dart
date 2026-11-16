import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/org_feed_repository.dart';
import 'package:quorum_app/api/saved_items_store.dart';
import 'package:quorum_app/api/socket_service.dart';
import 'package:quorum_app/models/org_feed_models.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/models/saved_item_models.dart';
import 'org_feed_comments_screen.dart';
import 'org_feed_composer_sheet.dart';
import 'org_feed_widgets.dart';
import 'organization_sheets.dart';
import 'organization_widgets.dart';

class OrgFeedTab extends StatefulWidget {
  const OrgFeedTab({
    super.key,
    required this.organization,
    required this.members,
    required this.teams,
  });

  final Organization organization;
  final List<OrgMember> members;
  final List<OrgTeam> teams;

  @override
  State<OrgFeedTab> createState() => _OrgFeedTabState();
}

class _OrgFeedTabState extends State<OrgFeedTab> with AutomaticKeepAliveClientMixin {
  final _repo = OrgFeedRepository.instance;
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _barVisible = true;

  List<OrgFeedPost> _posts = [];
  String? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _requestId = 0;

  OrgPostCategory? _category;
  bool _pinnedOnly = false;
  String? _teamId;
  String _search = '';

  late final Map<String, SocketHandler> _handlers = {
    'org:feed:post:new': _onPostNew,
    'org:feed:post:updated': _onPostUpdated,
    'org:feed:post:deleted': _onPostDeleted,
    'org:feed:post:pinned': _onPostPinned,
    'org:feed:reaction:updated': _onReaction,
    'org:feed:comment:new': _onCommentNew,
    'org:feed:comment:deleted': _onCommentDeleted,
  };

  @override
  bool get wantKeepAlive => true;

  String get _orgId => widget.organization.id;
  bool get _canManage => orgCanInvite(widget.organization.role);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    SocketService.instance.ensureConnected();
    SocketService.instance.joinOrg(_orgId);
    _handlers.forEach(SocketService.instance.on);
    SavedItemsStore.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _handlers.forEach(SocketService.instance.off);
    SocketService.instance.leaveOrg(_orgId);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _onScrollNotification(UserScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n.direction == ScrollDirection.reverse && _barVisible && n.metrics.pixels > 40) {
      FocusScope.of(context).unfocus();
      setState(() => _barVisible = false);
    } else if (n.direction == ScrollDirection.forward && !_barVisible) {
      setState(() => _barVisible = true);
    }
    return false;
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels <= 0 && !_barVisible) setState(() => _barVisible = true);
    if (_scroll.position.extentAfter < 400) _loadMore();
  }

  Future<void> _load({bool silent = false}) async {
    final id = ++_requestId;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await _repo.feed(
        _orgId,
        category: _category,
        teamId: _teamId,
        search: _search,
        pinnedOnly: _pinnedOnly,
      );
      if (!mounted || id != _requestId) return;
      setState(() {
        _posts = page.posts;
        _cursor = page.nextCursor;
        _hasMore = page.hasNextPage && page.nextCursor != null;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _loading = false;
        if (_posts.isEmpty) _error = errorText(e);
      });
      if (_posts.isNotEmpty) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final id = _requestId;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.feed(
        _orgId,
        category: _category,
        teamId: _teamId,
        search: _search,
        pinnedOnly: _pinnedOnly,
        cursor: _cursor,
      );
      if (!mounted || id != _requestId) return;
      final known = {for (final p in _posts) p.id};
      setState(() {
        _posts = [..._posts, ...page.posts.where((p) => !known.contains(p.id))];
        _cursor = page.nextCursor;
        _hasMore = page.hasNextPage && page.nextCursor != null;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      orgToast(context, errorText(e), error: true);
    }
  }

  void _applyFilters() {
    setState(() => _posts = []);
    _load();
  }

  void _setCategory(OrgPostCategory? c) {
    if (_category == c && !_pinnedOnly) return;
    _category = c;
    _pinnedOnly = false;
    _applyFilters();
  }

  void _setPinned() {
    if (_pinnedOnly) return;
    _pinnedOnly = true;
    _category = null;
    _applyFilters();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || value.trim() == _search) return;
      _search = value.trim();
      _applyFilters();
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _debounce?.cancel();
    setState(() {});
    if (_search.isEmpty) return;
    _search = '';
    _applyFilters();
  }

  bool _matches(OrgFeedPost p) {
    if (_category != null && p.category != _category) return false;
    if (_pinnedOnly && !p.isPinned) return false;
    if (_teamId != null && p.targetTeamId != _teamId) return false;
    final q = _search.toLowerCase();
    if (q.isNotEmpty && !'${p.title ?? ''} ${p.content}'.toLowerCase().contains(q)) return false;
    return true;
  }

  void _sort() {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    _posts.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch);
    });
  }

  int _indexOf(String id) => _posts.indexWhere((p) => p.id == id);

  void _replace(OrgFeedPost post) {
    final i = _indexOf(post.id);
    if (i < 0 || !mounted) return;
    setState(() => _posts[i] = post);
  }

  List<OrgFeedReaction> _preserveMine(List<OrgFeedReaction> local, List<OrgFeedReaction> incoming) {
    final mine = {for (final r in local) r.emoji: r.reactedByMe};
    return [for (final r in incoming) r.copyWith(reactedByMe: mine[r.emoji] ?? false)];
  }

  Map<String, dynamic>? _event(dynamic data) {
    final m = asMap(data);
    if (m == null || m['organizationId']?.toString() != _orgId || !mounted) return null;
    return m;
  }

  OrgFeedPost? _postFrom(Map<String, dynamic> m) {
    final raw = m['post'];
    if (raw is! Map) return null;
    final post = OrgFeedPost.fromJson(Map<String, dynamic>.from(raw));
    return post.id.isEmpty ? null : post;
  }

  void _onPostNew(dynamic data) {
    final m = _event(data);
    if (m == null) return;
    final post = _postFrom(m);
    if (post == null || _indexOf(post.id) >= 0 || !_matches(post)) return;
    setState(() {
      _posts = [post, ..._posts];
      _sort();
    });
  }

  void _onPostUpdated(dynamic data) {
    final m = _event(data);
    if (m == null) return;
    final post = _postFrom(m);
    if (post == null) return;
    final i = _indexOf(post.id);
    if (i < 0) return;
    final old = _posts[i];
    final raw = Map<String, dynamic>.from(m['post'] as Map);
    final merged = post.copyWith(
      reactions: raw.containsKey('reactions') ? _preserveMine(old.reactions, post.reactions) : old.reactions,
      commentCount: raw.containsKey('commentCount') ? post.commentCount : old.commentCount,
    );
    setState(() {
      _posts[i] = merged;
      _sort();
    });
  }

  void _onPostDeleted(dynamic data) {
    final m = _event(data);
    if (m == null) return;
    final id = m['postId']?.toString() ?? '';
    if (_indexOf(id) < 0) return;
    setState(() => _posts = _posts.where((p) => p.id != id).toList());
  }

  void _onPostPinned(dynamic data) {
    final m = _event(data);
    if (m == null) return;
    final post = _postFrom(m);
    if (post == null) return;
    final i = _indexOf(post.id);
    setState(() {
      if (i < 0) {
        if (_matches(post)) {
          _posts = [post, ..._posts];
        }
      } else if (_pinnedOnly && !post.isPinned) {
        _posts = _posts.where((p) => p.id != post.id).toList();
      } else {
        _posts[i] = _posts[i].copyWith(isPinned: post.isPinned, pinnedAt: post.pinnedAt);
      }
      _sort();
    });
  }

  void _onReaction(dynamic data) {
    final m = _event(data);
    if (m == null) return;
    final i = _indexOf(m['postId']?.toString() ?? '');
    if (i < 0) return;
    final old = _posts[i];
    final incoming = OrgFeedReaction.listFrom(m['reactions']);
    final mine = {for (final r in old.reactions) r.emoji: r.reactedByMe};
    if (m['actorId']?.toString() == CurrentUser.id) {
      mine[m['emoji']?.toString() ?? ''] = m['action']?.toString() == 'added';
    }
    setState(() {
      _posts[i] = old.copyWith(
        reactions: [for (final r in incoming) r.copyWith(reactedByMe: mine[r.emoji] ?? false)],
      );
    });
  }

  void _onCommentNew(dynamic data) {
    final m = _event(data);
    if (m == null) return;
    final i = _indexOf(m['postId']?.toString() ?? '');
    if (i < 0) return;
    setState(() => _posts[i] = _posts[i].copyWith(commentCount: _posts[i].commentCount + 1));
  }

  void _onCommentDeleted(dynamic data) {
    final m = _event(data);
    if (m == null) return;
    final i = _indexOf(m['postId']?.toString() ?? '');
    if (i < 0) return;
    final next = _posts[i].commentCount - 1;
    setState(() => _posts[i] = _posts[i].copyWith(commentCount: next < 0 ? 0 : next));
  }

  List<OrgFeedReaction> _toggleLocal(List<OrgFeedReaction> list, String emoji) {
    final i = list.indexWhere((r) => r.emoji == emoji);
    if (i < 0) return [...list, OrgFeedReaction(emoji: emoji, count: 1, reactedByMe: true)];
    final r = list[i];
    final copy = [...list];
    if (r.reactedByMe) {
      if (r.count - 1 <= 0) {
        copy.removeAt(i);
      } else {
        copy[i] = r.copyWith(count: r.count - 1, reactedByMe: false);
      }
    } else {
      copy[i] = r.copyWith(count: r.count + 1, reactedByMe: true);
    }
    return copy;
  }

  Future<void> _react(OrgFeedPost post, String emoji) async {
    final previous = post.reactions;
    _replace(post.copyWith(reactions: _toggleLocal(post.reactions, emoji)));
    try {
      final res = await _repo.react(_orgId, post.id, emoji);
      if (!mounted) return;
      final i = _indexOf(post.id);
      if (i >= 0) _replace(_posts[i].copyWith(reactions: res.reactions));
    } catch (e) {
      if (!mounted) return;
      final i = _indexOf(post.id);
      if (i >= 0) _replace(_posts[i].copyWith(reactions: previous));
      orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _pickReaction(OrgFeedPost post) async {
    final emoji = await pickOrgFeedEmoji(context);
    if (emoji != null) _react(post, emoji);
  }

  Future<void> _refreshOne(String postId) async {
    try {
      final fresh = await _repo.getPost(_orgId, postId);
      if (!mounted) return;
      _replace(fresh);
    } on ApiException catch (e) {
      if (!mounted || e.statusCode != 404) return;
      setState(() => _posts = _posts.where((p) => p.id != postId).toList());
    } catch (_) {}
  }

  Future<void> _openComments(OrgFeedPost post) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrgFeedCommentsScreen(
          organization: widget.organization,
          post: post,
          canManage: _canManage,
        ),
      ),
    );
    if (mounted) _refreshOne(post.id);
  }

  Future<void> _toggleSave(OrgFeedPost post) async {
    try {
      final saved = await SavedItemsStore.instance.toggle(SavedItemType.orgPost, post.id);
      if (!mounted) return;
      setState(() {});
      orgToast(context, saved ? 'Post saved' : 'Removed from saved');
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _togglePin(OrgFeedPost post) async {
    try {
      await _repo.togglePin(_orgId, post.id);
      if (!mounted) return;
      await _refreshOne(post.id);
      if (!mounted) return;
      final i = _indexOf(post.id);
      setState(() {
        if (i >= 0 && _pinnedOnly && !_posts[i].isPinned) {
          _posts = _posts.where((p) => p.id != post.id).toList();
        }
        _sort();
      });
      orgToast(context, post.isPinned ? 'Post unpinned' : 'Post pinned to top');
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _edit(OrgFeedPost post) async {
    final updated = await showOrgSheet<OrgFeedPost>(
      context,
      OrgFeedEditSheet(organizationId: _orgId, post: post),
    );
    if (updated == null || !mounted) return;
    final i = _indexOf(post.id);
    final current = i >= 0 ? _posts[i] : post;
    _replace(updated.copyWith(reactions: current.reactions, commentCount: current.commentCount));
    orgToast(context, 'Post updated');
  }

  Future<void> _delete(OrgFeedPost post) async {
    final ok = await orgConfirm(
      context,
      title: 'Delete post',
      body: 'This post and its comments will be removed for everyone.',
      action: 'Delete',
    );
    if (!ok) return;
    try {
      await _repo.deletePost(_orgId, post.id);
      if (!mounted) return;
      setState(() => _posts = _posts.where((p) => p.id != post.id).toList());
      orgToast(context, 'Post deleted');
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _compose() async {
    final post = await showOrgSheet<OrgFeedPost>(
      context,
      OrgFeedComposerSheet(
        organization: widget.organization,
        members: widget.members,
        teams: widget.teams,
      ),
    );
    if (post == null || !mounted) return;
    if (_indexOf(post.id) < 0 && _matches(post)) {
      setState(() {
        _posts = [post, ..._posts];
        _sort();
      });
    }
    orgToast(context, 'Posted to the organization feed');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _compose,
        backgroundColor: feedPurple,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _barVisible
                ? Column(children: [_searchRow(), _chips()])
                : const SizedBox(width: double.infinity),
          ),
          Expanded(
            child: NotificationListener<UserScrollNotification>(
              onNotification: _onScrollNotification,
              child: _content(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              cursorColor: feedPurple,
              decoration: InputDecoration(
                hintText: 'Search the feed',
                hintStyle: const TextStyle(color: Color(0xFF5A5E6B)),
                prefixIcon: const Icon(Icons.search_rounded, color: orgMuted, size: 20),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close_rounded, color: orgMuted, size: 18),
                      ),
                filled: true,
                fillColor: orgField,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: orgBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: orgBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: feedPurple),
                ),
              ),
            ),
          ),
          if (widget.teams.isNotEmpty) ...[
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Filter by team',
              color: orgCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onSelected: (v) {
                final next = v.isEmpty ? null : v;
                if (next == _teamId) return;
                _teamId = next;
                _applyFilters();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: '',
                  child: Text(
                    'All teams',
                    style: TextStyle(
                      color: _teamId == null ? feedPurple : Colors.white,
                      fontWeight: _teamId == null ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                for (final t in widget.teams)
                  PopupMenuItem(
                    value: t.id,
                    child: Text(
                      t.name,
                      style: TextStyle(
                        color: _teamId == t.id ? feedPurple : Colors.white,
                        fontWeight: _teamId == t.id ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
              ],
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _teamId == null ? orgField : feedPurple.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _teamId == null ? orgBorder : feedPurple),
                ),
                child: Icon(
                  Icons.groups_outlined,
                  color: _teamId == null ? orgMuted : Colors.white,
                  size: 21,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chips() {
    Widget chip(String label, bool selected, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? feedPurple : orgField,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: selected ? feedPurple : orgBorder),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : orgMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          chip('All', _category == null && !_pinnedOnly, () => _setCategory(null)),
          chip('Announcements', _category == OrgPostCategory.announcement, () => _setCategory(OrgPostCategory.announcement)),
          chip('Festivals', _category == OrgPostCategory.festival, () => _setCategory(OrgPostCategory.festival)),
          chip('Milestones', _category == OrgPostCategory.milestone, () => _setCategory(OrgPostCategory.milestone)),
          chip('Birthdays', _category == OrgPostCategory.birthday, () => _setCategory(OrgPostCategory.birthday)),
          chip('Promotions', _category == OrgPostCategory.promotion, () => _setCategory(OrgPostCategory.promotion)),
          chip('General', _category == OrgPostCategory.general, () => _setCategory(OrgPostCategory.general)),
          chip('Pinned', _pinnedOnly, _setPinned),
        ],
      ),
    );
  }

  Widget _content() {
    if (_loading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: feedPurple));
    }
    if (_error != null && _posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: orgMuted, size: 42),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _load,
                child: const Text('Retry', style: TextStyle(color: feedPurple, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }
    final filtered = _category != null || _pinnedOnly || _teamId != null || _search.isNotEmpty;
    return RefreshIndicator(
      color: feedPurple,
      backgroundColor: orgCard,
      onRefresh: () => _load(silent: true),
      child: _posts.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 70),
                const Icon(Icons.dynamic_feed_rounded, color: orgMuted, size: 44),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    filtered ? 'No posts match your filters' : 'No posts yet. Be the first to share something.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: orgMuted),
                  ),
                ),
              ],
            )
          : ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: _posts.length + (_hasMore ? 1 : 0),
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index >= _posts.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: feedPurple),
                      ),
                    ),
                  );
                }
                final post = _posts[index];
                return OrgFeedPostCard(
                  key: ValueKey(post.id),
                  post: post,
                  myId: CurrentUser.id,
                  canManage: _canManage,
                  saved: SavedItemsStore.instance.isSaved(SavedItemType.orgPost, post.id),
                  onReact: (emoji) => _react(post, emoji),
                  onPickReaction: () => _pickReaction(post),
                  onComments: () => _openComments(post),
                  onSave: () => _toggleSave(post),
                  onPin: () => _togglePin(post),
                  onEdit: () => _edit(post),
                  onDelete: () => _delete(post),
                );
              },
            ),
    );
  }
}
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/community_repository.dart';
import 'package:quorum_app/models/community_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'package:quorum_app/screens/community_screen/communtiy_details_screen.dart';
import 'package:quorum_app/widgets/card_shade.dart';
import 'package:quorum_app/widgets/swipe_card_deck.dart';
import 'community_widgets.dart';
import 'my_join_requests_screen.dart';

class CommunityDiscoverScreen extends StatefulWidget {
  const CommunityDiscoverScreen({super.key});

  @override
  State<CommunityDiscoverScreen> createState() => _CommunityDiscoverScreenState();
}

class _CommunityDiscoverScreenState extends State<CommunityDiscoverScreen> {
  static const Color darkBg = Color(0xFF0A0B14);
  static const Color cardBg = Color(0xFF16172B);
  static const Color cardBorder = Color(0xFF2A2C4A);
  static const Color violet = Color(0xFF7C5CFC);
  static const Color violetLight = Color(0xFF9B82FF);
  static const Color amber = Color(0xFFF59E0B);
  static const Color green = Color(0xFF22C55E);
  static const Color muted = Color(0xFF9A9CB8);

  final _repo = CommunityRepository.instance;
  final _scroll = ScrollController();
  final _search = TextEditingController();

  List<DiscoveredCommunity> _items = [];
  String? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String _query = '';
  int _token = 0;
  Timer? _debounce;
  final Set<String> _busy = {};
  final Set<String> _skipped = {};
  final Map<String, String> _deckRequests = {};
  final _deckKey = GlobalKey<SwipeCardDeckState<DiscoveredCommunity>>();
  bool _showJoined = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) _loadMore();
  }

  void _onChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final next = value.trim();
      if (next == _query) return;
      _query = next;
      _load();
    });
  }

  void _clear() {
    _search.clear();
    _debounce?.cancel();
    if (_query.isEmpty) {
      setState(() {});
      return;
    }
    _query = '';
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    final token = ++_token;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await _repo.discover(_query);
      if (!mounted || token != _token) return;
      setState(() {
        _items = page.items;
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        if (!silent) _error = errorText(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _cursor == null) return;
    final token = _token;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.discover(_query, cursor: _cursor);
      if (!mounted || token != _token) return;
      final known = _items.map((c) => c.id).toSet();
      setState(() {
        _items = [..._items, ...page.items.where((c) => !known.contains(c.id))];
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() => _loadingMore = false);
      showErrorSnack(context, errorText(e));
    }
  }

  void _replace(String id, DiscoveredCommunity Function(DiscoveredCommunity) update) {
    setState(() => _items = [for (final c in _items) c.id == id ? update(c) : c]);
  }

  List<DiscoveredCommunity> get _deckItems =>
      _items.where((c) => c.status == MembershipStatus.notMember && !_skipped.contains(c.id)).toList();

  Future<bool> _deckSwipe(DiscoveredCommunity c, SwipeDirection direction) async {
    if (direction == SwipeDirection.left) return true;
    final message = await showDialog<String>(
      context: context,
      builder: (_) => TextPromptDialog(
        title: 'Request to join ${c.name}',
        hint: 'Add a note for the admins (optional)',
        actionLabel: 'Send',
        maxLines: 4,
        maxLength: 500,
      ),
    );
    if (message == null || !mounted) return false;
    try {
      final request = await _repo.sendJoinRequest(c.id, message: message);
      if (!mounted) return false;
      _deckRequests[c.id] = request.id;
      showCommunityToast(context, 'Join request sent to ${c.name}');
      return true;
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
      return false;
    }
  }

  void _deckSwiped(DiscoveredCommunity c, SwipeDirection direction) {
    if (direction == SwipeDirection.left) {
      setState(() => _skipped.add(c.id));
    } else {
      final requestId = _deckRequests.remove(c.id);
      _replace(c.id, (x) => x.copyWith(status: MembershipStatus.pendingRequest, pendingRequestId: requestId));
    }
    if (_deckItems.length < 4) _loadMore();
  }

  Future<void> _requestJoin(DiscoveredCommunity c) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => TextPromptDialog(
        title: 'Request to join ${c.name}',
        hint: 'Add a note for the admins (optional)',
        actionLabel: 'Send',
        maxLines: 4,
        maxLength: 500,
      ),
    );
    if (message == null || !mounted) return;
    setState(() => _busy.add(c.id));
    try {
      final request = await _repo.sendJoinRequest(c.id, message: message);
      if (!mounted) return;
      _replace(
        c.id,
        (x) => x.copyWith(status: MembershipStatus.pendingRequest, pendingRequestId: request.id),
      );
      showCommunityToast(context, 'Join request sent to ${c.name}');
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy.remove(c.id));
    }
  }

  Future<void> _cancelRequest(DiscoveredCommunity c) async {
    setState(() => _busy.add(c.id));
    try {
      await _repo.cancelJoinRequest(c.id);
      if (!mounted) return;
      _replace(c.id, (x) => x.copyWith(status: MembershipStatus.notMember, clearPending: true));
      showCommunityToast(context, 'Join request cancelled');
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy.remove(c.id));
    }
  }

  Future<void> _open(DiscoveredCommunity c) async {
    if (!c.status.isJoined) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityDetailScreen(
          communityId: c.id,
          initialName: c.name,
          initialRole: c.status.role,
        ),
      ),
    );
    if (mounted) _load(silent: true);
  }

  Future<void> _openMyRequests() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyJoinRequestsScreen()),
    );
    if (mounted) _load(silent: true);
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _search,
        onChanged: _onChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (v) {
          _debounce?.cancel();
          final next = v.trim();
          if (next == _query && !_loading) return;
          _query = next;
          _load();
        },
        style: const TextStyle(color: Colors.white, fontSize: 14),
        cursorColor: violetLight,
        decoration: InputDecoration(
          hintText: 'Search public communities',
          hintStyle: const TextStyle(color: muted, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: muted, size: 20),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  onPressed: _clear,
                  icon: const Icon(Icons.close, color: muted, size: 18),
                ),
          filled: true,
          fillColor: cardBg,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: violet),
          ),
        ),
      ),
    );
  }

  Widget _avatar(DiscoveredCommunity c, [double size = 52]) {
    final icon = c.icon;
    if (icon == null) return CommunityAvatar(name: c.name, size: size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: Image.network(
        icon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => CommunityAvatar(name: c.name, size: size),
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _action(DiscoveredCommunity c) {
    final busy = _busy.contains(c.id);
    if (busy) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: violetLight),
      );
    }
    switch (c.status) {
      case MembershipStatus.owner:
      case MembershipStatus.admin:
      case MembershipStatus.member:
        return _statusPill('Joined · ${roleLabel(c.status.role)}', green);
      case MembershipStatus.pendingRequest:
        return GestureDetector(
          onTap: () => _cancelRequest(c),
          child: _statusPill('Requested · Cancel', amber),
        );
      case MembershipStatus.notMember:
        return FilledButton(
          onPressed: () => _requestJoin(c),
          style: FilledButton.styleFrom(
            backgroundColor: violet,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: const StadiumBorder(),
          ),
          child: const Text('Request to join', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        );
    }
  }

  Widget _card(DiscoveredCommunity c) {
    final description = c.description;
    final hasDesc = description != null && description.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: c.status.isJoined ? () => _open(c) : null,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _avatar(c),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasDesc ? description : 'No description yet',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: muted, fontSize: 13, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.groups, size: 14, color: violetLight),
                    const SizedBox(width: 4),
                    Text(
                      c.memberCount == 1 ? '1 member' : '${c.memberCount} members',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.tag, size: 14, color: muted),
                    const SizedBox(width: 2),
                    Text(
                      c.channelCount == 1 ? '1 channel' : '${c.channelCount} channels',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const Spacer(),
                    _action(c),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _glowAvatar(DiscoveredCommunity c) {
    final icon = c.icon;
    final initial = c.name.trim().isNotEmpty ? c.name.trim()[0].toUpperCase() : '?';
    Widget letter() => Container(
          alignment: Alignment.center,
          color: const Color(0xFF0E0E24),
          child: Text(
            initial,
            style: const TextStyle(color: Colors.white, fontSize: 46, fontWeight: FontWeight.w800),
          ),
        );
    return Container(
      width: 112,
      height: 112,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF14142E),
        border: Border.all(color: violet.withValues(alpha: 0.45), width: 1.5),
        boxShadow: [BoxShadow(color: violet.withValues(alpha: 0.35), blurRadius: 28, spreadRadius: 2)],
      ),
      child: ClipOval(
        child: icon == null
            ? letter()
            : Image.network(icon, fit: BoxFit.cover, errorBuilder: (_, _, _) => letter()),
      ),
    );
  }

  Widget _orb(double size, List<Color> colors) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: colors, begin: Alignment.topCenter, end: Alignment.bottomCenter),
      ),
    );
  }

  Widget _deckInfo(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF6C5CF5)),
        const SizedBox(width: 7),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _deckFace(DiscoveredCommunity c, double depth) {
    final description = c.description;
    final hasDesc = description != null && description.isNotEmpty;
    final base = cardShade(depth);
    final tint = Color.lerp(base, const Color(0xFF5B4BF0), (0.65 - depth * 0.2).clamp(0.1, 0.65))!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Color.lerp(base, Colors.white, 0.12)!),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -210,
              right: -120,
              child: _orb(380, [tint, base]),
            ),
            Positioned(
              bottom: -230,
              left: -80,
              child: _orb(340, [base, tint]),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _glowAvatar(c),
                    const SizedBox(height: 26),
                    Text(
                      c.name,
                      maxLines: 3,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, height: 1.15),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 32,
                      runSpacing: 8,
                      children: [
                        _deckInfo(Icons.groups_rounded, c.memberCount == 1 ? '1 Member' : '${c.memberCount} Members'),
                        _deckInfo(Icons.lock_rounded, 'Private'),
                      ],
                    ),
                    if (hasDesc) ...[
                      const SizedBox(height: 16),
                      Text(
                        description,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFB9BBD8), fontSize: 13.5, height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 30,
              child: Text(
                'Swipe to join or remove',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs() {
    Widget pill(String label, bool selected, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF5B4BF0) : cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? const Color(0xFF7A6CF7) : cardBorder, width: 1.2),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFB4B6D0),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          pill('Explore', !_showJoined, () => setState(() => _showJoined = false)),
          pill('Joined', _showJoined, () => setState(() => _showJoined = true)),
        ],
      ),
    );
  }

  Widget _deckView() {
    final items = _deckItems;
    if (items.isEmpty) {
      if ((_hasMore && _cursor != null) || _loadingMore) {
        if (!_loadingMore) WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
        return const Center(child: CircularProgressIndicator(color: violet));
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.done_all_rounded, size: 52, color: violetLight),
              const SizedBox(height: 12),
              const Text(
                "You're all caught up",
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'No more communities to swipe right now.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (_skipped.isNotEmpty)
                FilledButton(
                  onPressed: () => setState(_skipped.clear),
                  style: FilledButton.styleFrom(
                    backgroundColor: violet,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Show skipped again'),
                ),
              TextButton(
                onPressed: () => setState(() => _showJoined = true),
                child: const Text('View joined communities', style: TextStyle(color: violetLight)),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < 140) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
          child: SwipeCardDeck<DiscoveredCommunity>(
            key: _deckKey,
            items: items,
            rightLabel: 'JOIN',
            leftLabel: 'SKIP',
            rightColor: green,
            leftColor: const Color(0xFFEF4444),
            itemBuilder: (_, c, depth) => _deckFace(c, depth),
            onSwipe: _deckSwipe,
            onSwiped: _deckSwiped,
          ),
        );
      },
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: violet));
    }
    if (_error != null) {
      return CenteredMessage(
        icon: Icons.cloud_off,
        text: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    final joined = _items.where((c) => c.status.isJoined).toList();
    if (_items.isEmpty || joined.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 320,
            child: CenteredMessage(
              icon: _items.isEmpty && _query.isNotEmpty ? Icons.search_off : Icons.groups_outlined,
              text: _query.isNotEmpty
                  ? 'No communities match "$_query".'
                  : _showJoined
                      ? "You haven't joined any communities yet."
                      : 'No public communities to show yet.',
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: joined.length + (_loadingMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= joined.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: violet),
              ),
            ),
          );
        }
        return _card(joined[i]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: darkBg,
      appBar: AppBar(
        backgroundColor: darkBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Discover communities',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'My requests',
            onPressed: _openMyRequests,
            icon: const Icon(Icons.hourglass_top_rounded, color: violetLight, size: 22),
          ),
        ],
      ),
      body: Column(
        children: [
          _searchField(),
          _tabs(),
          Expanded(
            child: !_showJoined && !_loading && _error == null && _items.isNotEmpty
                ? _deckView()
                : RefreshIndicator(
                    color: violet,
                    backgroundColor: cardBg,
                    onRefresh: () => _load(silent: true),
                    child: _body(),
                  ),
          ),
        ],
      ),
    );
  }
}
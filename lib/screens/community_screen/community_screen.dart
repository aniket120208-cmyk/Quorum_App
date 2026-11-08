import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/community_repository.dart';
import 'package:quorum_app/api/notification_service.dart';
import 'package:quorum_app/models/community_models.dart';
import 'package:quorum_app/models/notification_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'package:quorum_app/screens/community_screen/communtiy_details_screen.dart';
import 'package:quorum_app/widgets/wallet_card_stack.dart';
import 'community_discover_screen.dart';
import 'community_widgets.dart';

enum _Filter { all, owned, member }

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  static const Color darkBg = Colors.transparent;
  static const Color cardBg = Color(0xFF16172B);
  static const Color cardBorder = Color(0xFF2A2C4A);
  static const Color violet = Color(0xFF7C5CFC);
  static const Color violetLight = Color(0xFF9B82FF);
  static const Color teal = Color(0xFF2DD4B0);
  static const Color tealDark = Color(0xFF14806B);

  final _repo = CommunityRepository.instance;
  List<Community> _items = [];
  bool _loading = true;
  String? _error;
  _Filter _filter = _Filter.all;
  StreamSubscription<NotificationItem>? _notificationSub;
  bool _walletMode = false;
  int _walletFront = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _notificationSub = NotificationService.instance.incoming.listen((n) {
      if (n.type == NotificationType.communityJoinAccepted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }

  Future<void> _discover() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CommunityDiscoverScreen()),
    );
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _repo.communities();
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

  Future<void> _open(Community c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityDetailScreen(
          communityId: c.id,
          initialName: c.name,
          initialRole: c.role,
        ),
      ),
    );
    if (mounted) _load(silent: true);
  }

  Future<void> _create() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const CommunityFormDialog(title: 'New community', actionLabel: 'Create'),
    );
    if (result == null || !mounted) return;
    try {
      final c = await _repo.createCommunity(result.$1, result.$2);
      if (!mounted) return;
      setState(() => _items = [c, ..._items]);
      await _open(c);
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _joinWithLink() async {
    final input = await showDialog<String>(
      context: context,
      builder: (_) => const TextPromptDialog(
        title: 'Join with invite link',
        hint: 'Paste the invite link or code',
        actionLabel: 'Continue',
      ),
    );
    if (input == null || input.isEmpty || !mounted) return;

    final token = parseInviteToken(input);
    try {
      final preview = await _repo.previewInvite(token);
      if (!preview.valid) {
        throw ApiException('This invitation is no longer valid.');
      }
      if (!mounted) return;

      final details = [
        if (preview.description != null && preview.description!.isNotEmpty) preview.description!,
        '${preview.memberCount} members${preview.inviterName.isEmpty ? '' : ' · invited by ${preview.inviterName}'}',
      ].join('\n\n');

      final ok = await confirmAction(
        context,
        title: 'Join ${preview.communityName}?',
        body: details,
        action: 'Join',
        destructive: false,
      );
      if (!ok || !mounted) return;

      final joined = await _repo.joinInvite(token);
      if (!mounted) return;
      setState(() => _items = [joined, ..._items.where((c) => c.id != joined.id)]);
      await _open(joined);
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  bool _isOwner(Community c) => c.role.toString().toLowerCase().contains('owner');

  String _roleLabel(Community c) {
    final raw = c.role.toString().split('.').last;
    if (raw.isEmpty) return '';
    return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final p = parts.first;
      return p.substring(0, p.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  List<Community> get _filtered {
    switch (_filter) {
      case _Filter.owned:
        return _items.where(_isOwner).toList();
      case _Filter.member:
        return _items.where((c) => !_isOwner(c)).toList();
      case _Filter.all:
        return _items;
    }
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [violet, violetLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.groups, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Community',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Explore & connect',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Color(0xFF9A9CB8), fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Discover communities',
            onPressed: _discover,
            icon: const Icon(Icons.search, color: violetLight, size: 22),
          ),
          IconButton(
            tooltip: 'Join with link',
            onPressed: _joinWithLink,
            icon: const Icon(Icons.link, color: violetLight, size: 20),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Create', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              backgroundColor: violet,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: const StadiumBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChips() {
    Widget chip(String label, _Filter f) {
      final selected = _filter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() => _filter = f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? violet : cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? violetLight : cardBorder, width: 1.2),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFB4B6D0),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          chip('All', _Filter.all),
          chip('Owned', _Filter.owned),
          chip('Member', _Filter.member),
          const Spacer(),
          _viewToggle(),
        ],
      ),
    );
  }

  Widget _rolePill(Community c) {
    final owner = _isOwner(c);
    final color = owner ? teal : violetLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.2),
        color: color.withValues(alpha: 0.08),
      ),
      child: Text(
        _roleLabel(c),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _communityCard(Community c) {
    final description = c.description;
    final hasDesc = description != null && description.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _open(c),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cardBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [violet, violetLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Text(
                    _initials(c.name),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _rolePill(c),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (hasDesc)
                        Text(
                          description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF9A9CB8), fontSize: 13),
                        )
                      else
                        Row(
                          children: [
                            const Icon(Icons.groups, size: 14, color: violetLight),
                            const SizedBox(width: 4),
                            Text(
                              c.memberCount == 1 ? '1 member' : '${c.memberCount} members',
                              style: const TextStyle(color: Color(0xFF9A9CB8), fontSize: 12),
                            ),
                            const SizedBox(width: 14),
                            const Icon(Icons.lock_outline, size: 14, color: Color(0xFF9A9CB8)),
                            const SizedBox(width: 4),
                            const Text(
                              'Private',
                              style: TextStyle(color: Color(0xFF9A9CB8), fontSize: 12),
                            ),
                          ],
                        ),
                      if (hasDesc) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.groups, size: 14, color: violetLight),
                            const SizedBox(width: 4),
                            Text(
                              c.memberCount == 1 ? '1 member' : '${c.memberCount} members',
                              style: const TextStyle(color: Color(0xFF9A9CB8), fontSize: 12),
                            ),
                            const SizedBox(width: 12),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _communitiesHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 22, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your communities',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 2),
        ],
      ),
    );
  }

  Widget _viewToggle() {
    Widget btn(IconData icon, bool active, String tip, VoidCallback onTap) {
      return Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: active ? violet : cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: active ? violetLight : cardBorder, width: 1.2),
            ),
            child: Icon(icon, size: 18, color: active ? Colors.white : const Color(0xFFB4B6D0)),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.style_outlined, !_walletMode, 'List', () => setState(() => _walletMode = false)),
        const SizedBox(width: 6),
        btn(Icons.view_agenda_outlined, _walletMode, 'Cards', () => setState(() => _walletMode = true)),
      ],
    );
  }

  static const List<List<Color>> _walletPalettes = [
    [Color(0xFF7C5CFC), Color(0xFF4C3AE3)],
    [Color(0xFF22A58A), Color(0xFF14806B)],
    [Color(0xFFF59E0B), Color(0xFFEA580C)],
    [Color(0xFFEC4899), Color(0xFFBE185D)],
    [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
  ];

  Widget _walletFace(Community c, int index) {
    final colors = _walletPalettes[index % _walletPalettes.length];
    final description = c.description;
    final hasDesc = description != null && description.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, -2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _roleLabel(c),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            hasDesc ? description : 'Private community',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, height: 1.3),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.groups, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                c.memberCount == 1 ? '1 member' : '${c.memberCount} members',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.22)),
                child: Text(
                  _initials(c.name),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _walletView(List<Community> list) {
    final position = (_walletFront % list.length) + 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        const footerHeight = 76.0;
        final stackMax = constraints.maxHeight - footerHeight;
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    WalletCardStack(
                      itemCount: list.length,
                      cardHeight: 190,
                      peek: 40,
                      maxVisible: 25,
                      maxHeight: stackMax,
                      itemBuilder: (_, i) => _walletFace(list[i], i),
                      onTap: (i) => _open(list[i]),
                      onFrontChanged: (i) => setState(() => _walletFront = i),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '$position / ${list.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Swipe the community away  •  Tap to open',
                      style: TextStyle(color: Color(0xFF9A9CB8), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statusBlock() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator(color: violet)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: CenteredMessage(
          icon: Icons.cloud_off,
          text: _error!,
          actionLabel: 'Retry',
          onAction: _load,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.groups_outlined, size: 48, color: Color(0xFF9A9CB8)),
          const SizedBox(height: 10),
          Text(
            _items.isEmpty ? 'No communities yet' : 'Nothing here',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            _items.isEmpty
                ? 'Create a private community for your team, or join one with an invite link.'
                : 'No communities match this filter.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF9A9CB8), fontSize: 13),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final showContent = !_loading && _error == null && list.isNotEmpty;

    return Scaffold(
      backgroundColor: darkBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            _filterChips(),
            const SizedBox(height: 8),
            Expanded(
              child: (showContent && !_walletMode)
                  ? _walletView(list)
                  : RefreshIndicator(
                      color: violet,
                      backgroundColor: cardBg,
                      onRefresh: () => _load(silent: true),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          if (showContent) ...[
                            _communitiesHeader(),
                            for (final c in list) _communityCard(c),
                          ] else
                            _statusBlock(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/community_repository.dart';
import 'package:quorum_app/models/community_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'package:quorum_app/screens/community_screen/communtiy_details_screen.dart';
import 'community_widgets.dart';

enum _Filter { all, owned, member }

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  static const Color darkBg = Color(0xFF0A0B14);
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Community',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Explore & connect',
                  style: TextStyle(color: Color(0xFF9A9CB8), fontSize: 12),
                ),
              ],
            ),
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

  Widget _heroCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorder),
        gradient: const LinearGradient(
          colors: [Color(0xFF2A2563), Color(0xFF161733)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Build your circle • Start a community',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Host dedicated sessions, collaborate with peers.',
                  style: TextStyle(color: Color(0xFF9A9CB8), fontSize: 12, height: 1.3),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text(
                    'Create Community',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: violet,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: const StadiumBorder(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: violet.withValues(alpha: 0.25),
            ),
            child: const Icon(Icons.groups, color: violetLight, size: 26),
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
        ],
      ),
    );
  }

  Widget _circlesSection(List<Community> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Row(
            children: [
              const Icon(Icons.hub_outlined, color: teal, size: 20),
              const SizedBox(width: 8),
              const Text(
                'My Circles',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: teal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${list.length} Active',
                  style: const TextStyle(color: teal, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 106,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final c = list[i];
              return GestureDetector(
                onTap: () => _open(c),
                child: SizedBox(
                  width: 70,
                  child: Column(
                    children: [
                      Container(
                        width: 66,
                        height: 66,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF22A58A), tealDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Text(
                          _initials(c.name),
                          style: const TextStyle(
                            color: teal,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
                            const Icon(Icons.lock_outline, size: 14, color: Color(0xFF9A9CB8)),
                            const SizedBox(width: 4),
                            const Text(
                              'Private',
                              style: TextStyle(color: Color(0xFF9A9CB8), fontSize: 12),
                            ),
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
          Text(
            'Private hubs you own or belong to',
            style: TextStyle(color: Color(0xFF9A9CB8), fontSize: 12),
          ),
        ],
      ),
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
        child: RefreshIndicator(
          color: violet,
          backgroundColor: cardBg,
          onRefresh: () => _load(silent: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _header(),
              _heroCard(),
              _filterChips(),
              if (showContent) ...[
                _circlesSection(list),
                _communitiesHeader(),
                for (final c in list) _communityCard(c),
              ] else
                _statusBlock(),
            ],
          ),
        ),
      ),
    );
  }
}
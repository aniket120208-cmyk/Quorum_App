import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/community_repository.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'package:quorum_app/models/community_models.dart';
import 'community_widgets.dart';

class CommunityInviteScreen extends StatefulWidget {
  const CommunityInviteScreen({
    super.key,
    required this.communityId,
    required this.communityName,
  });

  final String communityId;
  final String communityName;

  @override
  State<CommunityInviteScreen> createState() => _CommunityInviteScreenState();
}

class _CommunityInviteScreenState extends State<CommunityInviteScreen> {
  static const Color darkBg = Color(0xFF0F101A);
  static const List<int> _dayOptions = [1, 3, 7, 14, 30];

  final _repo = CommunityRepository.instance;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  int _days = 7;
  InviteLink? _link;
  bool _generating = false;

  final Set<String> _invited = {};
  final Set<String> _inviting = {};
  List<ChatUser> _results = [];
  bool _searching = false;
  String? _searchError;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _expiryText(DateTime d) =>
      '${d.day}/${d.month}/${d.year} at ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _shareText(InviteLink link) =>
      'Join "${widget.communityName}" on Quorum: ${link.url}';

  Future<InviteLink?> _generate() async {
    if (_generating) return _link;
    setState(() => _generating = true);
    try {
      final link = await _repo.createInvite(widget.communityId, _days);
      if (!mounted) return null;
      setState(() => _link = link);
      return link;
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
      return null;
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _inviteUser(ChatUser user) async {
    if (_inviting.contains(user.id) || _invited.contains(user.id)) return;
    setState(() => _inviting.add(user.id));
    try {
      await _repo.inviteUser(widget.communityId, user.id);
      if (!mounted) return;
      setState(() => _invited.add(user.id));
      showCommunityToast(context, 'Invitation sent to ${user.name}');
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _inviting.remove(user.id));
    }
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final page = await _repo.searchUsers(widget.communityId, q);
      if (!mounted || _searchCtrl.text.trim() != q) return;
      setState(() {
        _results = page.items;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = errorText(e);
      });
    }
  }

  Widget _linkCard() {
    final link = _link;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Invite link',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Anyone with this link can join as a member until it expires.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          const Text('Expires in', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _dayOptions
                .map(
                  (d) => ChoiceChip(
                    label: Text(d == 1 ? '1 day' : '$d days'),
                    selected: _days == d,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _days = d),
                    selectedColor: AppColors.primary,
                    backgroundColor: Colors.transparent,
                    side: BorderSide(
                      color: _days == d ? AppColors.primary : AppColors.surfaceBorder,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: _days == d ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _generating ? null : _generate,
              icon: _generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.link, size: 18),
              label: Text(link == null ? 'Generate link' : 'Generate new link'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ),
          if (link != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: darkBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    link.url,
                    style: const TextStyle(color: AppColors.primaryLight, fontSize: 13),
                  ),
                  if (link.expiresAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Expires ${_expiryText(link.expiresAt!)}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => copyToClipboard(context, link.url, message: 'Link copied'),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy link'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.surfaceBorder),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        copyToClipboard(context, _shareText(link), message: 'Message copied'),
                    icon: const Icon(Icons.message_outlined, size: 16),
                    label: const Text('Copy message'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.surfaceBorder),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _userTile(ChatUser u) {
    final email = u.email;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ChatAvatar(name: u.name, imageUrl: u.avatarUrl, radius: 20),
      title: Text(u.name, style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: (email != null && email.isNotEmpty)
          ? Text(
              email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          : null,
      trailing: _invited.contains(u.id)
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 16, color: AppColors.primaryLight),
                SizedBox(width: 4),
                Text('Invited', style: TextStyle(color: AppColors.primaryLight, fontSize: 13)),
              ],
            )
          : TextButton.icon(
              onPressed: _inviting.contains(u.id) ? null : () => _inviteUser(u),
              icon: _inviting.contains(u.id)
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1, size: 16),
              label: const Text('Invite'),
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
          'Invite people',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _linkCard(),
          const SizedBox(height: 22),
          const Text(
            'Find people',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Search for someone and send them an invitation. They can accept or decline it from their notifications. People already in this community are not shown.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: communityFieldDecoration('Search by name or email').copyWith(
              prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
            ),
          ),
          if (_searching) const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
          if (_searchError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_searchError!, style: const TextStyle(color: Colors.redAccent)),
            ),
          const SizedBox(height: 6),
          ..._results.map(_userTile),
          if (!_searching &&
              _results.isEmpty &&
              _searchError == null &&
              _searchCtrl.text.trim().length >= 2)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('No people found.', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ),
        ],
      ),
    );
  }
}
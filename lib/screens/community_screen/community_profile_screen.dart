import 'package:flutter/material.dart';
import 'package:quorum_app/api/community_repository.dart';
import 'package:quorum_app/models/community_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'community_widgets.dart';

class CommunityProfileScreen extends StatefulWidget {
  const CommunityProfileScreen({
    super.key,
    required this.detail,
    required this.canManagePhoto,
    required this.canInvite,
    required this.onMembers,
    required this.onInvite,
    required this.onChangePhoto,
  });

  final CommunityDetail detail;
  final bool canManagePhoto;
  final bool canInvite;
  final Future<void> Function() onMembers;
  final Future<void> Function() onInvite;
  final Future<void> Function() onChangePhoto;

  @override
  State<CommunityProfileScreen> createState() => _CommunityProfileScreenState();
}

class _CommunityProfileScreenState extends State<CommunityProfileScreen> {
  static const Color darkBg = Color(0xFF0F101A);
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  late CommunityDetail _d = widget.detail;

  Future<void> _refresh() async {
    try {
      final d = await CommunityRepository.instance.detail(_d.id);
      if (mounted) setState(() => _d = d);
    } catch (_) {}
  }

  Future<void> _run(Future<void> Function() action) async {
    await action();
    await _refresh();
  }

  String _date(DateTime d) {
    final l = d.toLocal();
    return '${l.day} ${_months[l.month - 1]} ${l.year}';
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primaryLight, size: 20),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final desc = d.description?.trim() ?? '';
    final created = d.createdAt;
    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        backgroundColor: darkBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text(
          'Community',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: widget.canManagePhoto ? () => _run(widget.onChangePhoto) : null,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CommunityAvatar(name: d.name, size: 96, imageUrl: d.avatar),
                      if (widget.canManagePhoto)
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.surface, width: 2),
                          ),
                          child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 14),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  d.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people_outline, size: 15, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      d.memberCount == 1 ? '1 member' : '${d.memberCount} members',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    RoleBadge(role: d.role),
                  ],
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    desc,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.45),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Column(
              children: [
                if (created != null) _infoRow(Icons.calendar_today_rounded, 'Created', _date(created)),
                if (d.ownerName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        ChatAvatar(name: d.ownerName, imageUrl: d.ownerAvatar, radius: 10),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text('Owner', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        ),
                        Flexible(
                          child: Text(
                            d.ownerName,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _run(widget.onMembers),
                  icon: const Icon(Icons.people_outline, size: 18),
                  label: const Text('Members'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.surfaceBorder),
                  ),
                ),
              ),
              if (widget.canInvite) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _run(widget.onInvite),
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('Invite'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
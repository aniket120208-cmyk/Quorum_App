import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/chat_repository.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'package:quorum_app/screens/chat_screen/attachment_widgets.dart';
import 'package:quorum_app/screens/chat_screen/chat_room_screen.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'package:quorum_app/screens/profile_screen/profile_screen.dart';

const _bg = Color(0xFF0F101A);

Future<void> openUserProfile(
  BuildContext context, {
  required String userId,
  required String name,
  String? email,
  String? avatarUrl,
  String? role,
  String? roleLabel,
  DateTime? joinedAt,
  bool allowMessage = true,
}) {
  if (userId.isNotEmpty && userId == CurrentUser.id) {
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
  }
  if (userId.isEmpty && name.trim().isEmpty) return Future.value();
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => UserProfileScreen(
        userId: userId,
        name: name,
        email: email,
        avatarUrl: avatarUrl,
        role: role,
        roleLabel: roleLabel,
        joinedAt: joinedAt,
        allowMessage: allowMessage,
      ),
    ),
  );
}

class ProfileTap extends StatelessWidget {
  const ProfileTap({
    super.key,
    required this.userId,
    required this.name,
    required this.child,
    this.email,
    this.avatarUrl,
    this.role,
    this.roleLabel,
    this.joinedAt,
    this.allowMessage = true,
  });

  final String userId;
  final String name;
  final String? email;
  final String? avatarUrl;
  final String? role;
  final String? roleLabel;
  final DateTime? joinedAt;
  final bool allowMessage;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openUserProfile(
        context,
        userId: userId,
        name: name,
        email: email,
        avatarUrl: avatarUrl,
        role: role,
        roleLabel: roleLabel,
        joinedAt: joinedAt,
        allowMessage: allowMessage,
      ),
      child: child,
    );
  }
}

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.name,
    this.email,
    this.avatarUrl,
    this.role,
    this.roleLabel,
    this.joinedAt,
    this.allowMessage = true,
  });

  final String userId;
  final String name;
  final String? email;
  final String? avatarUrl;
  final String? role;
  final String? roleLabel;
  final DateTime? joinedAt;
  final bool allowMessage;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Map<String, dynamic> _extra = {};
  bool _loading = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _loadExtra();
  }

  Map<String, dynamic>? _unwrap(dynamic body) {
    if (body is! Map) return null;
    final data = body['data'];
    if (data is Map) {
      if (data['user'] is Map) return Map<String, dynamic>.from(data['user']);
      return Map<String, dynamic>.from(data);
    }
    if (body['user'] is Map) return Map<String, dynamic>.from(body['user']);
    return Map<String, dynamic>.from(body);
  }

  Future<void> _loadExtra() async {
    if (widget.userId.isEmpty) return;
    setState(() => _loading = true);
    try {
      final r = await ApiClient.instance.dio.get('/api/users/${widget.userId}');
      final user = _unwrap(r.data);
      if (mounted && user != null) setState(() => _extra = user);
    } on DioException {
      return;
    } catch (_) {
      return;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _name {
    final fromApi = (_extra['name'] ?? '').toString().trim();
    return fromApi.isNotEmpty ? fromApi : (widget.name.trim().isEmpty ? 'Unknown' : widget.name.trim());
  }

  String? get _email {
    final fromApi = (_extra['email'] ?? '').toString().trim();
    if (fromApi.isNotEmpty) return fromApi;
    final given = widget.email?.trim() ?? '';
    return given.isEmpty ? null : given;
  }

  String? get _avatar {
    final fromApi = (_extra['avatar'] ?? _extra['avatarUrl'] ?? _extra['image'] ?? _extra['picture'] ?? '').toString().trim();
    if (fromApi.isNotEmpty) return fromApi;
    final given = widget.avatarUrl?.trim() ?? '';
    return given.isEmpty ? null : given;
  }

  DateTime? get _memberSince {
    final raw = _extra['createdAt'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  List<String> get _useCases {
    final raw = _extra['useCases'];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }

  bool get _verified =>
      _extra['isEmailVerified'] == true || _extra['isVerified'] == true || _extra['emailVerified'] == true;

  String _title(String v) {
    final parts = v.replaceAll('_', ' ').toLowerCase().split(' ').where((e) => e.isNotEmpty);
    return parts.map((e) => e[0].toUpperCase() + e.substring(1)).join(' ');
  }

  String _date(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Future<void> _copyEmail() async {
    final email = _email;
    if (email == null) return;
    await Clipboard.setData(ClipboardData(text: email));
    if (mounted) showInfoSnack(context, 'Email copied');
  }

  Future<void> _message() async {
    if (_starting || widget.userId.isEmpty) return;
    setState(() => _starting = true);
    try {
      final id = await ChatRepository.instance.startDm(widget.userId);
      Conversation? conv;
      try {
        conv = await ChatRepository.instance.conversationById(id, CurrentUser.id);
      } catch (_) {}
      conv ??= Conversation(
        id: id,
        directName: _name,
        directEmail: _email,
        directAvatar: _avatar,
        updatedAt: DateTime.now(),
        members: [ChatUser(id: widget.userId, name: _name, email: _email, avatarUrl: _avatar)],
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            conversation: conv!,
            currentUserId: CurrentUser.id,
            currentUserName: CurrentUser.name,
          ),
        ),
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _viewAvatar() {
    final url = _avatar;
    if (url == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ImageViewerScreen(url: url, fileName: '$_name.jpg')),
    );
  }

  Widget _row(IconData icon, String label, String value, {VoidCallback? onTap, Widget? trailing}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primaryLight),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = _email;
    final role = widget.role;
    final roleText = (role == null || role.trim().isEmpty) ? null : _title(role);
    final joined = widget.joinedAt;
    final since = _memberSince;
    final useCases = _useCases;

    final details = <Widget>[
      if (email != null)
        _row(Icons.mail_outline_rounded, 'Email', email,
            onTap: _copyEmail, trailing: const Icon(Icons.copy_rounded, size: 16, color: AppColors.textSecondary)),
      if (roleText != null) _row(Icons.shield_outlined, widget.roleLabel ?? 'Role', roleText),
      if (joined != null) _row(Icons.event_available_outlined, 'Joined', _date(joined)),
      if (since != null) _row(Icons.calendar_today_outlined, 'On Quorum since', _date(since)),
      if (_verified)
        _row(Icons.verified_outlined, 'Status', 'Verified email'),
    ];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text('Profile', style: TextStyle(color: AppColors.textPrimary, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SizedBox(height: 8),
          Center(
            child: GestureDetector(
              onTap: _avatar == null ? null : _viewAvatar,
              child: ChatAvatar(name: _name, imageUrl: _avatar, radius: 52),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _name,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          if (roleText != null) ...[
            const SizedBox(height: 8),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(roleText, style: const TextStyle(color: AppColors.primaryLight, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
          if (widget.allowMessage && widget.userId.isNotEmpty) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _starting ? null : _message,
              icon: _starting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: const Text('Message'),
            ),
          ],
          const SizedBox(height: 20),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (details.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < details.length; i++) ...[
                    if (i > 0) const Divider(height: 1, color: AppColors.surfaceBorder),
                    details[i],
                  ],
                ],
              ),
            ),
          if (useCases.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Interests', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final label in useCases)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
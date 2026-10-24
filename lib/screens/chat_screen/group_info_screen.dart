import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/chat_repository.dart';
import 'package:quorum_app/api/upload_service.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'chat_widgets.dart';
import 'user_picker_screen.dart';

class GroupInfoResult {
  final Conversation? conversation;
  final bool left;
  const GroupInfoResult({this.conversation, this.left = false});
}

class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({
    super.key,
    required this.conversation,
    required this.currentUserId,
    this.onLeaving,
  });

  final Conversation conversation;
  final String currentUserId;
  final ValueChanged<bool>? onLeaving;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  static const Color darkBg = Color(0xFF0F101A);

  final _repo = ChatRepository.instance;
  late Conversation _conv;
  bool _busy = false;
  String get _me => widget.currentUserId;
  bool get _canManage => _conv.adminId == null || _conv.adminId == _me;

  @override
  void initState() {
    super.initState();
    _conv = widget.conversation;
    _reload();
  }

  Future<void> _reload() async {
    try {
      final c = await _repo.conversationById(_conv.id, _me);
      if (!mounted || c == null) return;
      setState(() => _conv = c);
    } catch (_) {}
  }

  Future<bool> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _reload();
      return true;
    } catch (e) {
      if (mounted) {
        final denied = e is ApiException && e.statusCode == 403;
        showErrorSnack(context, denied ? 'Only the group admin can do this' : errorText(e));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title, style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(body, style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action, style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _rename() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _PromptDialog(
        title: 'Group name',
        initial: _conv.groupTitle ?? '',
        maxLength: 100,
        actionLabel: 'Save',
      ),
    );
    if (name == null) return;
    final clean = cleanGroupName(name);
    if (clean.isEmpty || clean == _conv.groupTitle) return;
    await _run(() => _repo.updateGroup(_conv.id, name: clean));
  }

  Future<void> _changeAvatar() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.textPrimary),
              title: const Text('Choose from gallery', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, 'pick'),
            ),
            if (_conv.avatar != null && _conv.avatar!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Remove photo', style: TextStyle(color: Colors.redAccent)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    if (choice == 'remove') {
      await _run(() => _repo.updateGroup(_conv.id, clearAvatar: true));
      return;
    }

    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    await _run(() async {
      final res = await UploadService.instance
          .upload(path: picked.path, fileName: picked.name);
      await _repo.updateGroup(_conv.id, avatar: res.url);
    });
  }

  Future<void> _addMembers() async {
    final picked = await Navigator.of(context).push<List<ChatUser>>(
      MaterialPageRoute(
        builder: (_) => UserPickerScreen(
          currentUserId: _me,
          multi: true,
          title: 'Add members',
          excludeIds: _conv.members.map((m) => m.id).toSet(),
        ),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    await _run(
        () => _repo.addParticipants(_conv.id, picked.map((u) => u.id).toList()));
  }

  Future<void> _remove(ChatUser u) async {
    final ok = await _confirm('Remove member', 'Remove ${u.name} from this group?', 'Remove');
    if (!ok || !mounted) return;
    await _run(() => _repo.removeParticipant(_conv.id, u.id));
  }

  Future<void> _leave() async {
    final ok = await _confirm('Leave group',
        'You will no longer receive messages from this group.', 'Leave');
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    widget.onLeaving?.call(true);
    try {
      await _repo.removeParticipant(_conv.id, _me);
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      widget.onLeaving?.call(false);
      if (mounted) showErrorSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _adminChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text('Admin',
            style: TextStyle(
                color: AppColors.primaryLight,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      );

  Widget _memberTile(ChatUser u) {
    final isMe = u.id == _me;
    final isAdminRow = u.id == _conv.adminId;
    final email = u.email;

    Widget? trailing;
    if (isAdminRow) {
      trailing = _adminChip();
    } else if (_canManage && !isMe) {
      trailing = PopupMenuButton<String>(
        color: AppColors.surface,
        icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
        onSelected: (v) {
          if (v == 'remove') _remove(u);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
              value: 'remove',
              child: Text('Remove', style: TextStyle(color: Colors.redAccent))),
        ],
      );
    }

    return ListTile(
      leading: ChatAvatar(name: u.name, imageUrl: u.avatarUrl, radius: 20),
      title: Text(isMe ? '${u.name} (You)' : u.name,
          style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: (email != null && email.isNotEmpty)
          ? Text(email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))
          : null,
      trailing: trailing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _conv.titleFor(_me);
    final members = _conv.members;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.pop(context, GroupInfoResult(conversation: _conv));
        }
      },
      child: Scaffold(
        backgroundColor: darkBg,
        appBar: AppBar(
          backgroundColor: darkBg,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          title: const Text('Group info', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                const SizedBox(height: 8),
                Center(
                  child: GestureDetector(
                    onTap: _canManage ? _changeAvatar : null,
                    child: Stack(
                      children: [
                        ChatAvatar(
                            name: title,
                            isGroup: true,
                            imageUrl: _conv.avatar,
                            radius: 48),
                        if (_canManage)
                          const Positioned(
                            right: 0,
                            bottom: 0,
                            child: CircleAvatar(
                              radius: 15,
                              backgroundColor: AppColors.primary,
                              child: Icon(Icons.camera_alt, size: 16, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    if (_canManage)
                      IconButton(
                        onPressed: _rename,
                        icon: const Icon(Icons.edit_outlined, color: AppColors.textSecondary, size: 20),
                      ),
                  ],
                ),
                Center(
                  child: Text('${members.length} members', style: const TextStyle(color: AppColors.textSecondary)),
                ),
                const SizedBox(height: 16),
                if (_canManage)
                  ListTile(
                    onTap: _addMembers,
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.person_add_alt_1, color: Colors.white),
                    ),
                    title: const Text('Add members', style: TextStyle(color: AppColors.textPrimary)),
                  ),
                ...members.map(_memberTile),
                const Divider(color: AppColors.surfaceBorder),
                ListTile(
                  onTap: _leave,
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: const Text('Leave group', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black38,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.initial,
    required this.maxLength,
    required this.actionLabel,
  });

  final String title;
  final String initial;
  final int maxLength;
  final String actionLabel;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(widget.title, style: const TextStyle(color: AppColors.textPrimary)),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: widget.maxLength,
        style: const TextStyle(color: AppColors.textPrimary),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
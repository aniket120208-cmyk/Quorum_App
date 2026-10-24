import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quorum_app/models/community_models.dart';
import 'package:quorum_app/screens/chat_screen/attachment_widgets.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.day}/${t.month}/${t.year}';
}

String parseInviteToken(String input) {
  final s = input.trim();
  final uri = Uri.tryParse(s);
  if (uri != null) {
    final segments = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    if (segments.isNotEmpty) return segments.last;
  }
  return s;
}

void showCommunityToast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF334155),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
}

Future<void> copyToClipboard(BuildContext context, String text, {String message = 'Copied'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showCommunityToast(context, message);
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  bool destructive = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary)),
      content: Text(body, style: const TextStyle(color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            action,
            style: TextStyle(color: destructive ? Colors.redAccent : AppColors.primaryLight),
          ),
        ),
      ],
    ),
  );
  return ok == true;
}

InputDecoration communityFieldDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textSecondary),
    filled: true,
    fillColor: const Color(0xFF0F101A),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.surfaceBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.primary),
    ),
  );
}

class CommunityAvatar extends StatelessWidget {
  const CommunityAvatar({super.key, required this.name, this.size = 48});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        color: Color(0xFF7C5CFC),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.45,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    if (role == 'MEMBER') return const SizedBox.shrink();
    final owner = role == 'OWNER';
    final color = owner ? const Color(0xFFF59E0B) : AppColors.primaryLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        roleLabel(role),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class TextPromptDialog extends StatefulWidget {
  const TextPromptDialog({
    super.key,
    required this.title,
    required this.actionLabel,
    this.hint,
    this.initial = '',
    this.maxLines = 1,
  });

  final String title;
  final String actionLabel;
  final String? hint;
  final String initial;
  final int maxLines;

  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
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
        minLines: 1,
        maxLines: widget.maxLines,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: communityFieldDecoration(widget.hint ?? ''),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

class CommunityFormDialog extends StatefulWidget {
  const CommunityFormDialog({
    super.key,
    required this.title,
    required this.actionLabel,
    this.name = '',
    this.description = '',
    this.nameHint = 'Community name',
    this.descriptionHint = 'What is this community about?',
    this.emptyError = 'Give your community a name.',
  });

  final String title;
  final String actionLabel;
  final String name;
  final String description;
  final String nameHint;
  final String descriptionHint;
  final String emptyError;

  @override
  State<CommunityFormDialog> createState() => _CommunityFormDialogState();
}

class _CommunityFormDialogState extends State<CommunityFormDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.name);
  late final TextEditingController _desc = TextEditingController(text: widget.description);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = widget.emptyError);
      return;
    }
    Navigator.pop(context, (name, _desc.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(widget.title, style: const TextStyle(color: AppColors.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: communityFieldDecoration(widget.nameHint),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              minLines: 3,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: communityFieldDecoration(widget.descriptionHint),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}

class ChannelBar extends StatelessWidget {
  const ChannelBar({
    super.key,
    required this.channels,
    required this.selectedId,
    required this.unreadIds,
    required this.onSelect,
    this.onAdd,
    this.onManage,
  });

  final List<CommunityChannel> channels;
  final String? selectedId;
  final Set<String> unreadIds;
  final ValueChanged<CommunityChannel> onSelect;
  final VoidCallback? onAdd;
  final ValueChanged<CommunityChannel>? onManage;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.surfaceBorder)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        children: [
          for (final ch in channels)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onSelect(ch),
                onLongPress: onManage == null ? null : () => onManage!(ch),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selectedId == ch.id ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selectedId == ch.id ? AppColors.primaryLight : AppColors.surfaceBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '# ${ch.name}',
                        style: TextStyle(
                          color: selectedId == ch.id ? Colors.white : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (unreadIds.contains(ch.id) && selectedId != ch.id) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2DD4B0),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (onAdd != null)
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 15, color: AppColors.primaryLight),
                    SizedBox(width: 4),
                    Text(
                      'Channel',
                      style: TextStyle(
                        color: AppColors.primaryLight,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

IconData postFileIcon(String? fileType) {
  switch (fileType) {
    case 'video':
      return Icons.videocam_outlined;
    case 'audio':
      return Icons.audiotrack_outlined;
    case 'image':
      return Icons.image_outlined;
    default:
      return Icons.description_outlined;
  }
}

class PostAttachmentView extends StatelessWidget {
  const PostAttachmentView({super.key, required this.post});

  final CommunityPost post;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(post.fileUrl ?? '');
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showErrorSnack(context, 'Could not open this file');
  }

  @override
  Widget build(BuildContext context) {
    final url = post.fileUrl;
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    if (post.isImage) {
      return GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ImageViewerScreen(url: url)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            url,
            width: double.infinity,
            height: 200,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            },
            errorBuilder: (context, error, stack) => const SizedBox(
              height: 120,
              child: Center(
                child: Icon(Icons.broken_image_outlined, color: AppColors.textSecondary, size: 32),
              ),
            ),
          ),
        ),
      );
    }
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F101A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(postFileIcon(post.fileType), color: AppColors.primaryLight, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                post.attachmentName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
            ),
            const Icon(Icons.open_in_new, size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.canEdit,
    required this.canDelete,
    this.onComments,
    this.onEdit,
    this.onDelete,
    this.saved = false,
    this.onToggleSave,
  });

  final CommunityPost post;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback? onComments;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool saved;
  final VoidCallback? onToggleSave;

  @override
  Widget build(BuildContext context) {
    final count = post.commentCount;
    final showText = post.content.isNotEmpty &&
        !(post.hasAttachment && post.content == post.attachmentName);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ChatAvatar(name: post.authorName, imageUrl: post.authorAvatar, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.authorName.isEmpty ? 'Unknown' : post.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      post.edited ? '${timeAgo(post.createdAt)} · edited' : timeAgo(post.createdAt),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (canEdit || canDelete)
                PopupMenuButton<String>(
                  color: AppColors.surface,
                  icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  onSelected: (v) {
                    if (v == 'edit') onEdit?.call();
                    if (v == 'delete') onDelete?.call();
                  },
                  itemBuilder: (_) => [
                    if (canEdit)
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit', style: TextStyle(color: AppColors.textPrimary)),
                      ),
                    if (canDelete)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (showText)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SelectableText(
                post.content,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.45),
              ),
            ),
          if (post.hasAttachment)
            Padding(
              padding: EdgeInsets.only(top: showText ? 10 : 0, right: 8),
              child: PostAttachmentView(post: post),
            ),
          if (onComments != null || onToggleSave != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (onComments != null)
                  InkWell(
                    onTap: onComments,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.chat_bubble_outline, size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            count == 0 ? 'Comment' : (count == 1 ? '1 comment' : '$count comments'),
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Spacer(),
                if (onToggleSave != null)
                  InkWell(
                    onTap: onToggleSave,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                        size: 20,
                        color: saved ? AppColors.primaryLight : AppColors.textSecondary,
                      ),
                    ),
                  ),
                const SizedBox(width: 2),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class CenteredMessage extends StatelessWidget {
  const CenteredMessage({
    super.key,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.surfaceBorder),
                ),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
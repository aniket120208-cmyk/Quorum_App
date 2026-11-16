import 'package:flutter/material.dart';
import 'package:quorum_app/models/org_feed_models.dart';
import 'package:quorum_app/screens/chat_screen/attachment_widgets.dart' show ImageViewerScreen;
import 'package:quorum_app/screens/chat_screen/file_preview_screen.dart' show openFilePreview;
import 'organization_sheets.dart';
import 'organization_widgets.dart';

const Color feedPurple = Color(0xFF7C5CFC);
const Color feedBody = Color(0xFFD1D5DB);

const List<String> orgFeedQuickEmojis = ['🎉', '👏', '❤️', '🔥', '🚀', '👍', '🙌', '😂', '🙏', '💯'];

Future<String?> pickOrgFeedEmoji(BuildContext context) {
  return showOrgSheet<String>(context, const _EmojiPickerSheet());
}

class _EmojiPickerSheet extends StatelessWidget {
  const _EmojiPickerSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('React', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final e in orgFeedQuickEmojis)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(context, e),
                  child: Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: orgField,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: orgBorder),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class OrgFeedTag extends StatelessWidget {
  const OrgFeedTag({super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }
}

class OrgFeedPostCard extends StatelessWidget {
  const OrgFeedPostCard({
    super.key,
    required this.post,
    required this.myId,
    required this.canManage,
    required this.saved,
    required this.onReact,
    required this.onPickReaction,
    required this.onComments,
    required this.onSave,
    required this.onPin,
    required this.onEdit,
    required this.onDelete,
  });

  final OrgFeedPost post;
  final String myId;
  final bool canManage;
  final bool saved;
  final void Function(String emoji) onReact;
  final VoidCallback onPickReaction;
  final VoidCallback onComments;
  final VoidCallback onSave;
  final VoidCallback onPin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  bool get _isMine => post.authorId == myId;
  bool get _canEdit => _isMine && !post.isSystemGenerated;
  bool get _canDelete => _isMine || canManage;

  @override
  Widget build(BuildContext context) {
    final title = post.title;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: orgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: post.isPinned ? feedPurple.withValues(alpha: 0.45) : orgBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (post.isPinned) const OrgFeedTag(label: 'PINNED', color: orgMuted, icon: Icons.push_pin_rounded),
              OrgFeedTag(label: post.category.label.toUpperCase(), color: post.category.color),
              if (post.targetTeam != null)
                OrgFeedTag(label: post.targetTeam!.name, color: orgTeal, icon: Icons.groups_rounded),
              if (post.targetUser != null)
                OrgFeedTag(label: post.targetUser!.name, color: feedPurple, icon: Icons.person_rounded),
            ],
          ),
          const SizedBox(height: 10),
          _authorRow(),
          if (title != null) ...[
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, height: 1.3),
            ),
          ],
          if (post.content.isNotEmpty) ...[
            SizedBox(height: title != null ? 6 : 10),
            Text(post.content, style: const TextStyle(color: feedBody, fontSize: 14, height: 1.45)),
          ],
          if (post.hasFile) ...[
            const SizedBox(height: 12),
            post.isImage ? _image(context) : _fileTile(context),
          ],
          const SizedBox(height: 12),
          _footer(),
        ],
      ),
    );
  }

  Widget _authorRow() {
    final name = post.author?.name.isNotEmpty == true ? post.author!.name : (post.isSystemGenerated ? 'Quorum' : 'Member');
    return Row(
      children: [
        OrgAvatar(name: name, logo: post.author?.avatar, size: 32, circular: true),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: name,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: '  ·  ${orgFeedTimeAgo(post.createdAt)}${post.isEdited ? ' · edited' : ''}',
                  style: const TextStyle(color: orgMuted, fontSize: 12),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        PopupMenuButton<String>(
          color: orgCard,
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.more_horiz_rounded, color: orgMuted, size: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onSelected: (v) {
            switch (v) {
              case 'save':
                onSave();
              case 'pin':
                onPin();
              case 'edit':
                onEdit();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'save',
              child: Text(saved ? 'Remove from saved' : 'Save post', style: const TextStyle(color: Colors.white)),
            ),
            if (canManage)
              PopupMenuItem(
                value: 'pin',
                child: Text(post.isPinned ? 'Unpin' : 'Pin to top', style: const TextStyle(color: Colors.white)),
              ),
            if (_canEdit)
              const PopupMenuItem(value: 'edit', child: Text('Edit', style: TextStyle(color: Colors.white))),
            if (_canDelete)
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: Color(0xFFEF4444))),
              ),
          ],
        ),
      ],
    );
  }

  Widget _image(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ImageViewerScreen(url: post.fileUrl!, fileName: post.fileName)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340),
          child: Image.network(
            post.fileUrl!,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                height: 180,
                color: orgField,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(color: feedPurple, strokeWidth: 2),
              );
            },
            errorBuilder: (context, error, stack) => Container(
              height: 120,
              color: orgField,
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined, color: orgMuted, size: 32),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileTile(BuildContext context) {
    final name = post.fileName ?? 'Attachment';
    final size = orgFeedFileSize(post.fileSize);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => openFilePreview(context, post.fileUrl!, post.fileName),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: orgField,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: orgBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: feedPurple.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.insert_drive_file_outlined, color: feedPurple, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  if (size.isNotEmpty) Text(size, style: const TextStyle(color: orgMuted, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.open_in_new_rounded, color: orgMuted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final r in post.reactions) _reactionPill(r),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onPickReaction,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: orgField,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: orgBorder),
                  ),
                  child: const Icon(Icons.add_reaction_outlined, color: orgMuted, size: 16),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onComments,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              post.commentCount == 0
                  ? 'Comment'
                  : '${post.commentCount} ${post.commentCount == 1 ? 'comment' : 'comments'}',
              style: const TextStyle(color: orgMuted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          onPressed: onSave,
          icon: Icon(
            saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            color: saved ? feedPurple : orgMuted,
            size: 20,
          ),
        ),
      ],
    );
  }

  Widget _reactionPill(OrgFeedReaction r) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onReact(r.emoji),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: r.reactedByMe ? feedPurple.withValues(alpha: 0.2) : orgField,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: r.reactedByMe ? feedPurple : orgBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(r.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 5),
            Text(
              '${r.count}',
              style: TextStyle(
                color: r.reactedByMe ? Colors.white : orgMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
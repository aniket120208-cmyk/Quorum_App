import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'chat_widgets.dart';
import 'voice_widgets.dart';

const List<String> quickReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏', '🎉', '🔥'];

class ReactionPickerRow extends StatelessWidget {
  const ReactionPickerRow({super.key, required this.onPick, this.selected});

  final ValueChanged<String> onPick;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final emoji in quickReactionEmojis)
            GestureDetector(
              onTap: () => onPick(emoji),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: emoji == selected ? AppColors.primary.withValues(alpha: 0.3) : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 26)),
              ),
            ),
        ],
      ),
    );
  }
}

class ReactionChips extends StatelessWidget {
  const ReactionChips({
    super.key,
    required this.groups,
    required this.myId,
    required this.onTap,
    required this.onLongPress,
  });

  final List<MessageReactionGroup> groups;
  final String myId;
  final ValueChanged<String> onTap;
  final ValueChanged<MessageReactionGroup> onLongPress;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final g in groups)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap(g.emoji);
            },
            onLongPress: () => onLongPress(g),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: g.reactedBy(myId) ? AppColors.primary.withValues(alpha: 0.3) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: g.reactedBy(myId) ? AppColors.primaryLight : AppColors.surfaceBorder,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(g.emoji, style: const TextStyle(fontSize: 13)),
                  if (g.count > 1) ...[
                    const SizedBox(width: 3),
                    Text(
                      '${g.count}',
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> showReactorsSheet(
  BuildContext context,
  List<MessageReactionGroup> groups,
  String myId, {
  String? initialEmoji,
  ValueChanged<String>? onRemoveMine,
}) {
  final total = groups.fold<int>(0, (sum, g) => sum + (g.users.isEmpty ? g.count : g.users.length));
  final initialIndex = initialEmoji == null
      ? 0
      : (groups.indexWhere((g) => g.emoji == initialEmoji) + 1).clamp(0, groups.length);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      var rowsInLongest = total;
      for (final g in groups) {
        if (g.users.length > rowsInLongest) rowsInLongest = g.users.length;
      }
      final maxHeight = MediaQuery.of(ctx).size.height * 0.65;
      final height = (rowsInLongest * 60.0 + 120).clamp(240.0, maxHeight).toDouble();

      Widget rows(List<(ChatUser, String)> entries, bool showEmoji) {
        if (entries.isEmpty) {
          return const Center(
            child: Text('No details available', style: TextStyle(color: AppColors.textSecondary)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          itemCount: entries.length,
          itemBuilder: (_, i) {
            final user = entries[i].$1;
            final emoji = entries[i].$2;
            final mine = user.id == myId;
            return ListTile(
              dense: true,
              onTap: mine && onRemoveMine != null
                  ? () {
                      Navigator.pop(ctx);
                      onRemoveMine(emoji);
                    }
                  : null,
              leading: ChatAvatar(name: user.name, imageUrl: user.avatarUrl, radius: 18),
              title: Text(
                mine ? 'You' : (user.name.isEmpty ? 'Unknown' : user.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: mine && onRemoveMine != null
                  ? const Text('Tap to remove', style: TextStyle(color: AppColors.textSecondary, fontSize: 11))
                  : null,
              trailing: Text(emoji, style: const TextStyle(fontSize: 22)),
            );
          },
        );
      }

      final everyone = <(ChatUser, String)>[
        for (final g in groups)
          for (final u in g.users) (u, g.emoji),
      ];

      return SafeArea(
        child: DefaultTabController(
          length: groups.length + 1,
          initialIndex: initialIndex,
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: AppColors.primary,
                  labelColor: AppColors.textPrimary,
                  unselectedLabelColor: AppColors.textSecondary,
                  dividerColor: AppColors.surfaceBorder,
                  labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  tabs: [
                    Tab(text: 'All $total'),
                    for (final g in groups) Tab(text: '${g.emoji} ${g.users.isEmpty ? g.count : g.users.length}'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      rows(everyone, true),
                      for (final g in groups) rows([for (final u in g.users) (u, g.emoji)], false),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class ForwardedLabel extends StatelessWidget {
  const ForwardedLabel({super.key, required this.isMe});

  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final color = isMe ? Colors.white70 : AppColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.shortcut_rounded, size: 13, color: color),
        const SizedBox(width: 4),
        Text('Forwarded', style: TextStyle(color: color, fontSize: 11, fontStyle: FontStyle.italic)),
      ],
    );
  }
}

class QuotedReplyBanner extends StatelessWidget {
  const QuotedReplyBanner({
    super.key,
    required this.reply,
    required this.isMe,
    required this.myId,
    this.onTap,
  });

  final QuotedReply reply;
  final bool isMe;
  final String myId;
  final VoidCallback? onTap;

  Widget _snippet(Color color) {
    if (reply.isDeleted) {
      return Text(
        'This message was deleted',
        style: TextStyle(color: color, fontSize: 12, fontStyle: FontStyle.italic),
      );
    }
    if (reply.isVoice) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '${formatVoiceDuration(reply.audioDuration ?? 0)} Voice message',
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      );
    }
    if (reply.content.isNotEmpty) {
      return Text(
        reply.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontSize: 12),
      );
    }
    final label = reply.isImage ? 'Photo' : (reply.fileName ?? 'File');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(reply.isImage ? Icons.photo_outlined : Icons.insert_drive_file_outlined, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 12)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isMe ? Colors.white70 : AppColors.textSecondary;
    final name = reply.senderId == myId ? 'You' : (reply.senderName.isEmpty ? 'Message' : reply.senderName);
    final showThumb = !reply.isDeleted && reply.isImage && reply.fileUrl != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: isMe ? 0.2 : 0.25),
          borderRadius: BorderRadius.circular(10),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: isMe ? Colors.white : AppColors.primaryLight,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isMe ? Colors.white : AppColors.primaryLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _snippet(textColor),
                    ],
                  ),
                ),
              ),
              if (showThumb)
                ClipRRect(
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
                  child: Image.network(
                    reply.fileUrl!,
                    width: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => const SizedBox(width: 44),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReplyComposerPreview extends StatelessWidget {
  const ReplyComposerPreview({super.key, required this.message, required this.myId, required this.onClose});

  final ChatMessage message;
  final String myId;
  final VoidCallback onClose;

  QuotedReply get _asReply => QuotedReply(
        id: message.id,
        content: message.text,
        fileUrl: message.fileUrl,
        fileType: message.fileType,
        fileName: message.fileName,
        audioDuration: message.audioDuration,
        isDeleted: message.isDeleted,
        senderId: message.senderId,
        senderName: message.senderName,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Color(0xFF0F101A)),
                child: QuotedReplyBanner(reply: _asReply, isMe: false, myId: myId),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cancel reply',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
          ),
        ],
      ),
    );
  }
}

class SwipeToReply extends StatefulWidget {
  const SwipeToReply({super.key, required this.child, required this.onReply, this.enabled = true});

  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> {
  static const double _trigger = 56;
  double _dx = 0;
  bool _fired = false;

  void _onUpdate(DragUpdateDetails d) {
    if (!widget.enabled) return;
    setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, 80.0));
    if (!_fired && _dx >= _trigger) {
      _fired = true;
      HapticFeedback.lightImpact();
    }
  }

  void _onEnd(DragEndDetails _) {
    if (_fired) widget.onReply();
    setState(() {
      _dx = 0;
      _fired = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final progress = (_dx / _trigger).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: () => setState(() {
        _dx = 0;
        _fired = false;
      }),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned(
            left: 4,
            child: Opacity(
              opacity: progress,
              child: Transform.scale(
                scale: 0.6 + 0.4 * progress,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceBorder.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.reply_rounded, size: 16, color: AppColors.textPrimary),
                ),
              ),
            ),
          ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'chat_widgets.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF6366F1);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color surface = Color(0xFF1E293B);
  static const Color surfaceBorder = Color(0xFF334155);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
}

enum ChatFilter { all, direct, groups, unread }

extension on ChatFilter {
  String get label {
    switch (this) {
      case ChatFilter.all:
        return 'All';
      case ChatFilter.direct:
        return 'DMs';
      case ChatFilter.groups:
        return 'Groups';
      case ChatFilter.unread:
        return 'Unread';
    }
  }

  String get emptyText {
    switch (this) {
      case ChatFilter.all:
        return 'No conversations yet.\nStart one with your contacts.';
      case ChatFilter.direct:
        return 'No direct messages yet.';
      case ChatFilter.groups:
        return 'No group chats yet.';
      case ChatFilter.unread:
        return 'You are all caught up.\nNo unread chats.';
    }
  }

  IconData get emptyIcon {
    switch (this) {
      case ChatFilter.all:
        return Icons.chat_bubble_outline;
      case ChatFilter.direct:
        return Icons.person_outline;
      case ChatFilter.groups:
        return Icons.groups_outlined;
      case ChatFilter.unread:
        return Icons.mark_chat_read_outlined;
    }
  }

  bool matches(Conversation c) {
    switch (this) {
      case ChatFilter.all:
        return true;
      case ChatFilter.direct:
        return !c.isGroup;
      case ChatFilter.groups:
        return c.isGroup;
      case ChatFilter.unread:
        return c.unreadCount > 0;
    }
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final String _currentUserId = 'user_1';
  List<Conversation> _conversations = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      setState(() {
        _isLoading = false;
        _conversations = [
          Conversation(
            id: 'c1',
            directName: 'Alex Rivera',
            updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
            unreadCount: 2,
            lastMessage: ChatMessage(
              id: 'm1',
              senderId: 'user_2',
              senderName: 'Alex Rivera',
              previewText: 'Hey, are the designs ready for review?',
              createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
            ),
          ),
        ];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChatListView(
      conversations: _conversations,
      currentUserId: _currentUserId,
      isLoading: _isLoading,
      onRefresh: _loadConversations,
      onConversationTap: (conversation) {},
      onNewChatTap: () {},
      onNewGroupTap: () {},
    );
  }
}

class ChatListView extends StatefulWidget {
  const ChatListView({
    super.key,
    required this.conversations,
    required this.currentUserId,
    required this.onConversationTap,
    required this.onNewChatTap,
    required this.onNewGroupTap,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
    this.onRefresh,
  });

  final List<Conversation> conversations;
  final String currentUserId;
  final ValueChanged<Conversation> onConversationTap;
  final VoidCallback onNewChatTap;
  final VoidCallback onNewGroupTap;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  ChatFilter _filter = ChatFilter.all;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F101A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F101A),
        elevation: 0,
        title: const Text(
          'Chat',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'New group',
            icon: const Icon(Icons.group_add_outlined, color: AppColors.textPrimary),
            onPressed: widget.onNewGroupTap,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textPrimary,
        tooltip: 'New chat',
        onPressed: widget.onNewChatTap,
        child: const Icon(Icons.edit_outlined),
      ),
      body: Builder(
        builder: (context) {
          if (widget.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (widget.errorMessage != null) {
            return MessagePlaceholder(
              icon: Icons.cloud_off,
              text: widget.errorMessage!,
              actionLabel: 'Retry',
              onAction: widget.onRetry ?? () {},
            );
          }

          if (widget.conversations.isEmpty) {
            return MessagePlaceholder(
              icon: Icons.chat_bubble_outline,
              text: ChatFilter.all.emptyText,
              actionLabel: 'New chat',
              onAction: widget.onNewChatTap,
            );
          }

          final unreadChats = widget.conversations.where((c) => c.unreadCount > 0).length;
          final visible = widget.conversations.where(_filter.matches).toList(growable: false);

          return Column(
            children: [
              FilterBar(
                selected: _filter,
                unreadChats: unreadChats,
                onSelected: (f) => setState(() => _filter = f),
              ),
              Expanded(
                child: visible.isEmpty
                    ? MessagePlaceholder(
                        icon: _filter.emptyIcon,
                        text: _filter.emptyText,
                        actionLabel: 'Show all chats',
                        onAction: () => setState(() => _filter = ChatFilter.all),
                      )
                    : RefreshIndicator(
                        color: AppColors.primary,
                        backgroundColor: AppColors.surface,
                        onRefresh: widget.onRefresh ?? () async {},
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            indent: 76,
                            color: AppColors.surfaceBorder,
                          ),
                          itemBuilder: (context, i) {
                            final conversation = visible[i];
                            return ConversationTile(
                              conversation: conversation,
                              currentUserId: widget.currentUserId,
                              onTap: () => widget.onConversationTap(conversation),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.selected,
    required this.unreadChats,
    required this.onSelected,
  });

  final ChatFilter selected;
  final int unreadChats;
  final ValueChanged<ChatFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: ChatFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = ChatFilter.values[i];
          final isSelected = f == selected;
          final showCount = f == ChatFilter.unread && unreadChats > 0;

          return GestureDetector(
            onTap: () => onSelected(f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.surfaceBorder,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    f.label,
                    style: TextStyle(
                      color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  if (showCount) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white.withValues(alpha: 0.25) : AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unreadChats > 99 ? '99+' : '$unreadChats',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.currentUserId,
    required this.onTap,
  });

  final Conversation conversation;
  final String currentUserId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = conversation.titleFor(currentUserId);
    final last = conversation.lastMessage;
    final unread = conversation.unreadCount;

    String preview = 'No messages yet';
    if (last != null) {
      final mine = last.senderId == currentUserId;
      final prefix = mine
          ? 'You: '
          : (conversation.isGroup && last.senderName.isNotEmpty
              ? '${last.senderName}: '
              : '');
      preview = '$prefix${last.previewText}';
    }

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ChatAvatar(
        name: title,
        isGroup: conversation.isGroup,
        imageUrl: conversation.isGroup ? conversation.avatar : null,
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: unread > 0 ? AppColors.textPrimary : AppColors.textSecondary,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatListTime(last?.createdAt ?? conversation.updatedAt),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          if (unread > 0) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class MessagePlaceholder extends StatelessWidget {
  const MessagePlaceholder({
    super.key,
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

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
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.surfaceBorder),
              ),
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
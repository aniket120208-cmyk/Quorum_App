import 'package:flutter/material.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'chat_action_sheets.dart';
import 'chat_room_screen.dart';
import 'chat_search_widgets.dart';
import 'chat_widgets.dart';
import 'dart:async';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/auth_service.dart';
import 'package:quorum_app/api/chat_actions.dart';
import 'package:quorum_app/api/chat_repository.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/socket_service.dart';
import 'user_picker_screen.dart';

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
  final _repo = ChatRepository.instance;
  final _socket = SocketService.instance;

  String _currentUserId = '';
  String _currentUserName = 'You';
  List<Conversation> _conversations = [];
  bool _isLoading = true;
  String? _error;
  String? _openConversationId;
  Timer? _refreshDebounce;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (!CurrentUser.isLoaded) {
        CurrentUser.setFromProfile(await AuthService.instance.getUserProfile());
      }
      _currentUserId = CurrentUser.id;
      _currentUserName = CurrentUser.name;

      await _socket.ensureConnected();
      _socket.on('conversation:update', _onConversationUpdate);
      _socket.on('message:new', _onNewMessage);
      _socket.on('conversation:removed', _onRemoved);
      _socket.on('conversation:muted', _onMuted);
      _socket.on('conversation:unmuted', _onUnmuted);
      _socket.on('conversation:blocked', _onBlocked);
      _socket.on('conversation:unblocked', _onUnblocked);
      _socket.on('conversation:cleared', _onCleared);
      _socket.on('conversation:deleted', _onRemoved);
      _socket.on('group:profile_picture_updated', _onGroupPicture);
      _socket.on('group:profile_picture_deleted', _onGroupPicture);
      _socket.on('connect', _onSocketConnect);

      await _loadConversations();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = errorText(e);
      });
    }
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _socket.off('conversation:update', _onConversationUpdate);
    _socket.off('message:new', _onNewMessage);
    _socket.off('conversation:removed', _onRemoved);
    _socket.off('conversation:muted', _onMuted);
    _socket.off('conversation:unmuted', _onUnmuted);
    _socket.off('conversation:blocked', _onBlocked);
    _socket.off('conversation:unblocked', _onUnblocked);
    _socket.off('conversation:cleared', _onCleared);
    _socket.off('conversation:deleted', _onRemoved);
    _socket.off('group:profile_picture_updated', _onGroupPicture);
    _socket.off('group:profile_picture_deleted', _onGroupPicture);
    _socket.off('connect', _onSocketConnect);
    super.dispose();
  }

  Future<void> _loadConversations({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final list = await _repo.conversations(_currentUserId);
      DateTime stamp(Conversation c) => c.lastMessage?.createdAt ?? c.updatedAt;
      list.sort((a, b) => stamp(b).compareTo(stamp(a)));
      if (!mounted) return;
      setState(() {
        _conversations = list;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (!silent) _error = errorText(e);
      });
    }
  }

  void _refreshSoon() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 300),
        () => _loadConversations(silent: true));
  }

  void _onConversationUpdate(dynamic _) => _refreshSoon();
  void _onSocketConnect(dynamic _) => _refreshSoon();

  void _onNewMessage(dynamic data) {
    final j = asMap(data);
    if (j == null || !mounted) return;
    final convId = (j['conversationId'] ?? '').toString();
    if (TeamConversations.ids.contains(convId)) return;
    final i = _conversations.indexWhere((c) => c.id == convId);
    if (i == -1) {
      _refreshSoon();
      return;
    }
    final msg = ChatMessage.fromJson(j);
    final c = _conversations[i];
    final countsAsUnread =
        msg.senderId != _currentUserId && _openConversationId != convId;
    setState(() {
      _conversations.removeAt(i);
      _conversations.insert(
        0,
        c.copyWith(
          lastMessage: msg,
          updatedAt: msg.createdAt,
          unreadCount: countsAsUnread ? c.unreadCount + 1 : c.unreadCount,
        ),
      );
    });
  }

  void _onGroupPicture(dynamic data) {
    final j = asMap(data);
    if (j == null || !mounted) return;
    final id = (j['conversationId'] ?? j['groupId'] ?? '').toString();
    final i = _conversations.indexWhere((c) => c.id == id);
    if (i == -1) return;
    final url = j['avatarUrl']?.toString();
    final cleared = url == null || url.isEmpty;
    setState(() {
      _conversations[i] = _conversations[i].copyWith(avatar: cleared ? null : url, clearAvatar: cleared);
    });
  }

  void _onRemoved(dynamic data) {
    final j = asMap(data);
    if (j == null || !mounted) return;
    final id = (j['conversationId'] ?? '').toString();
    setState(() => _conversations.removeWhere((c) => c.id == id));
  }

  void _patch(dynamic data, Conversation Function(Conversation c, Map<String, dynamic> j) change) {
    final j = asMap(data);
    if (j == null || !mounted) return;
    final id = (j['conversationId'] ?? j['id'] ?? '').toString();
    final i = _conversations.indexWhere((c) => c.id == id);
    if (i == -1) return;
    setState(() => _conversations[i] = change(_conversations[i], j));
  }

  void _onMuted(dynamic data) => _patch(
        data,
        (c, j) => c.copyWith(
          isMuted: true,
          mutedUntil: DateTime.tryParse((j['mutedUntil'] ?? '').toString())?.toLocal(),
        ),
      );

  void _onUnmuted(dynamic data) => _patch(data, (c, _) => c.copyWith(isMuted: false));
  void _onBlocked(dynamic data) => _patch(data, (c, _) => c.copyWith(isBlocked: true));
  void _onUnblocked(dynamic data) => _patch(data, (c, _) => c.copyWith(isBlocked: false));
  void _onCleared(dynamic data) =>
      _patch(data, (c, _) => c.copyWith(clearLastMessage: true, unreadCount: 0));

  Future<void> _showConversationActions(Conversation conversation) async {
    final title = conversation.titleFor(_currentUserId);
    final action = await showChatActionsSheet(context, conversation, title);
    if (action == null || !mounted) return;
    final actions = ChatActions.instance;
    final id = conversation.id;
    try {
      switch (action) {
        case ChatMenuAction.mute:
          final seconds = await pickMuteDuration(context);
          if (seconds == null || !mounted) return;
          final until = await actions.mute(id, durationSeconds: seconds);
          _patch({'conversationId': id}, (c, _) => c.copyWith(isMuted: true, mutedUntil: until));
          if (mounted) showInfoSnack(context, 'Notifications muted');
        case ChatMenuAction.unmute:
          await actions.unmute(id);
          _patch({'conversationId': id}, (c, _) => c.copyWith(isMuted: false));
          if (mounted) showInfoSnack(context, 'Notifications turned on');
        case ChatMenuAction.clear:
          final ok = await confirmChatAction(
            context,
            title: 'Clear chat?',
            body: 'All messages will be removed from your view. Other people keep their copy.',
            action: 'Clear',
          );
          if (!ok || !mounted) return;
          await actions.clear(id);
          _patch({'conversationId': id}, (c, _) => c.copyWith(clearLastMessage: true, unreadCount: 0));
          if (mounted) showInfoSnack(context, 'Chat cleared');
        case ChatMenuAction.block:
          final ok = await confirmChatAction(
            context,
            title: 'Block $title?',
            body: 'Neither of you will be able to send messages in this chat until you unblock.',
            action: 'Block',
          );
          if (!ok || !mounted) return;
          await actions.block(id);
          _patch({'conversationId': id}, (c, _) => c.copyWith(isBlocked: true));
          if (mounted) showInfoSnack(context, 'Chat blocked');
        case ChatMenuAction.unblock:
          await actions.unblock(id);
          _patch({'conversationId': id}, (c, _) => c.copyWith(isBlocked: false));
          if (mounted) showInfoSnack(context, 'Chat unblocked');
        case ChatMenuAction.delete:
          final ok = await confirmChatAction(
            context,
            title: 'Delete chat?',
            body: 'This removes the conversation and its history from your inbox.',
            action: 'Delete',
          );
          if (!ok || !mounted) return;
          await actions.deleteConversation(id);
          if (mounted) setState(() => _conversations.removeWhere((c) => c.id == id));
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _openChatRoom(Conversation conversation, {String? messageId, String? searchQuery}) async {
    _openConversationId = conversation.id;
    final i = _conversations.indexWhere((c) => c.id == conversation.id);
    if (i != -1 && _conversations[i].unreadCount > 0) {
      setState(() => _conversations[i] = _conversations[i].copyWith(unreadCount: 0));
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          conversation: conversation,
          currentUserId: _currentUserId,
          currentUserName: _currentUserName,
          initialMessageId: messageId,
          initialSearchQuery: searchQuery,
        ),
      ),
    );
    _openConversationId = null;
    if (mounted) _loadConversations(silent: true);
  }

  Future<void> _newChat() async {
    final picked = await Navigator.of(context).push<List<ChatUser>>(
      MaterialPageRoute(
        builder: (_) => UserPickerScreen(currentUserId: _currentUserId),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final user = picked.first;
    try {
      final id = await _repo.startDm(user.id);
      final existing = _conversations.where((c) => c.id == id);
      final conv = existing.isNotEmpty
          ? existing.first
          : Conversation(
              id: id,
              directName: user.name,
              directEmail: user.email,
              directAvatar: user.avatarUrl,
              updatedAt: DateTime.now(),
              members: [user],
            );
      if (!mounted) return;
      await _openChatRoom(conv);
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _newGroup() async {
    final picked = await Navigator.of(context).push<List<ChatUser>>(
      MaterialPageRoute(
        builder: (_) =>
            UserPickerScreen(currentUserId: _currentUserId, multi: true),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    final asked = await _askGroupName();
    final name = cleanGroupName(asked);
    if (name.isEmpty || !mounted) return;

    try {
      final id = await _repo.createGroup(
        name: name,
        participantIds: picked.map((u) => u.id).toList(),
      );
      Conversation? real;
      try {
        real = await _repo.conversationById(id, _currentUserId);
      } catch (_) {}
      final conv = real ??
          Conversation(
            id: id,
            isGroup: true,
            groupTitle: name,
            adminId: _currentUserId,
            updatedAt: DateTime.now(),
            members: [
              ChatUser(id: _currentUserId, name: _currentUserName),
              ...picked,
            ],
          );
      if (!mounted) return;
      await _openChatRoom(conv);
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  Future<String?> _askGroupName() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Group name',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 100,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'e.g. Project Engineering'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChatListView(
      conversations: _conversations,
      currentUserId: _currentUserId,
      isLoading: _isLoading,
      errorMessage: _error,
      onRetry: () {
        _init();
      },
      onRefresh: () => _loadConversations(silent: true),
      onConversationTap: _openChatRoom,
      onConversationLongPress: _showConversationActions,
      onMessageTap: (c, m) => _openChatRoom(c, messageId: m.id),
      onOpenInChat: (c, q) => _openChatRoom(c, searchQuery: q),
      onNewChatTap: _newChat,
      onNewGroupTap: _newGroup,
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
    this.onConversationLongPress,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
    this.onRefresh,
    this.onMessageTap,
    this.onOpenInChat,
  });

  final List<Conversation> conversations;
  final String currentUserId;
  final ValueChanged<Conversation> onConversationTap;
  final ValueChanged<Conversation>? onConversationLongPress;
  final void Function(Conversation conversation, ChatMessage message)? onMessageTap;
  final void Function(Conversation conversation, String query)? onOpenInChat;
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
  bool _searching = false;
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openSearch() => setState(() => _searching = true);

  void _closeSearch() {
    _searchFocus.unfocus();
    _search.clear();
    setState(() => _searching = false);
  }

  PreferredSizeWidget _searchBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0F101A),
      elevation: 0,
      titleSpacing: 0,
      leading: IconButton(
        tooltip: 'Close search',
        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
        onPressed: _closeSearch,
      ),
      title: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: TextField(
          controller: _search,
          focusNode: _searchFocus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          cursorColor: AppColors.primaryLight,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search chats and messages',
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                    onPressed: () {
                      _search.clear();
                      setState(() {});
                    },
                  ),
            filled: true,
            fillColor: const Color(0xFF1E293B),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
  }

  Widget _searchBody() {
    return ChatSearchView(
      query: _search.text,
      conversations: widget.conversations,
      currentUserId: widget.currentUserId,
      onConversationTap: (c) {
        _searchFocus.unfocus();
        widget.onConversationTap(c);
      },
      onMessageTap: (c, m) {
        _searchFocus.unfocus();
        final open = widget.onMessageTap;
        if (open != null) {
          open(c, m);
        } else {
          widget.onConversationTap(c);
        }
      },
      onOpenInChat: (c, q) {
        _searchFocus.unfocus();
        final open = widget.onOpenInChat;
        if (open != null) {
          open(c, q);
        } else {
          widget.onConversationTap(c);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _searching) _closeSearch();
      },
      child: _scaffold(),
    );
  }

  Widget _scaffold() {
    final media = MediaQuery.of(context);
    final fabLift = (media.padding.bottom - 20 - media.viewPadding.bottom)
        .clamp(0.0, double.infinity);
    return Scaffold(
      backgroundColor: const Color(0xFF0F101A),
      appBar: _searching ? _searchBar() : null,
      floatingActionButton: _searching
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: fabLift),
              child: FloatingActionButton(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textPrimary,
                tooltip: 'New chat',
                onPressed: widget.onNewChatTap,
                child: const Icon(Icons.edit_outlined),
              ),
            ),
      body: _searching
          ? _searchBody()
          : SafeArea(
              bottom: false,
              child: NestedScrollView(
                floatHeaderSlivers: true,
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  SliverAppBar(
                    primary: false,
                    floating: true,
                    snap: true,
                    backgroundColor: const Color(0xFF0F101A),
                    elevation: 0,
                    title: const Text(
                      'Chat',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    actions: [
                      IconButton(
                        tooltip: 'Search',
                        icon: const Icon(Icons.search_rounded, color: AppColors.textPrimary),
                        onPressed: _openSearch,
                      ),
                      IconButton(
                        tooltip: 'New group',
                        icon: const Icon(Icons.group_add_outlined, color: AppColors.textPrimary),
                        onPressed: widget.onNewGroupTap,
                      ),
                    ],
                  ),
                ],
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
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: FilterBar(
                            selected: _filter,
                            unreadChats: unreadChats,
                            onSelected: (f) => setState(() => _filter = f),
                          ),
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
                                    padding: EdgeInsets.only(
                                      bottom: 88 + MediaQuery.of(context).padding.bottom - 20,
                                    ),
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
                                        onLongPress: widget.onConversationLongPress == null
                                            ? null
                                            : () => widget.onConversationLongPress!(conversation),
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
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
    this.onLongPress,
  });

  final Conversation conversation;
  final String currentUserId;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

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

    final muted = conversation.muted;
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ChatAvatar(
        name: title,
        isGroup: conversation.isGroup,
        imageUrl: conversation.isGroup ? conversation.avatar : conversation.directAvatar,
        userId: conversation.directUserIdFor(currentUserId),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (conversation.isBlocked && !conversation.isGroup)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.block_rounded, size: 14, color: AppColors.textSecondary),
            ),
        ],
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
          if (unread > 0 || muted) ...[
            const SizedBox(height: 6),
            if (unread == 0)
              const Icon(Icons.notifications_off_outlined, size: 16, color: AppColors.textSecondary)
            else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: muted ? AppColors.textMuted : AppColors.primary,
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
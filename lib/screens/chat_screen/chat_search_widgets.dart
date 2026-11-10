import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/chat_repository.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';

const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String searchTime(DateTime t) {
  final now = DateTime.now();
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return '$hh:$mm';
  if (diff == 1) return 'Yesterday, $hh:$mm';
  final base = '${t.day} ${_months[t.month - 1]}';
  return t.year == now.year ? base : '$base ${t.year}';
}

String searchSnippet(String text, String query, {int lead = 24}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return flat;
  final lower = flat.toLowerCase();
  if (lower.length != flat.length) return flat;
  final i = lower.indexOf(q);
  if (i <= lead) return flat;
  return '…${flat.substring(i - lead)}';
}

class HighlightedText extends StatelessWidget {
  const HighlightedText({
    super.key,
    required this.text,
    required this.query,
    required this.style,
    this.maxLines = 2,
    this.windowed = true,
  });

  final String text;
  final String query;
  final TextStyle style;
  final int maxLines;
  final bool windowed;

  @override
  Widget build(BuildContext context) {
    final snippet = windowed ? searchSnippet(text, query) : text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final q = query.trim().toLowerCase();
    final lower = snippet.toLowerCase();
    if (q.isEmpty || lower.length != snippet.length || !lower.contains(q)) {
      return Text(snippet, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
    }
    final spans = <TextSpan>[];
    var from = 0;
    while (true) {
      final i = lower.indexOf(q, from);
      if (i < 0) break;
      if (i > from) spans.add(TextSpan(text: snippet.substring(from, i)));
      spans.add(
        TextSpan(
          text: snippet.substring(i, i + q.length),
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            backgroundColor: AppColors.primary.withValues(alpha: 0.4),
          ),
        ),
      );
      from = i + q.length;
    }
    if (from < snippet.length) spans.add(TextSpan(text: snippet.substring(from)));
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class MessageHitTile extends StatelessWidget {
  const MessageHitTile({
    super.key,
    required this.message,
    required this.query,
    required this.currentUserId,
    required this.onTap,
  });

  final ChatMessage message;
  final String query;
  final String currentUserId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sender = message.senderId == currentUserId
        ? 'You'
        : (message.senderName.isEmpty ? 'Unknown' : message.senderName);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    sender,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  searchTime(message.createdAt),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 4),
            HighlightedText(
              text: message.previewText,
              query: query,
              maxLines: 3,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14.5, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPlaceholder extends StatelessWidget {
  const _SearchPlaceholder({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14.5),
            ),
          ],
        ),
      ),
    );
  }
}

class MessageSearchController extends ChangeNotifier {
  MessageSearchController({required this.conversationId, required this.localMessages});

  final String conversationId;
  final List<ChatMessage> Function() localMessages;
  final ChatRepository _repo = ChatRepository.instance;

  String query = '';
  List<ChatMessage> results = const [];
  String? cursor;
  bool hasMore = false;
  bool loading = false;
  bool loadingMore = false;
  bool localOnly = false;
  Timer? _debounce;
  int _token = 0;
  bool _disposed = false;

  void _touch() {
    if (!_disposed) notifyListeners();
  }

  void setQuery(String value, {bool immediate = false}) {
    query = value;
    final trimmed = value.trim();
    _debounce?.cancel();
    _token++;
    if (trimmed.isEmpty) {
      results = const [];
      cursor = null;
      hasMore = false;
      loading = false;
      loadingMore = false;
      localOnly = false;
      _touch();
      return;
    }
    loading = true;
    _touch();
    final token = _token;
    _debounce = Timer(immediate ? Duration.zero : const Duration(milliseconds: 350), () => _run(token, trimmed));
  }

  Future<void> _run(int token, String q) async {
    try {
      final page = await _repo.searchMessages(conversationId, q, limit: 30);
      if (token != _token || _disposed) return;
      results = page.items;
      cursor = page.cursor;
      hasMore = page.hasMore;
      localOnly = false;
    } catch (_) {
      if (token != _token || _disposed) return;
      final lower = q.toLowerCase();
      results = localMessages()
          .where((m) => !m.isDeleted && m.previewText.toLowerCase().contains(lower))
          .toList();
      cursor = null;
      hasMore = false;
      localOnly = true;
    }
    loading = false;
    _touch();
  }

  Future<void> loadMore() async {
    final next = cursor;
    if (!hasMore || next == null || loading || loadingMore || localOnly) return;
    final token = _token;
    final q = query.trim();
    loadingMore = true;
    _touch();
    try {
      final page = await _repo.searchMessages(conversationId, q, cursor: next, limit: 30);
      if (token != _token || _disposed) return;
      final seen = results.map((m) => m.id).toSet();
      results = [...results, ...page.items.where((m) => !seen.contains(m.id))];
      cursor = page.cursor;
      hasMore = page.hasMore;
    } catch (e) {
      if (token != _token || _disposed) return;
      hasMore = false;
    }
    loadingMore = false;
    _touch();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}

class MessageSearchResults extends StatefulWidget {
  const MessageSearchResults({
    super.key,
    required this.controller,
    required this.currentUserId,
    required this.onTap,
  });

  final MessageSearchController controller;
  final String currentUserId;
  final ValueChanged<ChatMessage> onTap;

  @override
  State<MessageSearchResults> createState() => _MessageSearchResultsState();
}

class _MessageSearchResultsState extends State<MessageSearchResults> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.pixels > _scroll.position.maxScrollExtent - 240) {
        widget.controller.loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final q = c.query.trim();
        if (q.isEmpty) {
          return const _SearchPlaceholder(icon: Icons.search_rounded, text: 'Search messages in this chat');
        }
        if (c.loading && c.results.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (c.results.isEmpty) {
          return _SearchPlaceholder(
            icon: Icons.search_off_rounded,
            text: c.localOnly
                ? 'No matches in the messages loaded on this device.'
                : 'No messages found for “$q”',
          );
        }
        final count = c.results.length;
        return Column(
          children: [
            if (c.loading)
              const LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.primary,
                backgroundColor: Colors.transparent,
              ),
            Expanded(
              child: ListView.separated(
                controller: _scroll,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: count + 1 + (c.loadingMore ? 1 : 0),
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, color: AppColors.surfaceBorder),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text(
                        c.localOnly
                            ? 'Search is unavailable. Showing $count match${count == 1 ? '' : 'es'} from loaded messages.'
                            : '$count${c.hasMore ? '+' : ''} result${count == 1 && !c.hasMore ? '' : 's'}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }
                  if (i > count) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        ),
                      ),
                    );
                  }
                  final message = c.results[i - 1];
                  return MessageHitTile(
                    message: message,
                    query: q,
                    currentUserId: widget.currentUserId,
                    onTap: () => widget.onTap(message),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ConversationHits {
  const _ConversationHits(this.conversation, this.messages, this.hasMore);

  final Conversation conversation;
  final List<ChatMessage> messages;
  final bool hasMore;
}

class ChatSearchView extends StatefulWidget {
  const ChatSearchView({
    super.key,
    required this.query,
    required this.conversations,
    required this.currentUserId,
    required this.onConversationTap,
    required this.onMessageTap,
    required this.onOpenInChat,
  });

  final String query;
  final List<Conversation> conversations;
  final String currentUserId;
  final ValueChanged<Conversation> onConversationTap;
  final void Function(Conversation conversation, ChatMessage message) onMessageTap;
  final void Function(Conversation conversation, String query) onOpenInChat;

  @override
  State<ChatSearchView> createState() => _ChatSearchViewState();
}

class _ChatSearchViewState extends State<ChatSearchView> {
  static const int _maxChats = 60;
  static const int _workers = 6;
  static const int _perChat = 3;
  final ChatRepository _repo = ChatRepository.instance;
  Timer? _debounce;
  int _token = 0;
  List<_ConversationHits> _hits = [];
  bool _searching = false;
  bool _allFailed = false;
  String get _q => widget.query.trim();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(ChatSearchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) _schedule();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _token++;
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _token++;
    final token = _token;
    _hits = [];
    _allFailed = false;
    if (_q.length < 2) {
      _searching = false;
      return;
    }
    _searching = true;
    final q = _q;
    _debounce = Timer(const Duration(milliseconds: 400), () => _run(token, q));
  }

  Future<void> _run(int token, String q) async {
    final targets = widget.conversations.take(_maxChats).toList();
    if (targets.isEmpty) {
      if (mounted && token == _token) setState(() => _searching = false);
      return;
    }
    final order = {for (var i = 0; i < targets.length; i++) targets[i].id: i};
    final queue = List<Conversation>.of(targets);
    var failed = 0;

    Future<void> worker() async {
      while (queue.isNotEmpty && token == _token && mounted) {
        final conversation = queue.removeAt(0);
        try {
          final page = await _repo.searchMessages(conversation.id, q, limit: 6);
          if (token != _token || !mounted) return;
          if (page.items.isNotEmpty) {
            setState(() {
              _hits = [..._hits, _ConversationHits(conversation, page.items, page.hasMore)]
                ..sort((a, b) => order[a.conversation.id]!.compareTo(order[b.conversation.id]!));
            });
          }
        } catch (_) {
          failed++;
        }
      }
    }

    await Future.wait(List.generate(_workers, (_) => worker()));
    if (!mounted || token != _token) return;
    setState(() {
      _searching = false;
      _allFailed = failed == targets.length;
    });
  }

  bool _chatMatches(Conversation c, String q) {
    final lower = q.toLowerCase();
    if (c.titleFor(widget.currentUserId).toLowerCase().contains(lower)) return true;
    if ((c.directEmail ?? '').toLowerCase().contains(lower)) return true;
    return c.members.any(
      (m) =>
          m.id != widget.currentUserId &&
          (m.name.toLowerCase().contains(lower) || (m.email ?? '').toLowerCase().contains(lower)),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _chatRow(Conversation c, String q) {
    final title = c.titleFor(widget.currentUserId);
    final last = c.lastMessage;
    return InkWell(
      onTap: () => widget.onConversationTap(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ChatAvatar(
              name: title,
              isGroup: c.isGroup,
              imageUrl: c.isGroup ? c.avatar : c.directAvatar,
              radius: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HighlightedText(
                    text: title,
                    query: q,
                    maxLines: 1,
                    windowed: false,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (last != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        last.previewText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _hitWidgets(_ConversationHits hit, String q) {
    final c = hit.conversation;
    final title = c.titleFor(widget.currentUserId);
    final shown = hit.messages.take(_perChat).toList();
    return [
      InkWell(
        onTap: () => widget.onConversationTap(c),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
          child: Row(
            children: [
              ChatAvatar(
                name: title,
                isGroup: c.isGroup,
                imageUrl: c.isGroup ? c.avatar : c.directAvatar,
                radius: 13,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      for (final m in shown)
        MessageHitTile(
          message: m,
          query: q,
          currentUserId: widget.currentUserId,
          onTap: () => widget.onMessageTap(c, m),
        ),
      if (hit.hasMore || hit.messages.length > _perChat)
        InkWell(
          onTap: () => widget.onOpenInChat(c, q),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                Text(
                  'See all matches in this chat',
                  style: TextStyle(color: AppColors.primaryLight, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primaryLight),
              ],
            ),
          ),
        ),
      const Divider(height: 1, color: AppColors.surfaceBorder),
    ];
  }

  Widget _footnote(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Text(text, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    if (q.isEmpty) {
      return const _SearchPlaceholder(icon: Icons.search_rounded, text: 'Search your chats and messages');
    }
    final chats = widget.conversations.where((c) => _chatMatches(c, q)).toList();
    final canSearchMessages = q.length >= 2;
    final nothing = chats.isEmpty && _hits.isEmpty && !_searching;
    if (nothing && !_allFailed && canSearchMessages) {
      return _SearchPlaceholder(icon: Icons.search_off_rounded, text: 'No results for “$q”');
    }

    final children = <Widget>[];
    if (chats.isNotEmpty) {
      children.add(_sectionHeader('Chats'));
      for (final c in chats) {
        children.add(_chatRow(c, q));
      }
    }
    if (_hits.isNotEmpty) {
      children.add(_sectionHeader('Messages'));
      for (final hit in _hits) {
        children.addAll(_hitWidgets(hit, q));
      }
    }
    if (!canSearchMessages) {
      children.add(_footnote('Type at least 2 characters to search inside messages.'));
    } else if (_allFailed) {
      children.add(_footnote('Message search is unavailable right now.'));
    } else if (!_searching && widget.conversations.length > _maxChats) {
      children.add(_footnote('Searched your $_maxChats most recent chats.'));
    }
    if (_searching && children.isEmpty) children.add(_footnote('Searching…'));
    if (nothing && !canSearchMessages && chats.isEmpty) {
      return _SearchPlaceholder(icon: Icons.search_off_rounded, text: 'No chats match “$q”');
    }

    return Column(
      children: [
        if (_searching)
          const LinearProgressIndicator(
            minHeight: 2,
            color: AppColors.primary,
            backgroundColor: Colors.transparent,
          ),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: 32),
            children: children,
          ),
        ),
      ],
    );
  }
}
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/community_repository.dart';
import 'package:quorum_app/api/saved_items_store.dart';
import 'package:quorum_app/api/socket_service.dart';
import 'package:quorum_app/models/community_models.dart';
import 'package:quorum_app/models/saved_item_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'community_widgets.dart';

class PostCommentsScreen extends StatefulWidget {
  const PostCommentsScreen({
    super.key,
    required this.post,
    required this.myId,
    required this.role,
    required this.onCountChanged,
  });

  final CommunityPost post;
  final String myId;
  final String role;
  final ValueChanged<int> onCountChanged;

  @override
  State<PostCommentsScreen> createState() => _PostCommentsScreenState();
}

class _PostCommentsScreenState extends State<PostCommentsScreen> {
  static const Color darkBg = Color(0xFF0F101A);

  final _repo = CommunityRepository.instance;
  final _socket = SocketService.instance;
  final _scroll = ScrollController();
  final _input = TextEditingController();

  List<CommunityComment> _comments = [];
  String? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  String? _error;
  late int _count = widget.post.commentCount;

  String get _postId => widget.post.id;

  SavedItemType get _saveType =>
      widget.post.isDocument ? SavedItemType.document : SavedItemType.resource;

  @override
  void initState() {
    super.initState();
    _socket.ensureConnected().then((_) {
      if (!mounted) return;
      _socket.joinPost(_postId);
    });
    _socket.on('community:comment:new', _onCommentNew);
    _socket.on('community:comment:deleted', _onCommentDeleted);
    SavedItemsStore.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _socket.off('community:comment:new', _onCommentNew);
    _socket.off('community:comment:deleted', _onCommentDeleted);
    _socket.leavePost(_postId);
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onCommentNew(dynamic data) {
    final j = asMap(data);
    if (j == null || !mounted) return;
    if ((j['postId'] ?? '').toString() != _postId) return;
    final raw = j['comment'];
    if (raw is! Map) return;
    final comment = CommunityComment.fromJson(Map<String, dynamic>.from(raw));
    if (_comments.any((c) => c.id == comment.id)) return;
    final stick = _scroll.hasClients && _scroll.position.pixels >= _scroll.position.maxScrollExtent - 120;
    setState(() => _comments = [..._comments, comment]);
    _setCount(_count + 1);
    if (stick) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _onCommentDeleted(dynamic data) {
    final j = asMap(data);
    if (j == null || !mounted) return;
    if ((j['postId'] ?? '').toString() != _postId) return;
    final id = (j['commentId'] ?? '').toString();
    if (!_comments.any((c) => c.id == id)) return;
    setState(() => _comments = _comments.where((c) => c.id != id).toList());
    _setCount(_count - 1);
  }

  Future<void> _toggleSave() async {
    try {
      final saved = await SavedItemsStore.instance.toggle(_saveType, _postId);
      if (!mounted) return;
      setState(() {});
      showCommunityToast(context, saved ? 'Saved to your items' : 'Removed from saved items');
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  void _setCount(int n) {
    _count = n < 0 ? 0 : n;
    widget.onCountChanged(_count);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.comments(_postId);
      if (!mounted) return;
      setState(() {
        _comments = page.items;
        _cursor = page.cursor;
        _hasMore = page.hasMore && page.cursor != null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.comments(_postId, cursor: _cursor);
      if (!mounted) return;
      final known = _comments.map((c) => c.id).toSet();
      setState(() {
        _comments = [..._comments, ...page.items.where((c) => !known.contains(c.id))];
        _cursor = page.cursor;
        _hasMore = page.hasMore && page.cursor != null;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final c = await _repo.createComment(_postId, text);
      if (!mounted) return;
      _input.clear();
      if (!_comments.any((x) => x.id == c.id)) {
        setState(() => _comments = [..._comments, c]);
        _setCount(_count + 1);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _edit(CommunityComment c) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => TextPromptDialog(
        title: 'Edit comment',
        actionLabel: 'Save',
        initial: c.content,
        maxLines: 6,
      ),
    );
    if (text == null || text.isEmpty || text == c.content || !mounted) return;
    try {
      await _repo.editComment(c.id, text);
      if (!mounted) return;
      final i = _comments.indexWhere((x) => x.id == c.id);
      if (i == -1) return;
      setState(() => _comments[i] = _comments[i].copyWith(content: text, updatedAt: DateTime.now()));
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _delete(CommunityComment c) async {
    final ok = await confirmAction(
      context,
      title: 'Delete comment?',
      body: 'This comment will be removed.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await _repo.deleteComment(c.id);
      if (!mounted) return;
      if (_comments.any((x) => x.id == c.id)) {
        setState(() => _comments = _comments.where((x) => x.id != c.id).toList());
        _setCount(_count - 1);
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  Widget _commentTile(CommunityComment c) {
    final mine = c.authorId == widget.myId;
    final canDelete = mine || canModerate(widget.role);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChatAvatar(name: c.authorName, imageUrl: c.authorAvatar, radius: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.authorName.isEmpty ? 'Unknown' : c.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        c.edited ? '${timeAgo(c.createdAt)} · edited' : timeAgo(c.createdAt),
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                      if (mine || canDelete)
                        PopupMenuButton<String>(
                          color: AppColors.surface,
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textSecondary),
                          onSelected: (v) {
                            if (v == 'edit') _edit(c);
                            if (v == 'delete') _delete(c);
                          },
                          itemBuilder: (_) => [
                            if (mine)
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
                        )
                      else
                        const SizedBox(width: 8),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 2),
                    child: SelectableText(
                      c.content,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.4),
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

  Widget _list() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return CenteredMessage(
        icon: Icons.cloud_off,
        text: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      children: [
        PostCard(
          post: widget.post.copyWith(commentCount: _count),
          canEdit: false,
          canDelete: false,
          saved: SavedItemsStore.instance.isSaved(_saveType, _postId),
          onToggleSave: _toggleSave,
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(2, 6, 2, 2),
          child: Text(
            'Comments',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (_comments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                'No comments yet. Start the conversation.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ..._comments.map(_commentTile),
        if (_hasMore)
          Center(
            child: _loadingMore
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    ),
                  )
                : TextButton(onPressed: _loadMore, child: const Text('Load more comments')),
          ),
      ],
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
          'Post',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _list()),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: darkBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.surfaceBorder),
                      ),
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Write a comment...',
                          hintStyle: TextStyle(color: AppColors.textSecondary),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          )
                        : const Icon(Icons.send_rounded, color: AppColors.primary),
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
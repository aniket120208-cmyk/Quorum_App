import 'package:flutter/material.dart';
import 'package:quorum_app/widgets/char_limit.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/org_feed_repository.dart';
import 'package:quorum_app/api/socket_service.dart';
import 'package:quorum_app/models/org_feed_models.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'org_feed_widgets.dart';
import 'organization_widgets.dart';

class OrgFeedCommentsScreen extends StatefulWidget {
  const OrgFeedCommentsScreen({
    super.key,
    required this.organization,
    required this.post,
    required this.canManage,
  });

  final Organization organization;
  final OrgFeedPost post;
  final bool canManage;

  @override
  State<OrgFeedCommentsScreen> createState() => _OrgFeedCommentsScreenState();
}

class _OrgFeedCommentsScreenState extends State<OrgFeedCommentsScreen> {
  final _repo = OrgFeedRepository.instance;
  final _input = TextEditingController();
  final _focus = FocusNode();
  List<OrgFeedComment> _comments = [];
  String? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  String? _error;
  OrgFeedComment? _replyTo;
  OrgFeedComment? _editing;

  late final Map<String, SocketHandler> _handlers = {
    'org:feed:comment:new': _onNew,
    'org:feed:comment:updated': _onUpdated,
    'org:feed:comment:deleted': _onDeleted,
  };

  String get _orgId => widget.organization.id;
  String get _postId => widget.post.id;

  @override
  void initState() {
    super.initState();
    SocketService.instance.ensureConnected();
    SocketService.instance.joinOrg(_orgId);
    _handlers.forEach(SocketService.instance.on);
    _load();
  }

  @override
  void dispose() {
    _handlers.forEach(SocketService.instance.off);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _ours(Map<String, dynamic>? m) =>
      m != null && m['organizationId']?.toString() == _orgId && m['postId']?.toString() == _postId;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.comments(_orgId, _postId);
      if (!mounted) return;
      setState(() {
        _comments = page.comments;
        _cursor = page.nextCursor;
        _hasMore = page.hasNextPage && page.nextCursor != null;
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
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.comments(_orgId, _postId, cursor: _cursor);
      if (!mounted) return;
      final known = {for (final c in _comments) c.id};
      setState(() {
        _comments = [..._comments, ...page.comments.where((c) => !known.contains(c.id))];
        _cursor = page.nextCursor;
        _hasMore = page.hasNextPage && page.nextCursor != null;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      orgToast(context, errorText(e), error: true);
    }
  }

  bool _exists(String id) => _comments.any((c) => c.id == id || c.replies.any((r) => r.id == id));

  void _insert(OrgFeedComment c) {
    if (c.id.isEmpty || _exists(c.id)) return;
    if (c.parentId == null) {
      _comments = [..._comments, c];
      return;
    }
    final i = _comments.indexWhere((p) => p.id == c.parentId);
    if (i < 0) return;
    final parent = _comments[i];
    final next = [..._comments];
    next[i] = parent.copyWith(replies: [...parent.replies, c]);
    _comments = next;
  }

  void _replaceContent(String id, String content) {
    _comments = [
      for (final c in _comments)
        if (c.id == id)
          c.copyWith(content: content, isEdited: true)
        else
          c.copyWith(
            replies: [
              for (final r in c.replies) r.id == id ? r.copyWith(content: content, isEdited: true) : r,
            ],
          ),
    ];
  }

  void _remove(String id) {
    _comments = [
      for (final c in _comments)
        if (c.id != id) c.copyWith(replies: c.replies.where((r) => r.id != id).toList()),
    ];
  }

  void _onNew(dynamic data) {
    final m = asMap(data);
    if (!_ours(m) || !mounted) return;
    final raw = m!['comment'];
    if (raw is! Map) return;
    final c = OrgFeedComment.fromJson(Map<String, dynamic>.from(raw));
    setState(() => _insert(c));
  }

  void _onUpdated(dynamic data) {
    final m = asMap(data);
    if (!_ours(m) || !mounted) return;
    final raw = m!['comment'];
    if (raw is! Map) return;
    final c = OrgFeedComment.fromJson(Map<String, dynamic>.from(raw));
    setState(() => _replaceContent(c.id, c.content));
  }

  void _onDeleted(dynamic data) {
    final m = asMap(data);
    if (!_ours(m) || !mounted) return;
    final id = m!['commentId']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() {
      if (_replyTo?.id == id) _replyTo = null;
      if (_editing?.id == id) {
        _editing = null;
        _input.clear();
      }
      _remove(id);
    });
  }

  void _startReply(OrgFeedComment c) {
    setState(() {
      _editing = null;
      _replyTo = c;
    });
    _input.clear();
    _focus.requestFocus();
  }

  void _startEdit(OrgFeedComment c) {
    setState(() {
      _replyTo = null;
      _editing = c;
    });
    _input.text = c.content;
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _focus.requestFocus();
  }

  void _cancelCompose() {
    setState(() {
      _replyTo = null;
      _editing = null;
    });
    _input.clear();
  }

  Future<void> _delete(OrgFeedComment c) async {
    final ok = await orgConfirm(
      context,
      title: 'Delete comment',
      body: c.replies.isEmpty ? 'This comment will be removed.' : 'This comment and its replies will be removed.',
      action: 'Delete',
    );
    if (!ok) return;
    try {
      await _repo.deleteComment(_orgId, _postId, c.id);
      if (!mounted) return;
      setState(() => _remove(c.id));
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final editing = _editing;
      if (editing != null) {
        await _repo.editComment(_orgId, _postId, editing.id, content: text);
        if (!mounted) return;
        setState(() => _replaceContent(editing.id, text));
      } else {
        final reply = _replyTo;
        final created = await _repo.addComment(
          _orgId,
          _postId,
          content: text,
          parentId: reply == null ? null : (reply.parentId ?? reply.id),
        );
        if (!mounted) return;
        setState(() => _insert(created));
      }
      if (!mounted) return;
      setState(() {
        _replyTo = null;
        _editing = null;
      });
      _input.clear();
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  int get _total => _comments.fold<int>(0, (n, c) => n + 1 + c.replies.length);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          _total == 0 ? 'Comments' : 'Comments ($_total)',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _body()),
          _composer(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: feedPurple));
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: orgMuted, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _load,
                child: const Text('Retry', style: TextStyle(color: feedPurple, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        _postSummary(),
        const SizedBox(height: 16),
        if (_comments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('No comments yet. Start the conversation.', style: TextStyle(color: orgMuted))),
          )
        else
          for (final c in _comments) ...[
            _tile(c, reply: false),
            for (final r in c.replies)
              Padding(
                padding: const EdgeInsets.only(left: 40),
                child: _tile(r, reply: true),
              ),
            const SizedBox(height: 10),
          ],
        if (_hasMore)
          Center(
            child: _loadingMore
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: feedPurple),
                    ),
                  )
                : TextButton(
                    onPressed: _loadMore,
                    child: const Text('Load more comments', style: TextStyle(color: feedPurple, fontWeight: FontWeight.w700)),
                  ),
          ),
      ],
    );
  }

  Widget _postSummary() {
    final p = widget.post;
    final name = p.author?.name.isNotEmpty == true ? p.author!.name : 'Member';
    final headline = (p.title != null && p.title!.isNotEmpty) ? p.title! : p.content;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: orgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: orgBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OrgAvatar(name: name, logo: p.author?.avatar, size: 34, circular: true),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name  ·  ${orgFeedTimeAgo(p.createdAt)}',
                  style: const TextStyle(color: orgMuted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  headline.isEmpty ? (p.fileName ?? 'Attachment') : headline,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(OrgFeedComment c, {required bool reply}) {
    final name = c.author?.name.isNotEmpty == true ? c.author!.name : 'Member';
    final mine = c.authorId == CurrentUser.id;
    final canDelete = mine || widget.canManage;
    Widget action(String label, VoidCallback onTap, {Color color = orgMuted}) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 14, top: 4, bottom: 2),
          child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OrgAvatar(name: name, logo: c.author?.avatar, size: reply ? 26 : 32, circular: true),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: orgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _editing?.id == c.id ? feedPurple : orgBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: mine ? '$name (You)' : name,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                            TextSpan(
                              text: '  ${orgFeedTimeAgo(c.createdAt)}${c.isEdited ? ' · edited' : ''}',
                              style: const TextStyle(color: orgMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(c.content, style: const TextStyle(color: feedBody, fontSize: 13.5, height: 1.4)),
                    ],
                  ),
                ),
                Row(
                  children: [
                    action('Reply', () => _startReply(c)),
                    if (mine) action('Edit', () => _startEdit(c)),
                    if (canDelete) action('Delete', () => _delete(c), color: const Color(0xFFEF4444)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    final banner = _editing != null
        ? 'Editing your comment'
        : _replyTo != null
            ? 'Replying to ${_replyTo!.author?.name ?? 'comment'}'
            : null;
    return Container(
      decoration: const BoxDecoration(
        color: orgCard,
        border: Border(top: BorderSide(color: orgBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (banner != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          banner,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: feedPurple, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                      InkWell(
                        onTap: _cancelCompose,
                        child: const Icon(Icons.close_rounded, color: orgMuted, size: 18),
                      ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      buildCounter: charLimitCounter,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      cursorColor: feedPurple,
                      decoration: InputDecoration(
                        hintText: 'Write a comment...',
                        hintStyle: const TextStyle(color: Color(0xFF5A5E6B)),
                        filled: true,
                        fillColor: orgField,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(color: orgBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(color: orgBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(color: feedPurple),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    style: IconButton.styleFrom(backgroundColor: feedPurple, foregroundColor: Colors.white),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(_editing != null ? Icons.check_rounded : Icons.send_rounded, size: 20),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/auth_service.dart';
import 'package:quorum_app/api/community_repository.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/saved_items_store.dart';
import 'package:quorum_app/api/socket_service.dart';
import 'package:quorum_app/api/upload_service.dart';
import 'package:quorum_app/models/community_models.dart';
import 'package:quorum_app/models/saved_item_models.dart';
import 'package:quorum_app/widgets/copyable_id_tile.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'community_invite_screen.dart';
import 'community_members_search.dart';
import 'community_widgets.dart';
import 'post_comments_screen.dart';

class CommunityDetailScreen extends StatefulWidget {
  const CommunityDetailScreen({
    super.key,
    required this.communityId,
    required this.initialName,
    required this.initialRole,
  });

  final String communityId;
  final String initialName;
  final String initialRole;

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _PendingFile {
  final String path;
  final String name;
  final String type;
  final int size;

  const _PendingFile(this.path, this.name, this.type, this.size);
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  static const Color darkBg = Color(0xFF0F101A);

  final _repo = CommunityRepository.instance;
  final _socket = SocketService.instance;
  final _scroll = ScrollController();
  final _composer = TextEditingController();

  CommunityDetail? _detail;
  List<CommunityChannel> _channels = [];
  String? _channelId;
  final Set<String> _unreadChannels = {};
  final Set<String> _countedComments = {};
  String? _openPostId;
  List<CommunityPost> _posts = [];
  String? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _switching = false;
  bool _posting = false;
  double _uploadProgress = 0;
  _PendingFile? _pending;
  bool _socketReady = false;
  String? _error;
  String _meId = '';

  String get _id => widget.communityId;
  String get _role => _detail?.role ?? widget.initialRole;
  String get _name => _detail?.name ?? widget.initialName;

  String? get _channelName {
    for (final c in _channels) {
      if (c.id == _channelId) return c.name;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _detachSocket();
    _socket.leaveCommunity(_id);
    final ch = _channelId;
    if (ch != null) _socket.leaveChannel(ch);
    _scroll.dispose();
    _composer.dispose();
    super.dispose();
  }

  void _attachSocket() {
    if (_socketReady) return;
    _socketReady = true;
    _socket.on('community:post:new', _onPostNew);
    _socket.on('community:post:updated', _onPostUpdated);
    _socket.on('community:post:deleted', _onPostDeleted);
    _socket.on('community:comment:new', _onCommentNew);
    _socket.on('community:comment:deleted', _onCommentDeleted);
    _socket.on('connect', _onReconnect);
  }

  void _detachSocket() {
    if (!_socketReady) return;
    _socketReady = false;
    _socket.off('community:post:new', _onPostNew);
    _socket.off('community:post:updated', _onPostUpdated);
    _socket.off('community:post:deleted', _onPostDeleted);
    _socket.off('community:comment:new', _onCommentNew);
    _socket.off('community:comment:deleted', _onCommentDeleted);
    _socket.off('connect', _onReconnect);
  }

  Future<void> _onReconnect(dynamic _) async {
    if (_loading || _switching) return;
    try {
      final page = await _loadPosts(_channelId, null);
      if (!mounted) return;
      final known = page.items.map((p) => p.id).toSet();
      setState(() {
        _posts = [...page.items, ..._posts.where((p) => !known.contains(p.id))];
      });
    } catch (_) {}
  }

  CommunityPost? _postFrom(dynamic data) {
    final j = asMap(data);
    final raw = j?['post'];
    if (raw is! Map) return null;
    final post = CommunityPost.fromJson(Map<String, dynamic>.from(raw));
    if (post.communityId.isNotEmpty && post.communityId != _id) return null;
    return post;
  }

  void _onPostNew(dynamic data) {
    final post = _postFrom(data);
    if (post == null || !mounted) return;
    final inView = _channelId == null || post.channelId == null || post.channelId == _channelId;
    if (inView) {
      if (_posts.any((p) => p.id == post.id)) return;
      setState(() => _posts = [post, ..._posts]);
    } else if (post.authorId != _meId) {
      setState(() => _unreadChannels.add(post.channelId!));
    }
  }

  void _onPostUpdated(dynamic data) {
    final post = _postFrom(data);
    if (post == null) return;
    _replacePost(
      post.id,
      (p) => p.copyWith(
        content: post.content,
        updatedAt: post.updatedAt,
        fileUrl: post.fileUrl,
        fileType: post.fileType,
      ),
    );
  }

  void _onPostDeleted(dynamic data) {
    final j = asMap(data);
    final postId = (j?['postId'] ?? '').toString();
    if (postId.isEmpty || !mounted) return;
    if (!_posts.any((p) => p.id == postId)) return;
    setState(() => _posts = _posts.where((p) => p.id != postId).toList());
  }

  void _onCommentNew(dynamic data) {
    final j = asMap(data);
    if (j == null || !mounted) return;
    final postId = (j['postId'] ?? '').toString();
    if (postId.isEmpty || postId == _openPostId) return;
    final comment = j['comment'];
    final commentId = comment is Map ? (comment['id'] ?? '').toString() : '';
    if (commentId.isNotEmpty && !_countedComments.add(commentId)) return;
    _replacePost(postId, (p) => p.copyWith(commentCount: p.commentCount + 1));
  }

  void _onCommentDeleted(dynamic data) {
    final j = asMap(data);
    if (j == null || !mounted) return;
    final postId = (j['postId'] ?? '').toString();
    if (postId.isEmpty || postId == _openPostId) return;
    final commentId = (j['commentId'] ?? '').toString();
    _countedComments.remove(commentId);
    _replacePost(postId, (p) => p.copyWith(commentCount: p.commentCount > 0 ? p.commentCount - 1 : 0));
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!CurrentUser.isLoaded) {
        CurrentUser.setFromProfile(await AuthService.instance.getUserProfile());
      }
      _meId = CurrentUser.id;
      await _socket.ensureConnected();
      _attachSocket();
      _socket.joinCommunity(_id);
      SavedItemsStore.instance.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      });
      await _fetch();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  Future<List<CommunityChannel>> _fetchChannels() async {
    try {
      return await _repo.channels(_id);
    } catch (e) {
      if (e is ApiException && e.statusCode == 404) return const [];
      rethrow;
    }
  }

  String? _pickChannel(List<CommunityChannel> channels) {
    if (channels.isEmpty) return null;
    for (final c in channels) {
      if (c.id == _channelId) return c.id;
    }
    for (final c in channels) {
      if (c.isDefault) return c.id;
    }
    return channels.first.id;
  }

  Future<PageResult<CommunityPost>> _loadPosts(String? channelId, String? cursor) {
    if (channelId == null) return _repo.posts(_id, cursor: cursor);
    return _repo.channelPosts(_id, channelId, cursor: cursor);
  }

  void _switchRoom(String? from, String? to) {
    if (from == to) return;
    if (from != null) _socket.leaveChannel(from);
    if (to != null) _socket.joinChannel(to);
  }

  Future<void> _fetch() async {
    final results = await Future.wait([_repo.detail(_id), _fetchChannels()]);
    final detail = results[0] as CommunityDetail;
    final channels = results[1] as List<CommunityChannel>;
    final selected = _pickChannel(channels);
    final page = await _loadPosts(selected, null);
    if (!mounted) return;
    _switchRoom(_channelId, selected);
    setState(() {
      _detail = detail;
      _channels = channels;
      _channelId = selected;
      if (selected != null) _unreadChannels.remove(selected);
      _posts = page.items;
      _cursor = page.cursor;
      _hasMore = page.hasMore && page.cursor != null;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _selectChannel(CommunityChannel channel) async {
    if (channel.id == _channelId || _switching) return;
    final previous = _channelId;
    setState(() {
      _channelId = channel.id;
      _unreadChannels.remove(channel.id);
      _posts = [];
      _cursor = null;
      _hasMore = false;
      _switching = true;
    });
    _switchRoom(previous, channel.id);
    try {
      final page = await _repo.channelPosts(_id, channel.id);
      if (!mounted || _channelId != channel.id) return;
      setState(() {
        _posts = page.items;
        _cursor = page.cursor;
        _hasMore = page.hasMore && page.cursor != null;
      });
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _reloadChannels({String? select}) async {
    final list = await _fetchChannels();
    if (!mounted) return;
    setState(() => _channels = list);
    final target = select ?? _channelId;
    final match = list.where((c) => c.id == target).toList();
    if (match.isNotEmpty) {
      if (match.first.id != _channelId) await _selectChannel(match.first);
      return;
    }
    if (list.isEmpty) return;
    final fallback = list.firstWhere((c) => c.isDefault, orElse: () => list.first);
    await _selectChannel(fallback);
  }

  String _normalizeChannel(String raw) => raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');

  Future<void> _addChannel() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const CommunityFormDialog(
        title: 'New channel',
        actionLabel: 'Create',
        nameHint: 'Channel name',
        descriptionHint: 'What is this channel for?',
        emptyError: 'Give the channel a name.',
        enforceLimits: false,
      ),
    );
    if (result == null || !mounted) return;
    try {
      final ch = await _repo.createChannel(_id, _normalizeChannel(result.$1), result.$2);
      await _reloadChannels(select: ch.id);
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _manageChannel(CommunityChannel ch) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
              title: const Text('Edit channel', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            if (!ch.isDefault)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete channel', style: TextStyle(color: Colors.redAccent)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'edit') {
      final result = await showDialog<(String, String)>(
        context: context,
        builder: (_) => CommunityFormDialog(
          title: 'Edit channel',
          actionLabel: 'Save',
          name: ch.name,
          description: ch.description ?? '',
          nameHint: 'Channel name',
          descriptionHint: 'What is this channel for?',
          emptyError: 'Give the channel a name.',
          enforceLimits: false,
        ),
      );
      if (result == null || !mounted) return;
      try {
        await _repo.updateChannel(_id, ch.id, name: _normalizeChannel(result.$1), description: result.$2);
        await _reloadChannels();
      } catch (e) {
        if (mounted) showErrorSnack(context, errorText(e));
      }
    } else {
      final ok = await confirmAction(
        context,
        title: 'Delete channel?',
        body: 'The channel "#${ch.name}" and all of its posts will be removed.',
        action: 'Delete',
      );
      if (!ok || !mounted) return;
      try {
        await _repo.deleteChannel(_id, ch.id);
        await _reloadChannels();
      } catch (e) {
        if (mounted) showErrorSnack(context, errorText(e));
      }
    }
  }

  Future<void> _refresh() async {
    try {
      await _fetch();
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _reloadDetail() async {
    try {
      final d = await _repo.detail(_id);
      if (mounted) setState(() => _detail = d);
    } catch (_) {}
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    final channelAtStart = _channelId;
    setState(() => _loadingMore = true);
    try {
      final page = await _loadPosts(channelAtStart, _cursor);
      if (!mounted) return;
      if (channelAtStart != _channelId) {
        setState(() => _loadingMore = false);
        return;
      }
      final known = _posts.map((p) => p.id).toSet();
      setState(() {
        _posts = [..._posts, ...page.items.where((p) => !known.contains(p.id))];
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

  Future<void> _pickAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.textPrimary),
              title: const Text('Photo from gallery', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.textPrimary),
              title: const Text('Take a photo', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined, color: AppColors.textPrimary),
              title: const Text('Document, video or audio', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    try {
      String? path;
      String? name;
      if (choice == 'file') {
        final f = await FilePicker.pickFile(type: FileType.any);
        path = f?.path;
        name = f?.name;
      } else {
        final x = await ImagePicker().pickImage(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
          imageQuality: 85,
        );
        path = x?.path;
        name = x?.name;
      }
      if (path == null || name == null) return;
      await UploadService.ensureWithinLimit(path, name);
      final size = await File(path).length();
      if (!mounted) return;
      setState(() => _pending = _PendingFile(path!, name!, UploadService.fileTypeFor(name), size));
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  String _sizeLabel(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }

  Future<void> _createPost() async {
    final text = _composer.text.trim();
    final file = _pending;
    if ((text.isEmpty && file == null) || _posting) return;
    setState(() {
      _posting = true;
      _uploadProgress = 0;
    });
    try {
      String? url;
      String? type;
      if (file != null) {
        var last = 0.0;
        final res = await UploadService.instance.upload(
          path: file.path,
          fileName: file.name,
          onProgress: (p) {
            if (mounted && (p - last >= 0.02 || p >= 1)) {
              last = p;
              setState(() => _uploadProgress = p);
            }
          },
        );
        url = res.url;
        type = UploadService.postFileType(res.fileType);
      }
      final content = text.isEmpty ? file!.name : text;
      final channelId = _channelId;
      final post = channelId == null
          ? await _repo.createPost(_id, content, fileUrl: url, fileType: type)
          : await _repo.createChannelPost(_id, channelId, content, fileUrl: url, fileType: type);
      if (!mounted) return;
      _composer.clear();
      setState(() {
        _pending = null;
        if (!_posts.any((p) => p.id == post.id)) _posts = [post, ..._posts];
      });
      if (_scroll.hasClients) {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _toggleSavePost(CommunityPost post) async {
    final type = post.isDocument ? SavedItemType.document : SavedItemType.resource;
    try {
      final saved = await SavedItemsStore.instance.toggle(type, post.id);
      if (!mounted) return;
      setState(() {});
      showCommunityToast(context, saved ? 'Saved to your items' : 'Removed from saved items');
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _editPost(CommunityPost post) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => TextPromptDialog(
        title: 'Edit post',
        actionLabel: 'Save',
        initial: post.content,
        maxLines: 8,
      ),
    );
    if (text == null || text.isEmpty || text == post.content || !mounted) return;
    try {
      await _repo.editPost(post.id, text);
      if (!mounted) return;
      _replacePost(post.id, (p) => p.copyWith(content: text, updatedAt: DateTime.now()));
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _deletePost(CommunityPost post) async {
    final ok = await confirmAction(
      context,
      title: 'Delete post?',
      body: 'This post and its comments will be removed.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await _repo.deletePost(post.id);
      if (!mounted) return;
      setState(() => _posts = _posts.where((p) => p.id != post.id).toList());
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  void _replacePost(String id, CommunityPost Function(CommunityPost p) change) {
    if (!mounted) return;
    final i = _posts.indexWhere((p) => p.id == id);
    if (i == -1) return;
    setState(() => _posts[i] = change(_posts[i]));
  }

  Future<void> _openComments(CommunityPost post) async {
    _openPostId = post.id;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostCommentsScreen(
          post: post,
          myId: _meId,
          role: _role,
          onCountChanged: (n) => _replacePost(post.id, (p) => p.copyWith(commentCount: n)),
        ),
      ),
    );
    _openPostId = null;
    if (mounted) setState(() {});
  }

  Future<void> _openMembers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityMembersScreen(
          communityId: _id,
          communityName: _name,
          myId: _meId,
          myRole: _role,
        ),
      ),
    );
    _reloadDetail();
  }

  Future<void> _openInvite() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityInviteScreen(communityId: _id, communityName: _name),
      ),
    );
  }

  Future<void> _editCommunity() async {
    final d = _detail;
    if (d == null) return;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => CommunityFormDialog(
        title: 'Edit community',
        actionLabel: 'Save',
        name: d.name,
        description: d.description ?? '',
      ),
    );
    if (result == null || !mounted) return;
    try {
      await _repo.updateCommunity(_id, name: result.$1, description: result.$2);
      await _reloadDetail();
      if (mounted) showCommunityToast(context, 'Community updated');
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _leave() async {
    final ok = await confirmAction(
      context,
      title: 'Leave community?',
      body: 'You will lose access to the feed. You can rejoin with a new invite link.',
      action: 'Leave',
    );
    if (!ok || !mounted) return;
    try {
      await _repo.leave(_id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _deleteCommunity() async {
    final ok = await confirmAction(
      context,
      title: 'Delete community?',
      body: 'This permanently deletes "$_name", including all posts and comments. This cannot be undone.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await _repo.deleteCommunity(_id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  Widget _header() {
    final d = _detail;
    if (d == null) return const SizedBox.shrink();
    final description = d.description;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CommunityAvatar(name: d.name, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.people_outline, size: 15, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          d.memberCount == 1 ? '1 member' : '${d.memberCount} members',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(width: 8),
                        RoleBadge(role: d.role),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              description,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
            ),
          ],
          if (d.ownerName.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                ChatAvatar(name: d.ownerName, imageUrl: d.ownerAvatar, radius: 10),
                const SizedBox(width: 8),
                Text(
                  'Owned by ${d.ownerName}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          CopyableIdTile(
            label: 'Community ID',
            value: _id,
            labelColor: AppColors.textMuted,
            valueColor: AppColors.textPrimary,
            borderColor: AppColors.surfaceBorder,
            accentColor: AppColors.primary,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openMembers,
                  icon: const Icon(Icons.people_outline, size: 18),
                  label: const Text('Members'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.surfaceBorder),
                  ),
                ),
              ),
              if (canModerate(_role)) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _openInvite,
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('Invite'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _feed() {
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
        itemCount: _posts.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) return _header();
          final index = i - 1;
          if (index >= _posts.length) {
            if (_loadingMore) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  ),
                ),
              );
            }
            if (_switching) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  ),
                ),
              );
            }
            if (_posts.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(Icons.forum_outlined, size: 44, color: AppColors.textSecondary),
                    SizedBox(height: 10),
                    Text(
                      'No posts yet.\nBe the first to share something.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          }
          final post = _posts[index];
          final mine = post.authorId == _meId;
          return PostCard(
            post: post,
            canEdit: mine,
            canDelete: mine || canModerate(_role),
            onComments: () => _openComments(post),
            onEdit: () => _editPost(post),
            onDelete: () => _deletePost(post),
            saved: SavedItemsStore.instance.isSaved(
              post.isDocument ? SavedItemType.document : SavedItemType.resource,
              post.id,
            ),
            onToggleSave: () => _toggleSavePost(post),
          );
        },
      ),
    );
  }

  Widget _pendingPreview() {
    final f = _pending;
    if (f == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: f.type == 'image'
                    ? Image.file(File(f.path), width: 44, height: 44, fit: BoxFit.cover)
                    : Container(
                        width: 44,
                        height: 44,
                        color: AppColors.primary.withValues(alpha: 0.18),
                        child: Icon(postFileIcon(f.type), color: AppColors.primaryLight),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                    ),
                    Text(
                      _posting ? 'Uploading ${(_uploadProgress * 100).round()}%' : _sizeLabel(f.size),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _posting ? null : () => setState(() => _pending = null),
                icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
              ),
            ],
          ),
          if (_posting)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                value: _uploadProgress > 0 ? _uploadProgress : null,
                minHeight: 2,
                color: AppColors.primary,
                backgroundColor: AppColors.surfaceBorder,
              ),
            ),
        ],
      ),
    );
  }

  Widget _composerBar() {
    final channel = _channelName;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Attach',
              onPressed: _posting ? null : _pickAttachment,
              icon: const Icon(Icons.attach_file, color: AppColors.textSecondary),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: darkBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: TextField(
                  controller: _composer,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: channel == null ? 'Share something with the community...' : 'Post in #$channel',
                    hintStyle: const TextStyle(color: AppColors.textSecondary),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: _posting ? null : _createPost,
              icon: _posting
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
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return CenteredMessage(
        icon: Icons.lock_outline,
        text: _error!,
        actionLabel: 'Retry',
        onAction: _init,
      );
    }
    return Column(
      children: [
        if (_channels.isNotEmpty)
          ChannelBar(
            channels: _channels,
            selectedId: _channelId,
            unreadIds: _unreadChannels,
            onSelect: _selectChannel,
            onAdd: canModerate(_role) ? _addChannel : null,
            onManage: canModerate(_role) ? _manageChannel : null,
          ),
        Expanded(child: _feed()),
        _pendingPreview(),
        _composerBar(),
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
        title: Text(
          _name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_detail != null)
            PopupMenuButton<String>(
              color: AppColors.surface,
              icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
              onSelected: (v) {
                switch (v) {
                  case 'members':
                    _openMembers();
                  case 'invite':
                    _openInvite();
                  case 'edit':
                    _editCommunity();
                  case 'leave':
                    _leave();
                  case 'delete':
                    _deleteCommunity();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'members',
                  child: Text('Members', style: TextStyle(color: AppColors.textPrimary)),
                ),
                if (canModerate(_role))
                  const PopupMenuItem(
                    value: 'invite',
                    child: Text('Invite people', style: TextStyle(color: AppColors.textPrimary)),
                  ),
                if (canModerate(_role))
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit details', style: TextStyle(color: AppColors.textPrimary)),
                  ),
                const PopupMenuItem(
                  value: 'leave',
                  child: Text('Leave community', style: TextStyle(color: Colors.redAccent)),
                ),
                if (_role == 'OWNER')
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete community', style: TextStyle(color: Colors.redAccent)),
                  ),
              ],
            ),
        ],
      ),
      body: _body(),
    );
  }
}
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/chat_repository.dart';
import 'package:quorum_app/api/socket_service.dart';
import 'package:quorum_app/api/saved_items_store.dart';
import 'package:quorum_app/api/upload_service.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'package:quorum_app/models/saved_item_models.dart';
import 'attachment_widgets.dart';
import 'chat_widgets.dart';
import 'group_info_screen.dart';
import 'mention_widgets.dart';

const int _maxMessageLength = 20000;
const int _counterThreshold = 1000;

String _formatCount(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.conversation,
    required this.currentUserId,
    this.currentUserName = 'You',
    this.initialMessageId,
  });

  final Conversation conversation;
  final String currentUserId;
  final String currentUserName;
  final String? initialMessageId;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  static const _tmp = 'tmp_';
  final _repo = ChatRepository.instance;
  final _socket = SocketService.instance;
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final GlobalKey _targetKey = GlobalKey();
  String? _jumpTargetId;
  String? _highlightId;
  Timer? _highlightTimer;
  bool _jumpStarted = false;

  late Conversation _conv;
  List<ChatMessage> _messages = [];
  String? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  final Set<String> _typingIds = {};
  Timer? _typingStop;
  Timer? _convRefresh;
  bool _iAmTyping = false;
  bool _leavingByMe = false;

  final Map<String, String> _mentions = {};
  List<ChatUser> _suggestions = [];
  int _mentionStart = -1;

  static const Color darkBg = Color(0xFF0F101A);
  static const Color primary = Color(0xFF6366F1);
  static const Color surface = Color(0xFF1E293B);
  static const Color surfaceBorder = Color(0xFF334155);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);

  String get _convId => _conv.id;
  String get _me => widget.currentUserId;

  @override
  void initState() {
    super.initState();
    _conv = widget.conversation;
    _socket.activeConversationId = _convId;
    _socket.join(_convId);
    _socket.on('message:new', _onNewMessage);
    _socket.on('message:read', _onRead);
    _socket.on('message:updated', _onMessageEdited);
    _socket.on('message:deleted', _onMessageDeleted);
    _socket.on('typing:start', _onTypingStart);
    _socket.on('typing:stop', _onTypingStop);
    _socket.on('conversation:removed', _onRemoved);
    _socket.on('conversation:update', _onConversationUpdate);
    _socket.on('connect', _onReconnect);
    _scrollCtrl.addListener(_onScroll);
    _inputCtrl.addListener(_onTextChanged);
    _loadInitial();
    SavedItemsStore.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stopTyping();
    _typingStop?.cancel();
    _convRefresh?.cancel();
    _highlightTimer?.cancel();
    if (_socket.activeConversationId == _convId) _socket.activeConversationId = null;
    _socket.leave(_convId);
    _socket.off('message:new', _onNewMessage);
    _socket.off('message:read', _onRead);
    _socket.off('message:updated', _onMessageEdited);
    _socket.off('message:deleted', _onMessageDeleted);
    _socket.off('typing:start', _onTypingStart);
    _socket.off('typing:stop', _onTypingStop);
    _socket.off('conversation:removed', _onRemoved);
    _socket.off('conversation:update', _onConversationUpdate);
    _socket.off('connect', _onReconnect);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<ChatMessage> _merge(List<ChatMessage> a, List<ChatMessage> b) {
    final map = <String, ChatMessage>{};
    for (final m in [...a, ...b]) {
      map[m.id] = m;
    }
    final realClientIds = map.values
        .where((m) => !m.id.startsWith(_tmp) && m.clientMessageId != null)
        .map((m) => m.clientMessageId!)
        .toSet();
    map.removeWhere((id, m) => id.startsWith(_tmp) && realClientIds.contains(id));
    return map.values.toList()..sort((x, y) => y.createdAt.compareTo(x.createdAt));
  }

  void _update(String id, ChatMessage Function(ChatMessage m) change) {
    if (!mounted) return;
    final i = _messages.indexWhere((m) => m.id == id);
    if (i == -1) return;
    setState(() => _messages[i] = change(_messages[i]));
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.messages(_convId);
      if (!mounted) return;
      setState(() {
        _messages = _merge(_messages, page.items);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
      _markReadLatest();
      final target = widget.initialMessageId;
      if (target != null && target.isNotEmpty && !_jumpStarted) {
        _jumpStarted = true;
        _jumpToMessage(target);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  Future<void> _jumpToMessage(String id) async {
    var guard = 0;
    while (mounted && !_messages.any((m) => m.id == id) && _hasMore && _cursor != null && guard < 100) {
      guard++;
      if (!_loadingMore) setState(() => _loadingMore = true);
      try {
        final page = await _repo.messages(_convId, cursor: _cursor);
        if (!mounted) return;
        setState(() {
          _messages = _merge(_messages, page.items);
          _cursor = page.cursor;
          _hasMore = page.hasMore;
        });
      } catch (_) {
        break;
      }
    }
    if (!mounted) return;
    setState(() => _loadingMore = false);
    if (!_messages.any((m) => m.id == id)) {
      showInfoSnack(context, 'That message is no longer available');
      return;
    }
    setState(() {
      _jumpTargetId = id;
      _highlightId = id;
    });
    await _revealTarget();
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  Future<void> _revealTarget() async {
    var stuck = 0;
    for (var i = 0; i < 600; i++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scrollCtrl.hasClients) return;
      final ctx = _targetKey.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        return;
      }
      final pos = _scrollCtrl.position;
      final next = (pos.pixels + pos.viewportDimension * 0.8).clamp(0.0, pos.maxScrollExtent).toDouble();
      if (next <= pos.pixels) {
        stuck++;
        if (stuck > 5) return;
      } else {
        stuck = 0;
      }
      _scrollCtrl.jumpTo(next);
    }
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.messages(_convId, cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _messages = _merge(_messages, page.items);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _onReconnect(dynamic _) async {
    try {
      final page = await _repo.messages(_convId);
      if (!mounted) return;
      setState(() => _messages = _merge(_messages, page.items));
      _markReadLatest();
    } catch (_) {}
  }

  void _onConversationUpdate(dynamic data) {
    if (!_conv.isGroup) return;
    final j = asMap(data);
    final id = (j?['conversationId'] ?? j?['id'])?.toString();
    if (id != null && id != _convId) return;
    _convRefresh?.cancel();
    _convRefresh = Timer(const Duration(milliseconds: 400), _refreshConversation);
  }

  Future<void> _refreshConversation() async {
    try {
      final c = await _repo.conversationById(_convId, _me);
      if (!mounted || c == null) return;
      setState(() => _conv = c);
    } catch (_) {}
  }

  String _newTempId() => '$_tmp${DateTime.now().microsecondsSinceEpoch}';

  List<String> _collectMentions(String text) {
    final ids = _mentions.entries
        .where((e) => text.contains('@${e.value}'))
        .map((e) => e.key)
        .toList();
    _mentions.clear();
    return ids;
  }

  void _clearSuggestions() {
    if (_suggestions.isEmpty && _mentionStart == -1) return;
    setState(() {
      _suggestions = [];
      _mentionStart = -1;
    });
  }

  void _updateSuggestions() {
    final sel = _inputCtrl.selection;
    final text = _inputCtrl.text;
    if (!sel.isValid || !sel.isCollapsed || sel.baseOffset > text.length) {
      _clearSuggestions();
      return;
    }
    final before = text.substring(0, sel.baseOffset);
    final at = before.lastIndexOf('@');
    if (at == -1 || (at > 0 && !RegExp(r'\s').hasMatch(before[at - 1]))) {
      _clearSuggestions();
      return;
    }
    final query = before.substring(at + 1);
    if (RegExp(r'\s').hasMatch(query)) {
      _clearSuggestions();
      return;
    }
    final q = query.toLowerCase();
    final matches = _conv.members
        .where((u) => u.id != _me && u.name.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        final aw = a.name.toLowerCase().startsWith(q) ? 0 : 1;
        final bw = b.name.toLowerCase().startsWith(q) ? 0 : 1;
        return aw != bw ? aw.compareTo(bw) : a.name.compareTo(b.name);
      });
    if (matches.isEmpty) {
      _clearSuggestions();
      return;
    }
    setState(() {
      _mentionStart = at;
      _suggestions = matches.take(6).toList();
    });
  }

  void _pickMention(ChatUser user) {
    final cursor = _inputCtrl.selection.baseOffset;
    if (_mentionStart < 0 || cursor < _mentionStart) return;
    final insert = '@${user.name} ';
    final next = _inputCtrl.text.replaceRange(_mentionStart, cursor, insert);
    _mentions[user.id] = user.name;
    _inputCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: _mentionStart + insert.length),
    );
  }

  void _send() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    final mentionIds = _collectMentions(text);
    _inputCtrl.clear();
    _stopTyping();
    final id = _newTempId();
    final temp = ChatMessage(
      id: id,
      clientMessageId: id,
      senderId: _me,
      senderName: widget.currentUserName,
      text: text,
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
      mentionedUserIds: mentionIds,
    );
    setState(() => _messages.insert(0, temp));
    _scrollToNewest();
    _dispatch(id);
  }

  Future<void> _showAttachMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: textPrimary),
              title: const Text('Photo from gallery',
                  style: TextStyle(color: textPrimary)),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: textPrimary),
              title: const Text('Take a photo',
                  style: TextStyle(color: textPrimary)),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined, color: textPrimary),
              title: const Text('File', style: TextStyle(color: textPrimary)),
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
      _startUpload(path, name);
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  void _startUpload(String path, String name) {
    final caption = _inputCtrl.text.trim();
    final mentionIds = _collectMentions(caption);
    _inputCtrl.clear();
    _stopTyping();
    final id = _newTempId();
    final temp = ChatMessage(
      id: id,
      clientMessageId: id,
      senderId: _me,
      senderName: widget.currentUserName,
      text: caption,
      mentionedUserIds: mentionIds,
      fileType: UploadService.fileTypeFor(name),
      fileName: name,
      localPath: path,
      uploadProgress: 0,
      createdAt: DateTime.now(),
      status: MessageStatus.uploading,
    );
    setState(() => _messages.insert(0, temp));
    _scrollToNewest();
    _dispatch(id);
  }

  Future<void> _dispatch(String id) async {
    final i = _messages.indexWhere((m) => m.id == id);
    if (i == -1) return;
    final m = _messages[i];

    if (m.fileUrl == null && m.localPath != null) {
      _update(id, (x) => x.copyWith(status: MessageStatus.uploading, uploadProgress: 0));
      var last = 0.0;
      try {
        final res = await UploadService.instance.upload(
          path: m.localPath!,
          fileName: m.attachmentName,
          onProgress: (p) {
            if (p - last >= 0.02 || p >= 1) {
              last = p;
              _update(id, (x) => x.copyWith(uploadProgress: p));
            }
          },
        );
        if (!mounted) return;
        _update(id, (x) => x.copyWith(fileUrl: res.url, fileType: res.fileType));
      } catch (e) {
        if (!mounted) return;
        _update(id, (x) => x.copyWith(status: MessageStatus.uploadFailed));
        showErrorSnack(context, errorText(e));
        return;
      }
    }
    _emitSend(id);
  }

  void _emitSend(String id) {
    final i = _messages.indexWhere((m) => m.id == id);
    if (i == -1) return;
    final m = _messages[i];
    setState(() => _messages[i] = m.copyWith(status: MessageStatus.sending));

    _socket.emitAck('message:send', {
      'conversationId': _convId,
      'clientMessageId': id,
      if (m.text.isNotEmpty) 'content': m.text,
      if (m.mentionedUserIds.isNotEmpty) 'mentions': m.mentionedUserIds,
      if (m.fileUrl != null) 'fileUrl': m.fileUrl,
      if (m.fileUrl != null) 'fileType': m.fileType ?? 'file',
    }, (res) {
      if (!mounted) return;
      if (res != null && res['success'] == true && res['data'] is Map) {
        final j = Map<String, dynamic>.from(res['data']);
        setState(() {
          final idx = _messages.indexWhere((x) => x.id == id);
          final old = idx == -1 ? null : _messages[idx];
          var real = ChatMessage.fromJson(j);
          if (real.senderId.isEmpty) {
            real = real.copyWith(senderId: _me, senderName: widget.currentUserName);
          }
          if (old != null) {
            real = real.copyWith(localPath: old.localPath, fileName: old.fileName);
            if (real.mentionedUserIds.isEmpty && old.mentionedUserIds.isNotEmpty) {
              real = real.copyWith(mentionedUserIds: old.mentionedUserIds);
            }
          }
          _messages.removeWhere((x) => x.id == id);
          if (!_messages.any((x) => x.id == real.id)) _messages.add(real);
          _messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });
      } else {
        if (kDebugMode) debugPrint('message:send failed: $res');
        _update(id, (x) => x.copyWith(status: MessageStatus.failed));
      }
    });
  }

  void _scrollToNewest() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(0,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _onNewMessage(dynamic data) {
    final j = asMap(data);
    if (j == null || !mounted) return;
    if ((j['conversationId'] ?? '').toString() != _convId) return;
    final msg = ChatMessage.fromJson(j);
    setState(() {
      _messages = _merge(_messages, [msg]);
      _typingIds.remove(msg.senderId);
    });
    if (msg.senderId != _me) _markRead(msg.id);
  }

  void _markRead(String messageId) {
    if (messageId.startsWith(_tmp)) return;
    _socket.emit('message:read', {'conversationId': _convId, 'messageId': messageId});
  }

  void _markReadLatest() {
    final latest = _messages
        .where((m) => m.senderId != _me && !m.id.startsWith(_tmp))
        .firstOrNull;
    if (latest != null) _markRead(latest.id);
  }

  void _onRead(dynamic data) {
    final j = asMap(data);
    if (j == null || !mounted) return;
    if ((j['conversationId'] ?? '').toString() != _convId) return;
    final reader = (j['userId'] ?? j['readerId'] ?? '').toString();
    if (reader == _me) return;
    final readId = (j['messageId'] ?? j['lastReadMessageId'] ?? '').toString();
    final hit = _messages.where((m) => m.id == readId);
    if (hit.isEmpty) return;
    final boundary = hit.first.createdAt;
    setState(() {
      _messages = _messages
          .map((m) => m.senderId == _me && !m.createdAt.isAfter(boundary)
              ? m.copyWith(isRead: true)
              : m)
          .toList();
    });
  }

  void _onMessageEdited(dynamic data) {
    final j = asMap(data);
    if (j == null || !mounted) return;
    final msg = j['message'] is Map ? Map<String, dynamic>.from(j['message']) : j;
    final conv = (j['conversationId'] ?? msg['conversationId'] ?? '').toString();
    if (conv.isNotEmpty && conv != _convId) return;
    final id = (msg['messageId'] ?? msg['id'] ?? j['messageId'] ?? '').toString();
    final content = msg['content'] ?? j['content'];
    if (id.isEmpty || content == null) return;
    _update(id, (x) => x.copyWith(text: content.toString(), isEdited: true));
  }

  void _onMessageDeleted(dynamic data) {
    final j = asMap(data);
    if (j == null || !mounted) return;
    final conv = (j['conversationId'] ?? '').toString();
    if (conv.isNotEmpty && conv != _convId) return;
    final id = (j['messageId'] ?? j['id'] ?? '').toString();
    if (id.isEmpty) return;
    setState(() => _messages.removeWhere((x) => x.id == id));
  }

  void _onRemoved(dynamic data) {
    final j = asMap(data);
    if (j == null || !mounted) return;
    if ((j['conversationId'] ?? '').toString() != _convId) return;
    if (!_leavingByMe) {
      showErrorSnack(context, 'You were removed from this group');
    }
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _onTextChanged() {
    _updateSuggestions();
    if (_inputCtrl.text.isEmpty) {
      _mentions.clear();
      _stopTyping();
      return;
    }
    if (!_iAmTyping) {
      _iAmTyping = true;
      _socket.emit('typing:start', {'conversationId': _convId});
    }
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(seconds: 2), _stopTyping);
  }

  void _stopTyping() {
    _typingStop?.cancel();
    if (_iAmTyping) {
      _iAmTyping = false;
      _socket.emit('typing:stop', {'conversationId': _convId});
    }
  }

  void _onTypingStart(dynamic data) {
    final j = asMap(data);
    if (j == null || !mounted) return;
    if ((j['conversationId'] ?? '').toString() != _convId) return;
    final uid = (j['userId'] ?? j['senderId'] ?? '').toString();
    if (uid.isEmpty || uid == _me) return;
    setState(() => _typingIds.add(uid));
    Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _typingIds.remove(uid));
    });
  }

  void _onTypingStop(dynamic data) {
    final j = asMap(data);
    if (j == null || !mounted) return;
    final uid = (j['userId'] ?? j['senderId'] ?? '').toString();
    setState(() => _typingIds.remove(uid));
  }

  String? _otherEmail() {
    final direct = _conv.directEmail;
    if (direct != null && direct.isNotEmpty) return direct;
    for (final u in _conv.members) {
      if (u.id != _me && u.email != null && u.email!.isNotEmpty) return u.email;
    }
    return null;
  }

  String? _emailFor(ChatMessage m) {
    final fromMsg = m.senderEmail;
    if (fromMsg != null && fromMsg.isNotEmpty) return fromMsg;
    for (final u in _conv.members) {
      if (u.id == m.senderId) return u.email;
    }
    return null;
  }

  String? get _subtitle {
    if (_typingIds.isNotEmpty) {
      if (!_conv.isGroup) return 'typing…';
      final names = _conv.members
          .where((m) => _typingIds.contains(m.id))
          .map((m) => m.name)
          .toList();
      return names.isEmpty ? 'Someone is typing…' : '${names.join(', ')} typing…';
    }
    return _conv.isGroup ? '${_conv.members.length} members' : _otherEmail();
  }

  Future<void> _toggleSave(SavedItemType type, String itemId) async {
    try {
      final saved = await SavedItemsStore.instance.toggle(type, itemId);
      if (!mounted) return;
      setState(() {});
      showInfoSnack(context, saved ? 'Saved to your items' : 'Removed from saved items');
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _editMessage(ChatMessage m) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _EditMessageDialog(initial: m.text),
    );
    if (text == null || !mounted) return;
    final value = text.trim();
    if (value == m.text.trim()) return;
    if (value.isEmpty && !m.hasAttachment) {
      showErrorSnack(context, 'A message cannot be empty');
      return;
    }
    _update(m.id, (x) => x.copyWith(text: value, isEdited: true));
    try {
      await ChatRepository.instance.editMessage(_convId, m.id, value);
    } catch (e) {
      if (!mounted) return;
      _update(m.id, (_) => m);
      showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _deleteMessage(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        title: const Text('Delete message?', style: TextStyle(color: textPrimary)),
        content: const Text(
          'This message will be deleted for everyone in this chat.',
          style: TextStyle(color: textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _messages.removeWhere((x) => x.id == m.id));
    try {
      await ChatRepository.instance.deleteMessage(_convId, m.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages = _merge(_messages, [m]));
      showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _showMessageActions(ChatMessage m) async {
    if (m.id.startsWith(_tmp) || m.status != MessageStatus.sent) return;
    final type = m.fileUrl != null ? SavedItemType.file : SavedItemType.message;
    final saved = SavedItemsStore.instance.isSaved(type, m.id);
    final mine = m.senderId == _me;
    final canDelete = mine || (_conv.isGroup && _conv.adminId == _me);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m.text.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: textPrimary),
                title: const Text('Copy text', style: TextStyle(color: textPrimary)),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
            ListTile(
              leading: Icon(saved ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined, color: textPrimary),
              title: Text(
                saved ? 'Remove from saved' : (type == SavedItemType.file ? 'Save file' : 'Save message'),
                style: const TextStyle(color: textPrimary),
              ),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
            if (mine && m.text.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: textPrimary),
                title: const Text('Edit message', style: TextStyle(color: textPrimary)),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                title: const Text('Delete message', style: TextStyle(color: Colors.redAccent)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'edit') {
      await _editMessage(m);
      return;
    }
    if (choice == 'delete') {
      await _deleteMessage(m);
      return;
    }
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text));
      if (mounted) showInfoSnack(context, 'Copied');
      return;
    }
    await _toggleSave(type, m.id);
  }

  Future<void> _openGroupInfo() async {
    final result = await Navigator.of(context).push<GroupInfoResult>(
      MaterialPageRoute(
        builder: (_) => GroupInfoScreen(
          conversation: _conv,
          currentUserId: _me,
          onLeaving: (v) => _leavingByMe = v,
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result.left) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    final c = result.conversation;
    if (c != null) setState(() => _conv = c);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatClock(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _formatDayLabel(DateTime date) {
    final now = DateTime.now();
    if (_isSameDay(date, now)) return 'Today';
    if (_isSameDay(date, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: primary));
    }
    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _loadInitial, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text('No messages yet. Say hi!',
            style: TextStyle(color: textSecondary)),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _messages.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: primary),
              ),
            ),
          );
        }
        final m = _messages[i];
        final older = i + 1 < _messages.length ? _messages[i + 1] : null;
        final newer = i > 0 ? _messages[i - 1] : null;
        final showDay = older == null || !_isSameDay(older.createdAt, m.createdAt);
        final isMe = m.senderId == _me;
        final startsRun = older == null || showDay || older.senderId != m.senderId;
        final endsRun = newer == null || newer.senderId != m.senderId;
        final showSender = _conv.isGroup && !isMe && startsRun;
        final canRetry =
            m.status == MessageStatus.failed || m.status == MessageStatus.uploadFailed;

        return Column(
          key: m.id == _jumpTargetId ? _targetKey : null,
          children: [
            if (showDay) _DayChip(label: _formatDayLabel(m.createdAt)),
            _MessageBubble(
              message: m,
              isMe: isMe,
              highlighted: m.id == _highlightId,
              showSender: showSender,
              senderEmail: showSender ? _emailFor(m) : null,
              showTime: endsRun,
              timeText: _formatClock(m.createdAt),
              onRetry: canRetry ? () => _dispatch(m.id) : null,
              onLongPress: () => _showMessageActions(m),
              members: _conv.members,
              myId: _me,
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _conv.titleFor(_me);
    final subtitle = _subtitle;

    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        backgroundColor: darkBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: textPrimary),
        titleSpacing: 0,
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _conv.isGroup ? _openGroupInfo : null,
          child: Row(
            children: [
              ChatAvatar(
                name: title,
                isGroup: _conv.isGroup,
                imageUrl: _conv.isGroup ? _conv.avatar : null,
                radius: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: SavedItemsStore.instance.isSaved(SavedItemType.chat, _convId) ? 'Remove from saved' : 'Save chat',
            icon: Icon(
              SavedItemsStore.instance.isSaved(SavedItemType.chat, _convId)
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
            ),
            onPressed: () => _toggleSave(SavedItemType.chat, _convId),
          ),
          if (_conv.isGroup)
            IconButton(
              tooltip: 'Group info',
              icon: const Icon(Icons.info_outline),
              onPressed: _openGroupInfo,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          if (_suggestions.isNotEmpty)
            MentionSuggestionList(users: _suggestions, onPick: _pickMention),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _inputCtrl,
            builder: (_, value, __) {
              final left = _maxMessageLength - value.text.length;
              if (left > _counterThreshold) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                color: surface,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  left <= 0
                      ? 'Character limit reached (${_formatCount(_maxMessageLength)})'
                      : '${_formatCount(left)} of ${_formatCount(_maxMessageLength)} characters left',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              );
            },
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
              decoration: const BoxDecoration(
                color: surface,
                border: Border(top: BorderSide(color: surfaceBorder)),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Attach',
                    icon: const Icon(Icons.attach_file, color: textSecondary),
                    onPressed: _showAttachMenu,
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: darkBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: surfaceBorder),
                      ),
                      child: TextField(
                        controller: _inputCtrl,
                        minLines: 1,
                        maxLines: 4,
                        inputFormatters: [LengthLimitingTextInputFormatter(_maxMessageLength)],
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(color: textPrimary, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: TextStyle(color: textSecondary),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send_rounded, color: primary),
                    onPressed: _send,
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

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF94A3B8)),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.highlighted = false,
    required this.showSender,
    required this.showTime,
    required this.timeText,
    required this.members,
    required this.myId,
    this.senderEmail,
    this.onRetry,
    this.onLongPress,
  });

  final ChatMessage message;
  final bool isMe;
  final bool highlighted;
  final bool showSender;
  final String? senderEmail;
  final bool showTime;
  final String timeText;
  final VoidCallback? onRetry;
  final VoidCallback? onLongPress;
  final List<ChatUser> members;
  final String myId;

  @override
  Widget build(BuildContext context) {
    final mentionsMe = !isMe && message.mentions(myId);
    final status = message.status;
    final failed = status == MessageStatus.failed;
    final uploadFailed = status == MessageStatus.uploadFailed;
    final uploading = status == MessageStatus.uploading;
    final sending = status == MessageStatus.sending;

    IconData statusIcon() {
      if (failed || uploadFailed) return Icons.error_outline;
      if (uploading || sending) return Icons.access_time;
      return message.isRead ? Icons.done_all : Icons.done;
    }

    Color statusColor() {
      if (failed || uploadFailed) return Colors.redAccent;
      if (!uploading && !sending && message.isRead) return const Color(0xFF818CF8);
      return const Color(0xFF94A3B8);
    }

    String statusLabel() {
      if (failed) return 'Failed · tap to retry';
      if (uploadFailed) return 'Upload failed · tap to retry';
      if (uploading) {
        final p = ((message.uploadProgress ?? 0) * 100).round();
        return 'Uploading $p%';
      }
      return message.isEdited ? 'edited · $timeText' : timeText;
    }

    final hasText = message.text.isNotEmpty;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: onRetry,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: message.hasAttachment
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                color: isMe
                    ? const Color(0xFF6366F1)
                    : (mentionsMe ? const Color(0xFF2B2A3D) : const Color(0xFF1E293B)),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                border: highlighted
                    ? Border.all(color: mentionAmber, width: 2)
                    : mentionsMe
                        ? Border.all(color: mentionAmber.withValues(alpha: 0.6))
                        : ((isMe || message.hasAttachment) ? null : Border.all(color: const Color(0xFF334155))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showSender && message.senderName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.senderName,
                            style: const TextStyle(
                              color: Color(0xFF818CF8),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (senderEmail != null && senderEmail!.isNotEmpty)
                            Text(
                              senderEmail!,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (message.hasAttachment) AttachmentView(message: message),
                  if (hasText)
                    Padding(
                      padding: message.hasAttachment
                          ? const EdgeInsets.fromLTRB(14, 8, 14, 8)
                          : EdgeInsets.zero,
                      child: MentionText(
                        text: message.text,
                        names: mentionNamesFor(message, members),
                        myNames: myMentionNamesFor(message, members, myId),
                        isMe: isMe,
                        style: const TextStyle(color: Color(0xFFF8FAFC), fontSize: 14),
                      ),
                    ),
                ],
              ),
            ),
            if (showTime || status != MessageStatus.sent || message.isEdited)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4, left: 4, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      statusLabel(),
                      style: TextStyle(
                        fontSize: 10,
                        color: (failed || uploadFailed)
                            ? Colors.redAccent
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(statusIcon(), size: 13, color: statusColor()),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EditMessageDialog extends StatefulWidget {
  const _EditMessageDialog({required this.initial});
  final String initial;

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      title: const Text('Edit message', style: TextStyle(color: Color(0xFFF8FAFC))),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        minLines: 1,
        maxLines: 6,
        inputFormatters: [LengthLimitingTextInputFormatter(_maxMessageLength)],
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(color: Color(0xFFF8FAFC)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('Save')),
      ],
    );
  }
}
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/chat_repository.dart';
import 'package:quorum_app/api/socket_service.dart';
import 'package:quorum_app/api/upload_service.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'attachment_widgets.dart';
import 'chat_widgets.dart';
import 'group_info_screen.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.conversation,
    required this.currentUserId,
    this.currentUserName = 'You',
  });

  final Conversation conversation;
  final String currentUserId;
  final String currentUserName;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  static const _tmp = 'tmp_';
  final _repo = ChatRepository.instance;
  final _socket = SocketService.instance;
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

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
    _socket.join(_convId);
    _socket.on('message:new', _onNewMessage);
    _socket.on('message:read', _onRead);
    _socket.on('typing:start', _onTypingStart);
    _socket.on('typing:stop', _onTypingStop);
    _socket.on('conversation:removed', _onRemoved);
    _socket.on('conversation:update', _onConversationUpdate);
    _socket.on('connect', _onReconnect);
    _scrollCtrl.addListener(_onScroll);
    _inputCtrl.addListener(_onTextChanged);
    _loadInitial();
  }

  @override
  void dispose() {
    _stopTyping();
    _typingStop?.cancel();
    _convRefresh?.cancel();
    _socket.leave(_convId);
    _socket.off('message:new', _onNewMessage);
    _socket.off('message:read', _onRead);
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
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

  void _send() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
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
      _startUpload(path, name);
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  void _startUpload(String path, String name) {
    final caption = _inputCtrl.text.trim();
    _inputCtrl.clear();
    _stopTyping();
    final id = _newTempId();
    final temp = ChatMessage(
      id: id,
      clientMessageId: id,
      senderId: _me,
      senderName: widget.currentUserName,
      text: caption,
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
    if (_inputCtrl.text.isEmpty) {
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
          children: [
            if (showDay) _DayChip(label: _formatDayLabel(m.createdAt)),
            _MessageBubble(
              message: m,
              isMe: isMe,
              showSender: showSender,
              senderEmail: showSender ? _emailFor(m) : null,
              showTime: endsRun,
              timeText: _formatClock(m.createdAt),
              onRetry: canRetry ? () => _dispatch(m.id) : null,
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
    required this.showSender,
    required this.showTime,
    required this.timeText,
    this.senderEmail,
    this.onRetry,
  });

  final ChatMessage message;
  final bool isMe;
  final bool showSender;
  final String? senderEmail;
  final bool showTime;
  final String timeText;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
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
      return timeText;
    }

    final hasText = message.text.isNotEmpty;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: onRetry,
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
                color: isMe ? const Color(0xFF6366F1) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                border: (isMe || message.hasAttachment) ? null : Border.all(color: const Color(0xFF334155)),
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
                      child: Text(
                        message.text,
                        style: const TextStyle(color: Color(0xFFF8FAFC), fontSize: 14),
                      ),
                    ),
                ],
              ),
            ),
            if (showTime || status != MessageStatus.sent)
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
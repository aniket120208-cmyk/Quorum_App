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
import 'package:quorum_app/models/poll_models.dart';
import 'package:quorum_app/models/saved_item_models.dart';
import 'package:quorum_app/widgets/poll_widgets.dart';
import 'attachment_widgets.dart';
import 'chat_widgets.dart';
import 'forward_screen.dart';
import 'group_info_screen.dart';
import 'mention_widgets.dart';
import 'rich_chat_widgets.dart';
import 'voice_widgets.dart';

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
  final Set<String> _votingPolls = {};
  Timer? _typingStop;
  Timer? _convRefresh;
  bool _iAmTyping = false;
  bool _leavingByMe = false;

  final Map<String, String> _mentions = {};
  List<ChatUser> _suggestions = [];
  int _mentionStart = -1;

  ChatMessage? _replyTo;
  final List<String> _selectedIds = [];
  final VoiceRecorderController _recorder = VoiceRecorderController();
  bool _recording = false;
  bool get _selecting => _selectedIds.isNotEmpty;

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
    _socket.on('message:reaction_updated', _onReactionUpdated);
    _socket.on('poll:updated', _onPollUpdated);
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
    _socket.off('message:reaction_updated', _onReactionUpdated);
    _socket.off('poll:updated', _onPollUpdated);
    _socket.off('typing:start', _onTypingStart);
    _socket.off('typing:stop', _onTypingStop);
    _socket.off('conversation:removed', _onRemoved);
    _socket.off('conversation:update', _onConversationUpdate);
    _socket.off('connect', _onReconnect);
    _recorder.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<ChatMessage> _merge(List<ChatMessage> a, List<ChatMessage> b) {
    final map = <String, ChatMessage>{};
    for (final m in [...a, ...b]) {
      final prev = map[m.id];
      map[m.id] = (m.poll == null && prev?.poll != null) ? m.copyWith(poll: prev!.poll) : m;
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

  QuotedReply? _quoteOf(ChatMessage? m) {
    if (m == null) return null;
    return QuotedReply(
      id: m.id,
      content: m.text,
      fileUrl: m.fileUrl,
      fileType: m.fileType,
      fileName: m.fileName,
      audioDuration: m.audioDuration,
      isDeleted: m.isDeleted,
      senderId: m.senderId,
      senderName: m.senderName,
      senderAvatar: m.senderAvatar,
    );
  }

  void _send() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    final mentionIds = _collectMentions(text);
    _inputCtrl.clear();
    _stopTyping();
    final id = _newTempId();
    final reply = _replyTo;
    final temp = ChatMessage(
      id: id,
      clientMessageId: id,
      senderId: _me,
      senderName: widget.currentUserName,
      text: text,
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
      mentionedUserIds: mentionIds,
      replyToId: reply?.id,
      replyTo: _quoteOf(reply),
    );
    setState(() {
      _messages.insert(0, temp);
      _replyTo = null;
    });
    _scrollToNewest();
    _dispatch(id);
  }

  Future<void> _startRecording() async {
    _stopTyping();
    try {
      final ok = await _recorder.start();
      if (!mounted) return;
      if (!ok) {
        showErrorSnack(context, 'Microphone permission is required to record voice messages');
        return;
      }
      setState(() => _recording = true);
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _cancelRecording() async {
    await _recorder.cancel();
    if (mounted) setState(() => _recording = false);
  }

  Future<void> _sendRecording() async {
    final rec = await _recorder.stop();
    if (!mounted) return;
    setState(() => _recording = false);
    if (rec == null) {
      showInfoSnack(context, 'Recording was too short');
      return;
    }
    _startVoiceUpload(rec);
  }

  void _startVoiceUpload(VoiceRecording rec) {
    final id = _newTempId();
    final reply = _replyTo;
    final temp = ChatMessage(
      id: id,
      clientMessageId: id,
      senderId: _me,
      senderName: widget.currentUserName,
      fileType: 'voice',
      fileName: 'voice_note.m4a',
      localPath: rec.path,
      fileSize: rec.sizeBytes,
      audioDuration: rec.durationSeconds,
      audioWaveform: rec.waveform,
      uploadProgress: 0,
      createdAt: DateTime.now(),
      status: MessageStatus.uploading,
      replyToId: reply?.id,
      replyTo: _quoteOf(reply),
    );
    setState(() {
      _messages.insert(0, temp);
      _replyTo = null;
    });
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
            ListTile(
              leading: const Icon(Icons.poll_outlined, color: textPrimary),
              title: const Text('Poll', style: TextStyle(color: textPrimary)),
              onTap: () => Navigator.pop(ctx, 'poll'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'poll') {
      await _createPoll();
      return;
    }

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
    final reply = _replyTo;
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
      replyToId: reply?.id,
      replyTo: _quoteOf(reply),
    );
    setState(() {
      _messages.insert(0, temp);
      _replyTo = null;
    });
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
      void progress(double p) {
        if (p - last >= 0.02 || p >= 1) {
          last = p;
          _update(id, (x) => x.copyWith(uploadProgress: p));
        }
      }

      try {
        final res = m.isVoice
            ? await UploadService.instance.uploadVoice(
                conversationId: _convId,
                path: m.localPath!,
                fileName: m.attachmentName,
                onProgress: progress,
              )
            : await UploadService.instance.upload(
                path: m.localPath!,
                fileName: m.attachmentName,
                onProgress: progress,
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
      if (m.text.isNotEmpty || m.isVoice) 'content': m.text,
      if (m.mentionedUserIds.isNotEmpty) 'mentions': m.mentionedUserIds,
      if (m.replyToId != null) 'replyToId': m.replyToId,
      if (m.fileUrl != null) 'fileUrl': m.fileUrl,
      if (m.fileUrl != null) 'fileType': m.fileType ?? 'file',
      if (m.poll != null)
        'poll': {
          'question': m.poll!.question,
          'options': m.poll!.options.map((o) => o.text).toList(),
          'allowMultipleAnswers': m.poll!.allowMultipleAnswers,
        },
      if (m.isVoice) ...{
        'fileName': m.attachmentName,
        if (m.fileSize != null) 'fileSize': m.fileSize,
        'audioDuration': m.audioDuration ?? 0,
        'audioWaveform': m.audioWaveform,
      },
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
            real = real.copyWith(
              localPath: old.localPath,
              fileName: real.fileName ?? old.fileName,
              fileType: real.fileType ?? old.fileType,
              poll: real.poll ?? old.poll,
              replyTo: real.replyTo ?? old.replyTo,
              replyToId: real.replyToId ?? old.replyToId,
              audioWaveform: real.audioWaveform.isEmpty ? old.audioWaveform : real.audioWaveform,
              audioDuration: real.audioDuration ?? old.audioDuration,
            );
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
    if (msg.isPoll && msg.poll == null) _onReconnect(null);
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
    final forMe = j['deletedForMe'] == true || j['deleteForEveryone'] == false;
    if (forMe) {
      setState(() {
        _messages.removeWhere((x) => x.id == id);
        _selectedIds.remove(id);
      });
      return;
    }
    _markDeleted(id);
  }

  void _markDeleted(String id) {
    if (!mounted) return;
    setState(() {
      _messages = _messages.map((x) {
        if (x.id == id) return x.asDeleted();
        final quoted = x.replyTo;
        if (quoted != null && quoted.id == id) return x.copyWith(replyTo: quoted.asDeleted());
        return x;
      }).toList();
      _selectedIds.remove(id);
      if (_replyTo?.id == id) _replyTo = null;
    });
  }

  void _onReactionUpdated(dynamic data) {
    final j = asMap(data);
    if (j == null || !mounted) return;
    final conv = (j['conversationId'] ?? '').toString();
    if (conv.isNotEmpty && conv != _convId) return;
    final id = (j['messageId'] ?? '').toString();
    if (id.isEmpty) return;
    final groups = MessageReactionGroup.listFrom(j['reactions']);
    _update(id, (x) => x.copyWith(reactions: groups));
  }

  Future<T> _socketOrRest<T>(
    String event,
    Map<String, dynamic> data,
    T Function(Map<String, dynamic> res) fromAck,
    Future<T> Function() rest,
  ) async {
    final completer = Completer<Map<String, dynamic>?>();
    final started = DateTime.now();
    _socket.emitAck(event, data, completer.complete);
    final res = await completer.future;
    if (res == null) {
      if (DateTime.now().difference(started) > const Duration(seconds: 5)) {
        throw ApiException('The request timed out. Please try again.');
      }
      return rest();
    }
    if (res['success'] != true) {
      throw ApiException((res['message'] ?? 'Something went wrong').toString());
    }
    return fromAck(res);
  }

  Future<void> _react(ChatMessage m, String emoji) async {
    if (m.isDeleted || m.id.startsWith(_tmp)) return;
    final before = m.reactions;
    final me = ChatUser(id: _me, name: widget.currentUserName);
    _update(m.id, (x) => x.copyWith(reactions: toggleReaction(before, me, emoji)));
    try {
      final groups = await _socketOrRest<List<MessageReactionGroup>>(
        'message:react',
        {'conversationId': _convId, 'messageId': m.id, 'emoji': emoji},
        (res) {
          final d = res['data'];
          return MessageReactionGroup.listFrom(d is Map ? d['reactions'] : null);
        },
        () => _repo.reactToMessage(_convId, m.id, emoji),
      );
      if (mounted) _update(m.id, (x) => x.copyWith(reactions: groups));
    } catch (e) {
      if (!mounted) return;
      _update(m.id, (x) => x.copyWith(reactions: before));
      showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _createPoll() async {
    final draft = await showCreatePollSheet(context);
    if (draft == null || !mounted) return;
    _stopTyping();
    final id = _newTempId();
    final reply = _replyTo;
    final temp = ChatMessage(
      id: id,
      clientMessageId: id,
      senderId: _me,
      senderName: widget.currentUserName,
      text: draft.question,
      fileType: 'poll',
      poll: Poll.fromDraft(id, draft),
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
      replyToId: reply?.id,
      replyTo: _quoteOf(reply),
    );
    setState(() {
      _messages.insert(0, temp);
      _replyTo = null;
    });
    _scrollToNewest();
    _dispatch(id);
  }

  Future<void> _votePoll(ChatMessage m, String optionId) async {
    final poll = m.poll;
    if (poll == null || poll.isClosed || m.isDeleted || m.id.startsWith(_tmp)) return;
    if (!_votingPolls.add(m.id)) return;
    final me = ChatUser(id: _me, name: widget.currentUserName);
    _update(m.id, (x) => x.copyWith(poll: poll.toggledVote(me, optionId)));
    try {
      final updated = await _socketOrRest<Poll?>(
        'poll:vote',
        {'conversationId': _convId, 'messageId': m.id, 'optionIds': [optionId]},
        (res) => Poll.tryParse(res['data']),
        () => _repo.votePoll(_convId, poll.id, [optionId]),
      );
      if (mounted && updated != null) _update(m.id, (x) => x.copyWith(poll: updated));
    } catch (e) {
      if (!mounted) return;
      _update(m.id, (x) => x.copyWith(poll: poll));
      showErrorSnack(context, errorText(e));
    } finally {
      _votingPolls.remove(m.id);
    }
  }

  void _onPollUpdated(dynamic data) {
    final j = asMap(data);
    if (j == null || !mounted) return;
    final conv = (j['conversationId'] ?? '').toString();
    if (conv.isNotEmpty && conv != _convId) return;
    final incoming = Poll.tryParse(j['poll']);
    if (incoming == null) return;
    var id = (j['messageId'] ?? '').toString();
    if (id.isEmpty) {
      final hit = _messages.where((x) => x.poll?.id == incoming.id);
      if (hit.isEmpty) return;
      id = hit.first.id;
    }
    if (_votingPolls.contains(id)) return;
    _update(id, (x) => x.copyWith(poll: incoming.resolvedFor(_me, x.poll)));
  }

  Future<void> _openForward(List<String> ids) async {
    if (ids.isEmpty) return;
    final targets = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => ForwardScreen(currentUserId: _me, messageCount: ids.length),
      ),
    );
    if (targets == null || targets.isEmpty || !mounted) return;
    setState(_selectedIds.clear);
    try {
      await _socketOrRest<void>(
        'message:forward',
        {'messageIds': ids, 'targetConversationIds': targets},
        (_) {},
        () => _repo.forwardMessages(ids, targets),
      );
      if (mounted) showInfoSnack(context, ids.length == 1 ? 'Message forwarded' : 'Messages forwarded');
    } catch (e) {
      if (mounted) showErrorSnack(context, errorText(e));
    }
  }

  bool _forwardable(ChatMessage m) =>
      !m.isDeleted && !m.id.startsWith(_tmp) && m.status == MessageStatus.sent;

  void _forwardSelected() {
    final ids = _selectedIds.where((id) {
      final hit = _messages.where((m) => m.id == id);
      return hit.isNotEmpty && _forwardable(hit.first);
    }).toList();
    if (ids.isEmpty) {
      showInfoSnack(context, 'These messages cannot be forwarded');
      return;
    }
    _openForward(ids);
  }

  void _toggleSelect(ChatMessage m) {
    if (m.id.startsWith(_tmp)) return;
    setState(() {
      if (_selectedIds.contains(m.id)) {
        _selectedIds.remove(m.id);
      } else {
        _selectedIds.add(m.id);
      }
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
    final canEveryone = !m.isDeleted && (m.senderId == _me || (_conv.isGroup && _conv.adminId == _me));
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        title: const Text('Delete message?', style: TextStyle(color: textPrimary)),
        content: Text(
          canEveryone
              ? 'You can delete this message for everyone, or only remove it from your own view.'
              : 'This message will be removed only from your view.',
          style: const TextStyle(color: textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'me'), child: const Text('Delete for me')),
          if (canEveryone)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'everyone'),
              child: const Text('Delete for everyone', style: TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final everyone = choice == 'everyone';
    final snapshot = List<ChatMessage>.of(_messages);
    if (everyone) {
      _markDeleted(m.id);
    } else {
      setState(() {
        _messages.removeWhere((x) => x.id == m.id);
        _selectedIds.remove(m.id);
      });
    }
    try {
      await _socketOrRest<void>(
        'message:delete',
        {'conversationId': _convId, 'messageId': m.id, 'deleteForEveryone': everyone},
        (_) {},
        () => _repo.deleteMessage(_convId, m.id, forEveryone: everyone),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages = snapshot);
      showErrorSnack(context, errorText(e));
    }
  }

  Future<void> _showMessageActions(ChatMessage m) async {
    if (m.id.startsWith(_tmp) || m.status != MessageStatus.sent) return;
    HapticFeedback.mediumImpact();
    final deleted = m.isDeleted;
    final type = m.fileUrl != null ? SavedItemType.file : SavedItemType.message;
    final saved = SavedItemsStore.instance.isSaved(type, m.id);
    final mine = m.senderId == _me;
    final editable = mine &&
        !deleted &&
        !m.isVoice &&
        !m.isPoll &&
        m.text.isNotEmpty &&
        DateTime.now().difference(m.createdAt) < const Duration(hours: 24);
    final myGroups = m.reactions.where((g) => g.reactedBy(_me));
    final myReaction = myGroups.isEmpty ? null : myGroups.first.emoji;

    Widget tile(IconData icon, String label, String value, BuildContext ctx, {Color color = textPrimary}) {
      return ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color)),
        onTap: () => Navigator.pop(ctx, value),
      );
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: surface,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!deleted) ...[
                ReactionPickerRow(selected: myReaction, onPick: (e) => Navigator.pop(ctx, 'react:$e')),
                const Divider(height: 1, color: surfaceBorder),
                tile(Icons.reply_rounded, 'Reply', 'reply', ctx),
              ],
              if (!deleted && m.reactions.isNotEmpty)
                tile(Icons.emoji_emotions_outlined, 'View reactions', 'reactions', ctx),
              if (!deleted && m.text.isNotEmpty) tile(Icons.copy_rounded, 'Copy text', 'copy', ctx),
              if (!deleted) tile(Icons.shortcut_rounded, 'Forward', 'forward', ctx),
              tile(Icons.check_circle_outline_rounded, 'Select', 'select', ctx),
              if (!deleted)
                tile(
                  saved ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined,
                  saved ? 'Remove from saved' : (type == SavedItemType.file ? 'Save file' : 'Save message'),
                  'save',
                  ctx,
                ),
              if (editable) tile(Icons.edit_outlined, 'Edit message', 'edit', ctx),
              tile(Icons.delete_outline_rounded, 'Delete message', 'delete', ctx, color: Colors.redAccent),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice.startsWith('react:')) {
      await _react(m, choice.substring(6));
      return;
    }
    switch (choice) {
      case 'reply':
        setState(() => _replyTo = m);
      case 'reactions':
        await showReactorsSheet(
          context,
          m.reactions,
          _me,
          onRemoveMine: (e) => _react(m, e),
        );
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.text));
        if (mounted) showInfoSnack(context, 'Copied');
      case 'forward':
        await _openForward([m.id]);
      case 'select':
        setState(() => _selectedIds.add(m.id));
      case 'edit':
        await _editMessage(m);
      case 'delete':
        await _deleteMessage(m);
      case 'save':
        await _toggleSave(type, m.id);
    }
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

  String? _avatarFor(ChatMessage m) {
    final own = m.senderAvatar;
    if (own != null && own.isNotEmpty) return own;
    for (final u in _conv.members) {
      if (u.id == m.senderId && u.avatarUrl != null && u.avatarUrl!.isNotEmpty) return u.avatarUrl;
    }
    if (!_conv.isGroup && m.senderId != _me) return _conv.directAvatar;
    return null;
  }

  String _nameFor(ChatMessage m) {
    if (m.senderName.isNotEmpty) return m.senderName;
    for (final u in _conv.members) {
      if (u.id == m.senderId) return u.name;
    }
    return _conv.directName ?? '';
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
        final topGap = (older == null || showDay) ? 4.0 : (startsRun ? 14.0 : 5.0);

        return Column(
          key: m.id == _jumpTargetId ? _targetKey : null,
          children: [
            if (showDay) _DayChip(label: _formatDayLabel(m.createdAt)),
            _MessageBubble(
              message: m,
              isMe: isMe,
              highlighted: m.id == _highlightId,
              showSender: showSender,
              showAvatar: !isMe && startsRun && !_conv.isGroup,
              leadingAvatar: !_conv.isGroup,
              avatarUrl: _avatarFor(m),
              avatarName: _nameFor(m),
              topGap: topGap,
              senderEmail: showSender ? _emailFor(m) : null,
              showTime: true,
              timeText: _formatClock(m.createdAt),
              selecting: _selecting,
              selected: _selectedIds.contains(m.id),
              onRetry: canRetry && !_selecting ? () => _dispatch(m.id) : null,
              onTap: _selecting ? () => _toggleSelect(m) : null,
              onLongPress: () => _selecting ? _toggleSelect(m) : _showMessageActions(m),
              onReply: () => setState(() => _replyTo = m),
              onReact: (emoji) => _react(m, emoji),
              onReactors: (groups, emoji) => showReactorsSheet(
                context,
                groups,
                _me,
                initialEmoji: emoji,
                onRemoveMine: (e) => _react(m, e),
              ),
              onOpenReply: m.replyTo == null ? null : () => _jumpToMessage(m.replyTo!.id),
              onVote: _selecting || m.id.startsWith(_tmp) ? null : (optionId) => _votePoll(m, optionId),
              members: _conv.members,
              myId: _me,
            ),
          ],
        );
      },
    );
  }

  PreferredSizeWidget _selectionBar() {
    return AppBar(
      backgroundColor: darkBg,
      elevation: 0,
      iconTheme: const IconThemeData(color: textPrimary),
      titleSpacing: 0,
      leading: IconButton(
        tooltip: 'Cancel selection',
        icon: const Icon(Icons.close_rounded),
        onPressed: () => setState(_selectedIds.clear),
      ),
      title: Text(
        '${_selectedIds.length} selected',
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textPrimary),
      ),
      actions: [
        IconButton(
          tooltip: 'Forward',
          icon: const Icon(Icons.shortcut_rounded),
          onPressed: _forwardSelected,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) setState(_selectedIds.clear);
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildComposer() {
    final replying = _replyTo != null && !_recording;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (replying)
          ReplyComposerPreview(
            message: _replyTo!,
            myId: _me,
            onClose: () => setState(() => _replyTo = null),
          ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
            decoration: BoxDecoration(
              color: surface,
              border: Border(top: BorderSide(color: replying ? Colors.transparent : surfaceBorder)),
            ),
            child: _recording
                ? VoiceRecorderBar(
                    controller: _recorder,
                    onCancel: _cancelRecording,
                    onSend: _sendRecording,
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
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
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _inputCtrl,
                        builder: (_, value, __) {
                          final hasText = value.text.trim().isNotEmpty;
                          return IconButton(
                            tooltip: hasText ? 'Send' : 'Record voice message',
                            icon: Icon(hasText ? Icons.send_rounded : Icons.mic_rounded, color: primary),
                            onPressed: hasText ? _send : _startRecording,
                          );
                        },
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final title = _conv.titleFor(_me);
    final subtitle = _subtitle;

    return Scaffold(
      backgroundColor: darkBg,
      appBar: _selecting ? _selectionBar() : AppBar(
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
                imageUrl: _conv.isGroup ? _conv.avatar : _conv.directAvatar,
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
          _buildComposer(),
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
    required this.showAvatar,
    required this.leadingAvatar,
    this.avatarUrl,
    required this.avatarName,
    required this.topGap,
    required this.showTime,
    required this.timeText,
    required this.members,
    required this.myId,
    required this.onReact,
    required this.onReactors,
    this.senderEmail,
    this.selecting = false,
    this.selected = false,
    this.onRetry,
    this.onTap,
    this.onLongPress,
    this.onReply,
    this.onOpenReply,
    this.onVote,
  });

  final ChatMessage message;
  final bool isMe;
  final bool highlighted;
  final bool showSender;
  final bool showAvatar;
  final bool leadingAvatar;
  final String? avatarUrl;
  final String avatarName;
  final double topGap;
  final String? senderEmail;
  final bool showTime;
  final String timeText;
  final bool selecting;
  final bool selected;
  final VoidCallback? onRetry;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onReply;
  final VoidCallback? onOpenReply;
  final ValueChanged<String>? onVote;
  final ValueChanged<String> onReact;
  final void Function(List<MessageReactionGroup> groups, String emoji) onReactors;
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
    final deleted = message.isDeleted;

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
      return message.isEdited && !deleted ? 'edited · $timeText' : timeText;
    }

    final hasText = message.text.isNotEmpty;
    final isImage = message.fileType == 'image';
    final hasHeader = showSender ||
        message.isForwarded ||
        message.replyTo != null;
    final canSwipe = !selecting && status == MessageStatus.sent && !deleted && onReply != null;
    final maxBubble = MediaQuery.of(context).size.width * 0.72;

    final content = <Widget>[
      if (showSender)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 14, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ChatAvatar(name: avatarName, imageUrl: avatarUrl, radius: 10),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      avatarName.isEmpty ? 'Unknown' : avatarName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF818CF8),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (senderEmail != null && senderEmail!.isNotEmpty)
                      Text(
                        senderEmail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      if (!deleted && message.isForwarded)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: ForwardedLabel(isMe: isMe),
        ),
      if (!deleted && message.replyTo != null)
        QuotedReplyBanner(
          reply: message.replyTo!,
          isMe: isMe,
          myId: myId,
          onTap: onOpenReply,
        ),
      if (deleted)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block_rounded, size: 15, color: isMe ? Colors.white60 : const Color(0xFF94A3B8)),
              const SizedBox(width: 6),
              Text(
                'This message was deleted',
                style: TextStyle(
                  color: isMe ? Colors.white70 : const Color(0xFF94A3B8),
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        )
      else if (message.isPoll && message.poll != null)
        SizedBox(
          width: maxBubble,
          child: PollCard(
            poll: message.poll!,
            myId: myId,
            mine: isMe,
            pending: status != MessageStatus.sent,
            onVote: onVote,
          ),
        )
      else ...[
        if (message.hasAttachment && message.isVoice)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 14, 6),
            child: VoiceMessageView(message: message, isMe: isMe),
          )
        else if (message.hasAttachment)
          Padding(
            padding: isImage
                ? EdgeInsets.only(top: hasHeader ? 6 : 0)
                : const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: AttachmentView(message: message),
          ),
        if (hasText)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: MentionText(
              text: message.text,
              names: mentionNamesFor(message, members),
              myNames: myMentionNamesFor(message, members, myId),
              isMe: isMe,
              style: const TextStyle(color: Color(0xFFF8FAFC), fontSize: 14),
            ),
          ),
      ],
    ];

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxBubble),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isMe
            ? const Color(0xFF6366F1)
            : (mentionsMe ? const Color(0xFF2B2A3D) : const Color(0xFF1E293B)),
        borderRadius: BorderRadius.circular(16),
        border: highlighted
            ? Border.all(color: mentionAmber, width: 2)
            : mentionsMe
                ? Border.all(color: mentionAmber.withValues(alpha: 0.6))
                : ((isMe || (message.hasAttachment && !deleted)) ? null : Border.all(color: const Color(0xFF334155))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: content,
      ),
    );

    final column = Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        bubble,
        if (!deleted && message.reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ReactionChips(
              groups: message.reactions,
              myId: myId,
              onTap: onReact,
              onLongPress: (g) => onReactors(message.reactions, g.emoji),
            ),
          ),
        if (showTime || status != MessageStatus.sent || message.isEdited)
          Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 2, left: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  statusLabel(),
                  style: TextStyle(
                    fontSize: 10,
                    color: (failed || uploadFailed) ? Colors.redAccent : const Color(0xFF94A3B8),
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
    );

    return Container(
      color: selected ? const Color(0xFF6366F1).withValues(alpha: 0.16) : Colors.transparent,
      padding: EdgeInsets.only(top: topGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selecting)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 8),
              child: Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? const Color(0xFF818CF8) : const Color(0xFF64748B),
              ),
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                if (!isMe && leadingAvatar) ...[
                  SizedBox(
                    width: 30,
                    child: showAvatar ? ChatAvatar(name: avatarName, imageUrl: avatarUrl, radius: 15) : null,
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: SwipeToReply(
                    enabled: canSwipe,
                    onReply: onReply ?? () {},
                    child: GestureDetector(
                      onTap: onTap ?? onRetry,
                      onLongPress: onLongPress,
                      child: column,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
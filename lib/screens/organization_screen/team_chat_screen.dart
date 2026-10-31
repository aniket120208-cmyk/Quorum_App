import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/api/socket_service.dart';
import 'package:quorum_app/api/upload_service.dart';
import 'package:quorum_app/models/chat_models.dart' show TeamConversations;
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/screens/jira_screen/team_jira_board_screen.dart';
import 'package:quorum_app/screens/meetings_screen/meetings_list_screen.dart';
import 'package:quorum_app/screens/chat_screen/attachment_widgets.dart';
import 'organization_widgets.dart';

class TeamChatScreen extends StatefulWidget {
  const TeamChatScreen({
    super.key,
    required this.organization,
    required this.team,
    this.members = const [],
  });

  final Organization organization;
  final OrgTeam team;
  final List<OrgMember> members;

  @override
  State<TeamChatScreen> createState() => _TeamChatScreenState();
}

class _TeamChatScreenState extends State<TeamChatScreen> {
  final _repo = OrganizationRepository.instance;
  final _socket = SocketService.instance;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  List<TeamMessage> _messages = [];
  List<OrgMember> _teamMembers = [];
  bool _teamMembersLoaded = false;
  String? _conversationId;
  bool _loading = true;
  String? _error;
  String _mentionQuery = '';
  bool _mentionActive = false;
  int _tempCounter = 0;
  Timer? _poller;
  bool _syncing = false;

  int get _memberCount => _teamMembersLoaded ? _teamMembers.length : widget.team.membersCount;
  List<OrgMember> get _mentionPool => _teamMembers.isNotEmpty ? _teamMembers : widget.members;

  bool get _isLead => orgCanInvite(widget.organization.role);
  String get _me => CurrentUser.id;

  @override
  void initState() {
    super.initState();
    _socket.on('chat:message:new', _onSocketMessage);
    _socket.on('message:new', _onGenericMessage);
    _socket.on('connect', _onReconnect);
    _input.addListener(_onInputChanged);
    _load();
    _loadTeamMembers();
    _poller = Timer.periodic(const Duration(seconds: 3), (_) {
      _sync();
      _loadTeamMembers();
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    _socket.off('chat:message:new', _onSocketMessage);
    _socket.off('message:new', _onGenericMessage);
    _socket.off('connect', _onReconnect);
    final id = _conversationId;
    if (id != null) _socket.leaveTeamRoom(id);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadTeamMembers() async {
    try {
      final people = await _repo.teamMembers(widget.organization.id, widget.team.id);
      if (!mounted) return;
      final changed = !_teamMembersLoaded ||
          people.length != _teamMembers.length ||
          people.map((m) => m.userId).join(',') != _teamMembers.map((m) => m.userId).join(',');
      if (changed) {
        setState(() {
          _teamMembers = people;
          _teamMembersLoaded = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final history = await _repo.teamMessages(widget.organization.id, widget.team.id);
      if (!mounted) return;
      final pending = _messages.where((m) => m.isPending).toList();
      if (history.conversationId.isNotEmpty) {
        TeamConversations.ids.add(history.conversationId);
      }
      setState(() {
        _conversationId = history.conversationId;
        _messages = [...history.messages, ...pending];
        _loading = false;
      });
      await _socket.ensureConnected();
      if (history.conversationId.isNotEmpty) {
        _socket.joinTeamRoom(history.conversationId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  void _onReconnect(dynamic _) {
    final id = _conversationId;
    if (id != null && id.isNotEmpty) _socket.joinTeamRoom(id);
    _sync();
  }

  bool _sameList(List<TeamMessage> a, List<TeamMessage> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].isPinned != b[i].isPinned || a[i].status != b[i].status) {
        return false;
      }
    }
    return true;
  }

  Future<void> _sync() async {
    if (_syncing || !mounted || _loading || _conversationId == null) return;
    _syncing = true;
    try {
      final history = await _repo.teamMessages(widget.organization.id, widget.team.id);
      if (!mounted) return;
      final pending = _messages.where((m) {
        if (!m.isPending) return false;
        final duplicated = history.messages.any((s) =>
            s.senderId == m.senderId &&
            s.content == m.content &&
            s.fileName == m.fileName &&
            !s.createdAt.isBefore(m.createdAt.subtract(const Duration(minutes: 1))));
        return !duplicated;
      }).toList();
      final next = [...history.messages, ...pending];
      final current = _messages;
      if (_sameList(current, next)) return;
      final grew = next.length > current.length;
      setState(() => _messages = next);
      if (grew) _scrollToNewest();
    } catch (_) {
    } finally {
      _syncing = false;
    }
  }

  void _onGenericMessage(dynamic raw) {
    final map = asMap(raw);
    if (map == null) return;
    final inner = map['message'];
    final source = inner is Map ? Map<String, dynamic>.from(inner) : map;
    if (source['conversationId'] == null) return;
    _onSocketMessage(raw);
  }

  void _onSocketMessage(dynamic raw) {
    var map = asMap(raw);
    if (map == null || !mounted) return;
    final inner = map['message'];
    if (inner is Map) map = Map<String, dynamic>.from(inner);
    final message = TeamMessage.fromJson(map, fallbackConversationId: _conversationId);
    if (_conversationId != null && message.conversationId != _conversationId) return;
    if (_messages.any((m) => m.id == message.id)) return;
    if (message.sender == null && message.senderId != null) {
      _sync();
      return;
    }
    if (message.senderId == _me &&
        _messages.any((m) => m.isPending && m.content == message.content && m.senderId == _me)) {
      return;
    }
    setState(() => _messages = [..._messages, message]);
    _scrollToNewest();
  }

  void _onInputChanged() {
    final text = _input.text;
    final cursor = _input.selection.baseOffset;
    final end = cursor < 0 || cursor > text.length ? text.length : cursor;
    final match = RegExp(r'@(\w*)$').firstMatch(text.substring(0, end));
    final active = match != null;
    final query = match?.group(1)?.toLowerCase() ?? '';
    if (active != _mentionActive || query != _mentionQuery) {
      setState(() {
        _mentionActive = active;
        _mentionQuery = query;
      });
    }
  }

  List<String> get _mentionOptions {
    if (!_mentionActive) return const [];
    final options = <String>[];
    if (_isLead) {
      for (final keyword in const ['all', 'team']) {
        if (keyword.startsWith(_mentionQuery)) options.add(keyword);
      }
    }
    final seen = <String>{};
    for (final member in _mentionPool) {
      if (member.userId == _me) continue;
      final first = member.name.trim().split(RegExp(r'\s+')).first;
      if (first.isEmpty) continue;
      if (!first.toLowerCase().startsWith(_mentionQuery)) continue;
      if (seen.add(first.toLowerCase())) options.add(first);
    }
    return options.take(8).toList();
  }

  void _applyMention(String name) {
    final text = _input.text;
    final cursor = _input.selection.baseOffset;
    final end = cursor < 0 || cursor > text.length ? text.length : cursor;
    final head = text.substring(0, end).replaceFirst(RegExp(r'@\w*$'), '@$name ');
    final tail = text.substring(end);
    _input.value = TextEditingValue(
      text: '$head$tail',
      selection: TextSelection.collapsed(offset: head.length),
    );
  }

  void _scrollToNewest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String _tempId() => 'tmp_${DateTime.now().microsecondsSinceEpoch}_${_tempCounter++}';

  static const _mimeTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'bmp': 'image/bmp',
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'zip': 'application/zip',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
  };

  String _mimeFor(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
    return _mimeTypes[ext] ?? 'application/octet-stream';
  }

  TeamMessage _tempMessage({required String content, String? localPath, String? fileName, int? fileSize}) {
    final me = _mentionPool.where((m) => m.userId == _me);
    final name = me.isNotEmpty ? me.first.name : 'You';
    return TeamMessage(
      id: _tempId(),
      conversationId: _conversationId ?? '',
      senderId: _me,
      content: content,
      fileType: fileName == null ? null : _mimeFor(fileName),
      fileName: fileName,
      fileSize: fileSize,
      createdAt: DateTime.now(),
      sender: TeamMessageSender(id: _me, name: name),
      status: localPath != null ? TeamMessageStatus.uploading : TeamMessageStatus.sending,
      localPath: localPath,
    );
  }

  void _update(String id, TeamMessage Function(TeamMessage) change) {
    if (!mounted) return;
    final i = _messages.indexWhere((m) => m.id == id);
    if (i == -1) return;
    setState(() => _messages[i] = change(_messages[i]));
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    final temp = _tempMessage(content: text);
    setState(() => _messages = [..._messages, temp]);
    _scrollToNewest();
    await _deliver(temp.id);
  }

  Future<void> _deliver(String tempId) async {
    final index = _messages.indexWhere((m) => m.id == tempId);
    if (index == -1) return;
    var message = _messages[index];

    if (message.localPath != null && (message.fileUrl == null || message.fileUrl!.isEmpty)) {
      _update(tempId, (m) => m.copyWith(status: TeamMessageStatus.uploading, uploadProgress: 0));
      var last = 0.0;
      try {
        final res = await UploadService.instance.upload(
          path: message.localPath!,
          fileName: message.fileName ?? 'file',
          onProgress: (p) {
            if (p - last >= 0.02 || p >= 1) {
              last = p;
              _update(tempId, (m) => m.copyWith(uploadProgress: p));
            }
          },
        );
        _update(tempId, (m) => m.copyWith(fileUrl: res.url));
      } catch (e) {
        _update(tempId, (m) => m.copyWith(status: TeamMessageStatus.failed));
        if (mounted) orgToast(context, errorText(e), error: true);
        return;
      }
    }

    final current = _messages.indexWhere((m) => m.id == tempId);
    if (current == -1) return;
    message = _messages[current];
    _update(tempId, (m) => m.copyWith(status: TeamMessageStatus.sending));

    try {
      final sent = await _repo.sendTeamMessage(
        widget.organization.id,
        widget.team.id,
        content: message.content,
        fileUrl: message.fileUrl,
        fileType: message.fileType,
        fileName: message.fileName,
        fileSize: message.fileSize,
      );
      if (!mounted) return;
      setState(() {
        final already = _messages.any((m) => m.id == sent.id);
        final i = _messages.indexWhere((m) => m.id == tempId);
        if (i == -1) return;
        if (already) {
          _messages.removeAt(i);
        } else {
          _messages[i] = sent;
        }
        _messages = List.of(_messages);
      });
    } catch (e) {
      _update(tempId, (m) => m.copyWith(status: TeamMessageStatus.failed));
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: orgCard,
      shape: orgSheetShape,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in const [
              ('camera', Icons.photo_camera_outlined, 'Camera'),
              ('gallery', Icons.photo_library_outlined, 'Photo library'),
              ('file', Icons.insert_drive_file_outlined, 'File'),
            ])
              ListTile(
                leading: Icon(option.$2, color: orgTeal),
                title: Text(option.$3, style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(sheetContext, option.$1),
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
      final caption = _input.text.trim();
      _input.clear();
      final temp = _tempMessage(content: caption, localPath: path, fileName: name, fileSize: size);
      setState(() => _messages = [..._messages, temp]);
      _scrollToNewest();
      await _deliver(temp.id);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _togglePin(TeamMessage message) async {
    try {
      final pinned = await _repo.toggleTeamMessagePin(
        widget.organization.id,
        widget.team.id,
        message.id,
      );
      _update(message.id, (m) => m.copyWith(isPinned: pinned));
      if (mounted) orgToast(context, pinned ? 'Message pinned' : 'Message unpinned');
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _delete(TeamMessage message) async {
    final ok = await orgConfirm(
      context,
      title: 'Delete message',
      body: 'Delete this message for everyone?',
      action: 'Delete',
    );
    if (!ok) return;
    try {
      await _repo.deleteTeamMessage(widget.organization.id, widget.team.id, message.id);
      if (!mounted) return;
      setState(() => _messages = _messages.where((m) => m.id != message.id).toList());
      orgToast(context, 'Message deleted');
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  void _discard(TeamMessage message) {
    setState(() => _messages = _messages.where((m) => m.id != message.id).toList());
  }

  Future<void> _showActions(TeamMessage message) async {
    if (message.isSystem) return;
    final mine = message.senderId == _me;
    final actions = <(String, IconData, String, Color)>[];

    if (message.status == TeamMessageStatus.failed) {
      actions.add(('retry', Icons.refresh_rounded, 'Retry', Colors.white));
      actions.add(('discard', Icons.delete_outline_rounded, 'Discard', const Color(0xFFEF4444)));
    } else if (!message.isPending) {
      if (message.content.isNotEmpty) {
        actions.add(('copy', Icons.copy_rounded, 'Copy text', Colors.white));
      }
      if (_isLead) {
        actions.add((
          'pin',
          message.isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
          message.isPinned ? 'Unpin message' : 'Pin message',
          Colors.white,
        ));
      }
      if (mine || _isLead) {
        actions.add(('delete', Icons.delete_outline_rounded, 'Delete message', const Color(0xFFEF4444)));
      }
    }
    if (actions.isEmpty) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: orgCard,
      shape: orgSheetShape,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in actions)
              ListTile(
                leading: Icon(action.$2, color: action.$4),
                title: Text(action.$3, style: TextStyle(color: action.$4)),
                onTap: () => Navigator.pop(sheetContext, action.$1),
              ),
          ],
        ),
      ),
    );

    switch (choice) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.content));
        if (mounted) orgToast(context, 'Copied');
      case 'pin':
        await _togglePin(message);
      case 'delete':
        await _delete(message);
      case 'retry':
        await _deliver(message.id);
      case 'discard':
        _discard(message);
    }
  }

  Future<void> _showPinned() async {
    final pinned = _messages.where((m) => m.isPinned).toList().reversed.toList();
    if (pinned.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: orgCard,
      shape: orgSheetShape,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.6),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Pinned messages',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              for (final m in pinned)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: orgField,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: orgBorder),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.sender?.name ?? 'System',
                              style: const TextStyle(color: orgTeal, fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              m.content.isNotEmpty ? m.content : (m.fileName ?? 'Attachment'),
                              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                      if (_isLead)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.push_pin_outlined, color: orgMuted, size: 20),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _togglePin(m);
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMeetings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeetingsListScreen.team(organization: widget.organization, team: widget.team),
      ),
    );
  }

  void _openJira() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeamJiraBoardScreen(organization: widget.organization, team: widget.team),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        actions: [
          IconButton(
            tooltip: 'Team meetings',
            onPressed: _openMeetings,
            icon: const Icon(Icons.videocam_outlined),
          ),
          IconButton(
            tooltip: 'Jira tickets',
            onPressed: _openJira,
            icon: const Icon(Icons.view_kanban_outlined),
          ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.team.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              '$_memberCount ${_memberCount == 1 ? 'member' : 'members'} · ${widget.organization.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: orgMuted),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _pinnedBanner(),
          Expanded(child: _body()),
          _mentionBar(),
          _composer(),
        ],
      ),
    );
  }

  Widget _pinnedBanner() {
    final pinned = _messages.where((m) => m.isPinned).toList();
    if (pinned.isEmpty) return const SizedBox.shrink();
    final latest = pinned.last;
    return InkWell(
      onTap: _showPinned,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          color: orgCard,
          border: Border(bottom: BorderSide(color: orgBorder)),
        ),
        child: Row(
          children: [
            const Icon(Icons.push_pin_rounded, color: orgTeal, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                latest.content.isNotEmpty ? latest.content : (latest.fileName ?? 'Attachment'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            if (pinned.length > 1)
              Text('+${pinned.length - 1}', style: const TextStyle(color: orgTeal, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: orgTeal));
    }
    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: orgMuted, size: 42),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _load,
                child: const Text('Retry', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text('No messages yet. Say hello to the team!', style: TextStyle(color: orgMuted)),
      );
    }
    final reversed = _messages.reversed.toList();
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: reversed.length,
      itemBuilder: (context, index) => _messageItem(reversed[index]),
    );
  }

  Widget _messageItem(TeamMessage message) {
    if (message.isSystem) return _systemBubble(message);
    final mine = message.senderId == _me;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showActions(message),
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: mine ? orgAccent : orgCard,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
            border: Border.all(color: message.isPinned ? orgTeal.withAlpha(140) : orgBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    message.sender?.name ?? '',
                    style: const TextStyle(color: orgTeal, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              if (message.hasAttachment) _attachment(message),
              if (message.hasAttachment && message.content.isNotEmpty) const SizedBox(height: 6),
              if (message.content.isNotEmpty) _text(message.content),
              const SizedBox(height: 4),
              _footer(message, mine),
            ],
          ),
        ),
      ),
    );
  }

  Widget _text(String content) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'@\w+');
    var cursor = 0;
    for (final match in pattern.allMatches(content)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: content.substring(cursor, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: const TextStyle(color: orgTeal, fontWeight: FontWeight.w700),
      ));
      cursor = match.end;
    }
    if (cursor < content.length) spans.add(TextSpan(text: content.substring(cursor)));
    return Text.rich(
      TextSpan(children: spans),
      style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35),
    );
  }

  Widget _footer(TeamMessage message, bool mine) {
    final time = MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(message.createdAt));
    Widget status = const SizedBox.shrink();
    if (message.status == TeamMessageStatus.uploading || message.status == TeamMessageStatus.sending) {
      status = const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white70),
      );
    } else if (message.status == TeamMessageStatus.failed) {
      status = const Icon(Icons.error_outline_rounded, color: Color(0xFFFF8A80), size: 14);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (message.isPinned) ...[
          const Icon(Icons.push_pin_rounded, color: orgTeal, size: 12),
          const SizedBox(width: 4),
        ],
        Text(time, style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
        if (mine) ...[const SizedBox(width: 6), status],
      ],
    );
  }

  Widget _attachment(TeamMessage message) {
    final uploading = message.status == TeamMessageStatus.uploading;
    if (message.isImage) {
      final local = message.localPath;
      final Widget image = local != null
          ? Image.file(File(local), width: 220, height: 220, fit: BoxFit.cover)
          : Image.network(
              message.fileUrl ?? '',
              width: 220,
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => const SizedBox(
                width: 220,
                height: 140,
                child: Center(child: Icon(Icons.broken_image_outlined, color: orgMuted, size: 32)),
              ),
            );
      return GestureDetector(
        onTap: uploading || message.fileUrl == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ImageViewerScreen(url: message.fileUrl!)),
                ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            alignment: Alignment.center,
            children: [
              image,
              if (uploading)
                Positioned.fill(
                  child: Container(
                    color: Colors.black54,
                    child: Center(
                      child: CircularProgressIndicator(
                        value: message.uploadProgress > 0 ? message.uploadProgress : null,
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: uploading || message.fileUrl == null ? null : () => _openFile(message.fileUrl!),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
            child: uploading
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      value: message.uploadProgress > 0 ? message.uploadProgress : null,
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.insert_drive_file_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.fileName ?? 'Attachment',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, decoration: TextDecoration.underline),
                ),
                if (message.fileSize != null)
                  Text(
                    _sizeLabel(message.fileSize!),
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _openFile(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) orgToast(context, 'Could not open this file', error: true);
  }

  Widget _systemBubble(TeamMessage message) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: orgField,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: orgBorder),
        ),
        child: Text(
          message.content,
          textAlign: TextAlign.center,
          style: const TextStyle(color: orgMuted, fontSize: 12),
        ),
      ),
    );
  }

  Widget _mentionBar() {
    final options = _mentionOptions;
    if (options.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        color: orgCard,
        border: Border(top: BorderSide(color: orgBorder)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: options.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) => ActionChip(
          backgroundColor: orgField,
          side: const BorderSide(color: orgBorder),
          label: Text('@${options[index]}', style: const TextStyle(color: orgTeal, fontSize: 12.5)),
          onPressed: () => _applyMention(options[index]),
        ),
      ),
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: const BoxDecoration(
        color: orgCard,
        border: Border(top: BorderSide(color: orgBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: _attach,
              icon: const Icon(Icons.attach_file_rounded, color: orgMuted),
            ),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Message ${widget.team.name}',
                  hintStyle: const TextStyle(color: orgMuted),
                  filled: true,
                  fillColor: orgField,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              decoration: const BoxDecoration(color: orgAccent, shape: BoxShape.circle),
              child: IconButton(
                onPressed: _sendText,
                icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
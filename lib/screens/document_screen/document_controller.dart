import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/auth_service.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/document_repository.dart';
import 'package:quorum_app/api/socket_service.dart';
import 'package:quorum_app/models/document_content.dart';
import 'package:quorum_app/models/document_models.dart';

enum DocumentStatus { loading, ready, error }

class DocumentEvents {
  DocumentEvents._();
  static const join = 'document:join';
  static const leave = 'document:leave';
  static const update = 'document:update';
  static const updated = 'document:updated';
  static const cursor = 'document:cursor';
  static const usersList = ['document:users_list', 'document:users-list'];
  static const userJoined = ['document:user_joined', 'document:user-joined'];
  static const userLeft = ['document:user_left', 'document:user-left'];
  static const cursorMoved = ['document:cursor_moved', 'document:cursor-moved'];
  static const whiteboardEmbedded = ['document:whiteboard_embedded', 'document:whiteboard-embedded'];
}

String _blockSignature(DocBlock b) => jsonEncode(DocContent.serialize([b]));

class DocumentController extends ChangeNotifier {
  DocumentController({required this.documentId, this.meetingCode});

  final String documentId;
  final String? meetingCode;
  final DocumentRepository _repo = DocumentRepository.instance;
  final SocketService _socket = SocketService.instance;
  final StreamController<String> _notices = StreamController<String>.broadcast();
  final Map<String, ActiveDocumentUser> _users = {};
  final Map<String, DocumentCursor> _cursors = {};

  DocumentStatus status = DocumentStatus.loading;
  String? error;
  QuorumDoc? doc;
  List<DocBlock> blocks = [];
  bool offline = false;
  int remoteRevision = 0;
  Timer? _emitTimer;
  List<String> _base = [];
  String _lastSent = '';
  bool _dirty = false;
  bool _needsResend = false;
  bool _joinAttempted = false;
  bool _disposed = false;
  bool _unsaved = false;
  Timer? _cursorTimer;
  Map<String, dynamic>? _pendingCursor;
  String _lastCursorKey = '';

  Stream<String> get notices => _notices.stream;
  DocumentAccess get access => doc?.accessFor(CurrentUser.id) ?? DocumentAccess.read;
  bool get canEdit => access != DocumentAccess.read;

  List<ActiveDocumentUser> get otherUsers {
    final seen = <String>{};
    final out = <ActiveDocumentUser>[];
    for (final u in _users.values) {
      if (u.userId == CurrentUser.id) continue;
      if (seen.add(u.userId)) out.add(u);
    }
    return out;
  }

  Map<String, DocumentCursor> get remoteCursors => Map.unmodifiable(_cursors);

  List<DocumentCursor> cursorsOnLine(int line) => [
        for (final c in _cursors.values)
          if (c.line == line) c,
      ];

  void _touch() {
    if (!_disposed) notifyListeners();
  }

  void _notice(String message) {
    if (!_disposed && !_notices.isClosed) _notices.add(message);
  }

  Future<void> start() async {
    try {
      if (!CurrentUser.isLoaded) {
        try {
          CurrentUser.setFromProfile(await AuthService.instance.getUserProfile());
        } catch (_) {}
      }
      final loaded = await _repo.get(documentId, meetingCode: meetingCode);
      if (_disposed) return;
      doc = loaded;
      blocks = DocContent.parse(loaded.content);
      _snapshot();
      status = DocumentStatus.ready;
      offline = !_socket.isConnected;
      _touch();
      _bind();
      unawaited(_join());
    } catch (e) {
      if (_disposed) return;
      status = DocumentStatus.error;
      error = errorText(e);
      _touch();
    }
  }

  Future<void> retry() {
    status = DocumentStatus.loading;
    error = null;
    _touch();
    return start();
  }

  void _snapshot() {
    _base = blocks.map(_blockSignature).toList();
    _lastSent = jsonEncode(DocContent.serialize(blocks));
  }

  void _bind() {
    _socket.on(DocumentEvents.update, _onUpdate);
    _socket.on(DocumentEvents.updated, _onUpdate);
    _socket.on(DocumentEvents.cursorMoved[0], _onCursorMoved);
    _socket.on(DocumentEvents.cursorMoved[1], _onCursorMoved);
    _socket.on(DocumentEvents.usersList[0], _onUsersList);
    _socket.on(DocumentEvents.usersList[1], _onUsersList);
    _socket.on(DocumentEvents.userJoined[0], _onUserJoined);
    _socket.on(DocumentEvents.userJoined[1], _onUserJoined);
    _socket.on(DocumentEvents.userLeft[0], _onUserLeft);
    _socket.on(DocumentEvents.userLeft[1], _onUserLeft);
    _socket.on(DocumentEvents.whiteboardEmbedded[0], _onWhiteboardEmbedded);
    _socket.on(DocumentEvents.whiteboardEmbedded[1], _onWhiteboardEmbedded);
    _socket.addConnectionListener(_onConnection);
  }

  void _unbind() {
    _socket.off(DocumentEvents.update, _onUpdate);
    _socket.off(DocumentEvents.updated, _onUpdate);
    _socket.off(DocumentEvents.cursorMoved[0], _onCursorMoved);
    _socket.off(DocumentEvents.cursorMoved[1], _onCursorMoved);
    _socket.off(DocumentEvents.usersList[0], _onUsersList);
    _socket.off(DocumentEvents.usersList[1], _onUsersList);
    _socket.off(DocumentEvents.userJoined[0], _onUserJoined);
    _socket.off(DocumentEvents.userJoined[1], _onUserJoined);
    _socket.off(DocumentEvents.userLeft[0], _onUserLeft);
    _socket.off(DocumentEvents.userLeft[1], _onUserLeft);
    _socket.off(DocumentEvents.whiteboardEmbedded[0], _onWhiteboardEmbedded);
    _socket.off(DocumentEvents.whiteboardEmbedded[1], _onWhiteboardEmbedded);
    _socket.removeConnectionListener(_onConnection);
  }

  void _onConnection(bool connected) {
    if (_disposed) return;
    offline = !connected;
    _touch();
    if (connected && _joinAttempted) _join(rejoin: true);
  }

  Future<void> _join({bool rejoin = false}) async {
    _joinAttempted = true;
    await _socket.ensureConnected();
    final connected = await _socket.waitConnected();
    if (_disposed) return;
    if (!connected) {
      offline = true;
      _touch();
      return;
    }
    _socket.emitAck(DocumentEvents.join, {'documentId': documentId}, (res) {
      if (_disposed) return;
      if (res == null) {
        if (!rejoin) _notice('Live collaboration is unavailable. Changes may not sync right now.');
        _flushPending();
        return;
      }
      if (res['success'] == false) {
        _notice(res['message']?.toString() ?? 'Could not join the live session.');
        _flushPending();
        return;
      }
      offline = false;
      _applyJoin(res['data']);
    });
  }

  void _applyJoin(dynamic raw) {
    final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    _users.clear();
    for (final u in ActiveDocumentUser.listFrom(raw is List ? raw : (data['activeUsers'] ?? data['users']))) {
      _users[u.socketId ?? u.userId] = u;
    }
    final version = int.tryParse((data['version'] ?? '').toString());
    final pending = _dirty || _needsResend;
    if (!pending && data['content'] != null && version != null && version > (doc?.version ?? 0)) {
      _adoptRemote(data['content']);
      doc = doc?.copyWith(version: version);
    }
    _touch();
    _flushPending();
  }

  void _flushPending() {
    if (!_needsResend) return;
    _needsResend = false;
    _sendNow(force: true);
  }

  void _onUsersList(dynamic raw) {
    final d = asMap(raw);
    if (d == null || _disposed) return;
    final id = (d['documentId'] ?? '').toString();
    if (id.isNotEmpty && id != documentId) return;
    _users.clear();
    for (final u in ActiveDocumentUser.listFrom(d['users'] ?? d['activeUsers'])) {
      _users[u.socketId ?? u.userId] = u;
    }
    _pruneCursors();
    _touch();
  }

  void _pruneCursors() {
    final present = _users.values.map((u) => u.userId).toSet();
    _cursors.removeWhere((userId, _) => !present.contains(userId));
  }

  void _onUserJoined(dynamic raw) {
    final d = asMap(raw);
    if (d == null || _disposed) return;
    final active = d['activeUsers'];
    if (active is List) {
      _users.clear();
      for (final u in ActiveDocumentUser.listFrom(active)) {
        _users[u.socketId ?? u.userId] = u;
      }
    } else {
      final u = ActiveDocumentUser.tryParse(d);
      if (u != null) _users[u.socketId ?? u.userId] = u;
    }
    _touch();
  }

  void _onUserLeft(dynamic raw) {
    final d = asMap(raw);
    if (d == null || _disposed) return;
    final active = d['activeUsers'];
    if (active is List) {
      _users.clear();
      for (final u in ActiveDocumentUser.listFrom(active)) {
        _users[u.socketId ?? u.userId] = u;
      }
    } else {
      final u = ActiveDocumentUser.tryParse(d);
      if (u != null) {
        _users.remove(u.socketId ?? u.userId);
        _users.removeWhere((_, x) => x.userId == u.userId && (u.socketId == null || x.socketId == u.socketId));
        if (!_users.values.any((x) => x.userId == u.userId)) _cursors.remove(u.userId);
      }
    }
    _pruneCursors();
    _touch();
  }

  void _onCursorMoved(dynamic raw) {
    final d = asMap(raw);
    if (d == null || _disposed) return;
    final id = (d['documentId'] ?? '').toString();
    if (id.isNotEmpty && id != documentId) return;
    final cursor = DocumentCursor.tryParse(d);
    if (cursor == null || cursor.userId == CurrentUser.id) return;
    _cursors[cursor.userId] = cursor;
    _touch();
  }

  void _onWhiteboardEmbedded(dynamic raw) {
    final d = asMap(raw);
    if (d == null || _disposed) return;
    final id = (d['documentId'] ?? '').toString();
    if (id.isNotEmpty && id != documentId) return;
    final boardId = (d['whiteboardId'] ?? '').toString();
    if (boardId.isEmpty) return;
    final embed = asMap(d['embedData']);
    final name = (embed?['name'] ?? d['name'] ?? 'Whiteboard').toString();
    _addWhiteboard(boardId, name);
  }

  void _addWhiteboard(String boardId, String name) {
    final current = doc;
    if (current == null || current.whiteboards.any((b) => b.whiteboardId == boardId)) return;
    doc = current.copyWith(
      whiteboards: [
        ...current.whiteboards,
        EmbeddedWhiteboard(id: boardId, whiteboardId: boardId, name: name),
      ],
    );
    _touch();
  }

  void embedWhiteboard(String boardId, String name) {
    if (!canEdit || _disposed) return;
    _addWhiteboard(boardId, name);
    _socket.emit(DocumentEvents.whiteboardEmbedded[0], {
      'documentId': documentId,
      'whiteboardId': boardId,
      'embedData': {'name': name},
    });
  }

  void sendCursor(int line, int ch, {int? selectionStart, int? selectionEnd}) {
    if (_disposed || !_joinAttempted || !_socket.isConnected) return;
    final hasSelection = selectionStart != null && selectionEnd != null && selectionStart != selectionEnd;
    final key = '$line:$ch:${hasSelection ? '$selectionStart-$selectionEnd' : ''}';
    if (key == _lastCursorKey) return;
    _lastCursorKey = key;
    _pendingCursor = {
      'documentId': documentId,
      'cursor': {
        'line': line,
        'ch': ch,
        if (hasSelection) 'selection': {'start': selectionStart, 'end': selectionEnd},
      },
    };
    if (_cursorTimer != null) return;
    _flushCursor();
    _cursorTimer = Timer(const Duration(milliseconds: 60), () {
      _cursorTimer = null;
      if (_pendingCursor != null) _flushCursor();
    });
  }

  void _flushCursor() {
    final payload = _pendingCursor;
    _pendingCursor = null;
    if (payload == null || _disposed) return;
    _socket.emit(DocumentEvents.cursor, payload);
  }

  void _onUpdate(dynamic raw) {
    final d = asMap(raw);
    if (d == null || _disposed) return;
    final id = (d['documentId'] ?? d['id'] ?? '').toString();
    if (id.isNotEmpty && id != documentId) return;
    final from = (d['userId'] ?? d['updatedBy'] ?? '').toString();
    if (from.isNotEmpty && from == CurrentUser.id) return;
    final title = d['title']?.toString();
    if (title != null && title.isNotEmpty && title != doc?.title) {
      doc = doc?.copyWith(title: title);
      _touch();
    }
    final content = d['content'] ?? (d['document'] is Map ? (d['document'] as Map)['content'] : null);
    if (content == null) return;
    final version = int.tryParse((d['version'] ?? '').toString());
    if (version != null) doc = doc?.copyWith(version: version);
    _adoptRemote(content);
  }

  void _adoptRemote(dynamic content) {
    final remote = DocContent.parse(content);
    final remoteSigs = remote.map(_blockSignature).toList();
    final pending = _dirty || _needsResend;
    if (!pending) {
      blocks = remote;
      _base = remoteSigs;
      _lastSent = jsonEncode(DocContent.serialize(blocks));
      remoteRevision++;
      _touch();
      return;
    }
    if (remote.length == blocks.length && _base.length == blocks.length) {
      final merged = <DocBlock>[];
      for (var i = 0; i < blocks.length; i++) {
        merged.add(_blockSignature(blocks[i]) == _base[i] ? remote[i] : blocks[i]);
      }
      blocks = merged;
      _base = remoteSigs;
      remoteRevision++;
      _touch();
    }
  }

  void commit(List<DocBlock> next) {
    blocks = next;
    localChanged();
  }

  void localChanged() {
    if (!canEdit || _disposed) return;
    _dirty = true;
    _unsaved = true;
    _emitTimer ??= Timer(const Duration(milliseconds: 120), () {
      _emitTimer = null;
      _sendNow();
    });
  }

  void _sendNow({bool force = false}) {
    if (_disposed && !force) return;
    _dirty = false;
    final content = DocContent.serialize(blocks);
    final signature = jsonEncode(content);
    if (!force && signature == _lastSent) {
      _base = blocks.map(_blockSignature).toList();
      return;
    }
    _lastSent = signature;
    _base = blocks.map(_blockSignature).toList();
    if (!_socket.isConnected) {
      _needsResend = true;
      return;
    }
    _socket.emitAck(DocumentEvents.update, {'documentId': documentId, 'content': content}, (res) {
      if (_disposed) return;
      if (res != null && res['success'] == false) {
        _notice(res['message']?.toString() ?? 'Your last change could not be saved.');
      }
    });
  }

  Future<void> rename(String title) async {
    await _repo.rename(documentId, title);
    doc = doc?.copyWith(title: title);
    _touch();
    _socket.emit(DocumentEvents.update, {'documentId': documentId, 'title': title});
  }

  Future<void> persist() async {
    if (!_unsaved || !canEdit) return;
    final content = DocContent.serialize(blocks);
    try {
      await _repo.saveContent(documentId, content);
      _unsaved = false;
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_dirty && canEdit) {
      _emitTimer?.cancel();
      _emitTimer = null;
      _sendNow(force: true);
    }
    if (meetingCode != null && _unsaved && canEdit) {
      unawaited(_repo.saveContent(documentId, DocContent.serialize(blocks)).catchError((_) {}));
    }
    _emitTimer?.cancel();
    _cursorTimer?.cancel();
    _disposed = true;
    _unbind();
    if (_joinAttempted && _socket.isConnected) _socket.emit(DocumentEvents.leave, {'documentId': documentId});
    _notices.close();
    super.dispose();
  }
}
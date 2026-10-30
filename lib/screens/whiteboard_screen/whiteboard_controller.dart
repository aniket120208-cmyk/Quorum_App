import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/socket_service.dart';
import 'package:quorum_app/models/whiteboard_models.dart';

enum WhiteboardStatus { joining, ready, error }
enum WhiteboardTool { pan, select, pen, eraser, text, shape, emoji }
enum ShapeKind { rectangle, ellipse, diamond, triangle, line, arrow }

class WhiteboardTextResult {
  const WhiteboardTextResult({required this.text, required this.fontSize, required this.color});
  final String text;
  final double fontSize;
  final Color color;
}

class _PendingOp {
  _PendingOp(this.event, this.data);
  final String event;
  final Map<String, dynamic> data;
}

class _UndoAction {
  _UndoAction({
    this.added = const [],
    this.removed = const [],
    this.before = const [],
    this.after = const [],
  });

  final List<WhiteboardElement> added;
  final List<WhiteboardElement> removed;
  final List<WhiteboardElement> before;
  final List<WhiteboardElement> after;
}

class WhiteboardController extends ChangeNotifier {
  WhiteboardController({required this.boardId, this.meetingCode});

  final String boardId;
  final String? meetingCode;

  final SocketService _socket = SocketService.instance;
  final Map<String, WhiteboardElement> _elements = {};
  final Map<String, WhiteboardPresence> _users = {};
  final Map<String, RemoteCursor> _cursors = {};
  final List<_PendingOp> _pending = [];
  final List<_UndoAction> _undoStack = [];
  final List<_UndoAction> _redoStack = [];
  final StreamController<String> _notices = StreamController<String>.broadcast();

  List<WhiteboardElement>? _cache;
  Timer? _pruneTimer;
  DateTime _lastCursorSent = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;
  bool _joined = false;
  int _idCounter = 0;

  WhiteboardStatus status = WhiteboardStatus.joining;
  String? error;
  bool offline = false;
  WhiteboardViewState viewState = const WhiteboardViewState();
  WhiteboardTool tool = WhiteboardTool.pen;
  Color color = const Color(0xFF0F172A);
  double strokeWidth = 3;
  String? selectedId;
  ShapeKind shape = ShapeKind.rectangle;
  bool fillShapes = false;
  String emoji = '😀';

  List<Offset> _livePoints = [];
  List<WhiteboardElement> _erasing = [];
  WhiteboardElement? _moveOrigin;
  Offset _moveDelta = Offset.zero;
  Offset? _shapeStart;
  String? _shapeId;
  WhiteboardElement? liveShape;

  Stream<String> get notices => _notices.stream;
  List<Offset> get livePoints => _livePoints;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get isEmpty => _elements.isEmpty;
  List<WhiteboardPresence> get users => _users.values.toList(growable: false);
  List<RemoteCursor> get cursors => _cursors.values.toList(growable: false);
  List<WhiteboardElement> get elements => _cache ??= _elements.values.toList(growable: false);
  WhiteboardElement? get selected => selectedId == null ? null : _elements[selectedId];
  bool get isDarkCanvas {
    final bg = parseHexColor(viewState.backgroundColor) ?? Colors.white;
    return bg.computeLuminance() < 0.4;
  }

  void _touch() {
    _cache = null;
    if (!_disposed) notifyListeners();
  }

  void _notice(String message) {
    if (!_disposed && !_notices.isClosed) _notices.add(message);
  }

  String _newId() {
    _idCounter++;
    final user = CurrentUser.id.isEmpty ? 'u' : CurrentUser.id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final short = user.length > 6 ? user.substring(0, 6) : user;
    return 'el_${short}_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_$_idCounter';
  }

  Future<void> start() async {
    _attach();
    _pruneTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pruneCursors());
    await _join();
  }

  void retry() {
    status = WhiteboardStatus.joining;
    error = null;
    _touch();
    _join();
  }

  void _attach() {
    _socket.on('whiteboard:user-joined', _onUserJoined);
    _socket.on('whiteboard:user-left', _onUserLeft);
    _socket.on('whiteboard:element-updated', _onElementUpdated);
    _socket.on('whiteboard:elements-changed', _onElementsChanged);
    _socket.on('whiteboard:cursor-moved', _onCursorMoved);
    _socket.on('whiteboard:cleared', _onCleared);
    _socket.addConnectionListener(_onConnection);
  }

  void _detach() {
    _socket.off('whiteboard:user-joined', _onUserJoined);
    _socket.off('whiteboard:user-left', _onUserLeft);
    _socket.off('whiteboard:element-updated', _onElementUpdated);
    _socket.off('whiteboard:elements-changed', _onElementsChanged);
    _socket.off('whiteboard:cursor-moved', _onCursorMoved);
    _socket.off('whiteboard:cleared', _onCleared);
    _socket.removeConnectionListener(_onConnection);
  }

  void _onConnection(bool connected) {
    if (_disposed) return;
    offline = !connected;
    _touch();
    if (connected && _joined && status == WhiteboardStatus.ready) {
      _join(rejoin: true);
    }
  }

  Future<void> _join({bool rejoin = false}) async {
    if (_disposed) return;
    await _socket.ensureConnected();
    final connected = await _socket.waitConnected();
    if (_disposed) return;
    if (!connected) {
      _failJoin('Unable to connect. Check your connection and try again.', rejoin);
      return;
    }
    _socket.emitAck(
      'whiteboard:join',
      {'boardId': boardId, if (meetingCode != null) 'meetingCode': meetingCode},
      (res) {
        if (_disposed) return;
        if (res == null) {
          _failJoin('Could not join whiteboard. Try again.', rejoin);
          return;
        }
        if (res['success'] != true) {
          _failJoin(res['message']?.toString() ?? 'Could not join whiteboard', rejoin);
          return;
        }
        _applyJoin(res['data'], rejoin);
      },
    );
  }

  void _failJoin(String message, bool rejoin) {
    if (rejoin) {
      offline = true;
      _notice(message);
      _touch();
      return;
    }
    status = WhiteboardStatus.error;
    error = message;
    _touch();
  }

  void _applyJoin(dynamic raw, bool rejoin) {
    final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final content = data['content'] is Map ? Map<String, dynamic>.from(data['content']) : <String, dynamic>{};
    final serverElements = WhiteboardElement.parseList(data['elements'] ?? content['elements']);

    _elements
      ..clear()
      ..addEntries(serverElements.map((e) => MapEntry(e.id, e)));

    if (!rejoin) {
      viewState = WhiteboardViewState.fromJson(data['viewState'] ?? content['viewState']);
      color = isDarkCanvas ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    }

    _users.clear();
    final active = data['activeUsers'];
    if (active is List) {
      for (final u in active) {
        final p = WhiteboardPresence.tryParse(u);
        if (p != null) _users[p.key] = p;
      }
    }

    final queued = List<_PendingOp>.of(_pending);
    _pending.clear();
    for (final op in queued) {
      _reapply(op);
    }

    _joined = true;
    offline = false;
    status = WhiteboardStatus.ready;
    error = null;
    _touch();

    for (final op in queued) {
      _emit(op.event, op.data);
    }
  }

  void _reapply(_PendingOp op) {
    switch (op.event) {
      case 'whiteboard:draw-element':
        final el = WhiteboardElement.tryParse(op.data['element']);
        if (el != null) _elements[el.id] = el;
      case 'whiteboard:elements-change':
        for (final el in WhiteboardElement.parseList(op.data['updates'])) {
          _elements[el.id] = el;
        }
        final deletes = op.data['deletes'];
        if (deletes is List) {
          for (final id in deletes) {
            _elements.remove(id.toString());
          }
        }
      case 'whiteboard:clear':
        _elements.clear();
    }
  }

  void _emit(String event, Map<String, dynamic> data, {VoidCallback? onFailure}) {
    if (!_socket.isConnected || status != WhiteboardStatus.ready || offline) {
      _pending.add(_PendingOp(event, data));
      return;
    }
    _socket.emitAck(event, data, (res) {
      if (_disposed) return;
      if (res != null && res['success'] == false) {
        _notice(res['message']?.toString() ?? 'Your last change could not be saved.');
        onFailure?.call();
        _join(rejoin: true);
      }
    });
  }

  void _onUserJoined(dynamic raw) {
    final d = asMap(raw);
    if (d == null || _disposed) return;
    final active = d['activeUsers'];
    if (active is List) {
      _users.clear();
      for (final u in active) {
        final p = WhiteboardPresence.tryParse(u);
        if (p != null) _users[p.key] = p;
      }
    } else {
      final p = WhiteboardPresence.tryParse(d);
      if (p != null) _users[p.key] = p;
    }
    _touch();
  }

  void _onUserLeft(dynamic raw) {
    final d = asMap(raw);
    if (d == null || _disposed) return;
    final active = d['activeUsers'];
    if (active is List) {
      _users.clear();
      for (final u in active) {
        final p = WhiteboardPresence.tryParse(u);
        if (p != null) _users[p.key] = p;
      }
    } else {
      final p = WhiteboardPresence.tryParse(d);
      if (p != null) {
        _users.remove(p.key);
        _users.removeWhere((_, u) => u.socketId != null && u.socketId == p.socketId);
        _cursors.remove(p.key);
      }
    }
    _touch();
  }

  void _onElementUpdated(dynamic raw) {
    final d = asMap(raw);
    if (d == null || _disposed) return;
    final el = WhiteboardElement.tryParse(d['element']);
    if (el == null) return;
    _elements[el.id] = el;
    _touch();
  }

  void _onElementsChanged(dynamic raw) {
    final d = asMap(raw);
    if (d == null || _disposed) return;
    for (final el in WhiteboardElement.parseList(d['updates'])) {
      _elements[el.id] = el;
    }
    final deletes = d['deletes'];
    if (deletes is List) {
      for (final item in deletes) {
        final id = item is Map ? item['id']?.toString() : item?.toString();
        if (id != null) {
          _elements.remove(id);
          if (selectedId == id) selectedId = null;
        }
      }
    }
    _touch();
  }

  void _onCursorMoved(dynamic raw) {
    final d = asMap(raw);
    if (d == null || _disposed) return;
    final userId = d['userId']?.toString();
    if (userId != null && userId == CurrentUser.id) return;
    final key = userId ?? d['socketId']?.toString();
    if (key == null || key.isEmpty) return;
    final x = d['x'];
    final y = d['y'];
    if (x is! num || y is! num) return;
    _cursors[key] = RemoteCursor(
      key: key,
      name: (d['name'] ?? 'Guest').toString(),
      x: x.toDouble(),
      y: y.toDouble(),
      updatedAt: DateTime.now(),
    );
    _touch();
  }

  void _onCleared(dynamic raw) {
    if (_disposed) return;
    _elements.clear();
    selectedId = null;
    _undoStack.clear();
    _redoStack.clear();
    _touch();
  }

  void _pruneCursors() {
    if (_cursors.isEmpty) return;
    final cutoff = DateTime.now().subtract(const Duration(seconds: 6));
    final before = _cursors.length;
    _cursors.removeWhere((_, c) => c.updatedAt.isBefore(cutoff));
    if (_cursors.length != before) _touch();
  }

  void setTool(WhiteboardTool next) {
    tool = next;
    if (next != WhiteboardTool.select) selectedId = null;
    _touch();
  }

  void setShape(ShapeKind next) {
    shape = next;
    _touch();
  }

  void setFillShapes(bool next) {
    fillShapes = next;
    _touch();
  }

  void setEmoji(String next) {
    emoji = next;
    _touch();
  }

  void setColor(Color next) {
    color = next;
    _touch();
  }

  void setStrokeWidth(double next) {
    strokeWidth = next;
    _touch();
  }

  void setView({double? zoom, double? scrollX, double? scrollY}) {
    viewState = viewState.copyWith(zoom: zoom, scrollX: scrollX, scrollY: scrollY);
    _touch();
  }

  void panBy(Offset canvasDelta) {
    setView(scrollX: viewState.scrollX + canvasDelta.dx, scrollY: viewState.scrollY + canvasDelta.dy);
  }

  void resetView() {
    setView(zoom: 1, scrollX: 0, scrollY: 0);
  }

  void sendCursor(Offset p) {
    if (status != WhiteboardStatus.ready || !_socket.isConnected) return;
    final now = DateTime.now();
    if (now.difference(_lastCursorSent).inMilliseconds < 60) return;
    _lastCursorSent = now;
    _socket.emit('whiteboard:cursor-move', {'boardId': boardId, 'x': p.dx, 'y': p.dy});
  }

  void beginStroke(Offset p) {
    _livePoints = [p];
    sendCursor(p);
    _touch();
  }

  void addStrokePoint(Offset p) {
    if (_livePoints.isEmpty) return;
    final minDistance = 1.2 / viewState.zoom;
    if ((p - _livePoints.last).distance < minDistance) return;
    _livePoints = [..._livePoints, p];
    sendCursor(p);
    _touch();
  }

  void endStroke() {
    final pts = _livePoints;
    _livePoints = [];
    if (pts.isEmpty) {
      _touch();
      return;
    }
    final rounded = pts.map((o) => [WhiteboardElement.round(o.dx), WhiteboardElement.round(o.dy)]).toList();
    if (rounded.length == 1) {
      rounded.add([rounded.first[0] + 0.1, rounded.first[1]]);
    }
    final el = WhiteboardElement({
      'id': _newId(),
      'type': 'stroke',
      'points': rounded,
      'strokeColor': colorToHex(color),
      'strokeWidth': strokeWidth,
    });
    _addLocal(el);
  }

  void addText(Offset p, WhiteboardTextResult result) {
    final value = result.text.trim();
    if (value.isEmpty) return;
    final el = WhiteboardElement({
      'id': _newId(),
      'type': 'text',
      'x': WhiteboardElement.round(p.dx),
      'y': WhiteboardElement.round(p.dy),
      'text': value,
      'fontSize': result.fontSize,
      'color': colorToHex(result.color),
    });
    _addLocal(el);
  }

  void updateText(String id, WhiteboardTextResult result) {
    final old = _elements[id];
    final value = result.text.trim();
    if (old == null || old.type != 'text' || value.isEmpty) return;
    final json = Map<String, dynamic>.from(old.json)
      ..['text'] = value
      ..['fontSize'] = result.fontSize
      ..['color'] = colorToHex(result.color);
    final next = WhiteboardElement(json);
    _elements[id] = next;
    _record(_UndoAction(before: [old], after: [next]));
    _touch();
    _emit('whiteboard:elements-change', {
      'boardId': boardId,
      'updates': [next.toJson()],
      'deletes': <String>[],
    });
  }

  void placeEmoji(Offset p) {
    final size = 28 + strokeWidth * 4;
    final el = WhiteboardElement({
      'id': _newId(),
      'type': 'text',
      'x': WhiteboardElement.round(p.dx - size * 0.6),
      'y': WhiteboardElement.round(p.dy - size * 0.6),
      'text': emoji,
      'fontSize': size,
      'color': colorToHex(color),
    });
    _addLocal(el);
  }

  WhiteboardElement _buildShape(String id, Offset a, Offset b) {
    final hex = colorToHex(color);
    if (shape == ShapeKind.line || shape == ShapeKind.arrow) {
      return WhiteboardElement({
        'id': id,
        'type': shape.name,
        'points': [
          [WhiteboardElement.round(a.dx), WhiteboardElement.round(a.dy)],
          [WhiteboardElement.round(b.dx), WhiteboardElement.round(b.dy)],
        ],
        'strokeColor': hex,
        'strokeWidth': strokeWidth,
      });
    }
    final rect = Rect.fromPoints(a, b);
    return WhiteboardElement({
      'id': id,
      'type': shape.name,
      'x': WhiteboardElement.round(rect.left),
      'y': WhiteboardElement.round(rect.top),
      'width': WhiteboardElement.round(rect.width),
      'height': WhiteboardElement.round(rect.height),
      'strokeColor': hex,
      'strokeWidth': strokeWidth,
      'fillColor': fillShapes ? hex : 'transparent',
    });
  }

  void beginShape(Offset p) {
    _shapeStart = p;
    _shapeId = _newId();
    liveShape = _buildShape(_shapeId!, p, p);
    sendCursor(p);
    _touch();
  }

  void updateShape(Offset p) {
    final start = _shapeStart;
    final id = _shapeId;
    if (start == null || id == null) return;
    liveShape = _buildShape(id, start, p);
    sendCursor(p);
    _touch();
  }

  void endShape() {
    final start = _shapeStart;
    final id = _shapeId;
    var el = liveShape;
    _shapeStart = null;
    _shapeId = null;
    liveShape = null;
    if (start == null || id == null || el == null) {
      _touch();
      return;
    }
    final isLine = el.type == 'line' || el.type == 'arrow';
    final minSize = 4 / viewState.zoom;
    final tiny = isLine
        ? (el.points.last - el.points.first).distance < minSize
        : el.width < minSize && el.height < minSize;
    if (tiny) {
      final extent = isLine ? const Offset(110, 0) : const Offset(110, 80);
      el = _buildShape(id, start, start + extent);
    }
    _addLocal(el);
  }

  void _addLocal(WhiteboardElement el) {
    _elements[el.id] = el;
    _record(_UndoAction(added: [el]));
    _touch();
    _emit('whiteboard:draw-element', {'boardId': boardId, 'element': el.toJson()});
  }

  void cancelGesture() {
    _livePoints = [];
    _shapeStart = null;
    _shapeId = null;
    liveShape = null;
    if (_moveOrigin != null) {
      _elements[_moveOrigin!.id] = _moveOrigin!;
      _moveOrigin = null;
      _moveDelta = Offset.zero;
    }
    if (_erasing.isNotEmpty) {
      for (final e in _erasing) {
        _elements[e.id] = e;
      }
      _erasing = [];
    }
    _touch();
  }

  void eraseAt(Offset p, double tolerance) {
    sendCursor(p);
    var changed = false;
    for (final el in List.of(_elements.values)) {
      if (elementHit(el, p, tolerance)) {
        _elements.remove(el.id);
        _erasing.add(el);
        changed = true;
      }
    }
    if (changed) _touch();
  }

  void endErase() {
    final removed = _erasing;
    _erasing = [];
    if (removed.isEmpty) return;
    _record(_UndoAction(removed: removed));
    _emit('whiteboard:elements-change', {
      'boardId': boardId,
      'updates': <Map<String, dynamic>>[],
      'deletes': removed.map((e) => e.id).toList(),
    });
  }

  void beginMove(Offset p, double tolerance) {
    sendCursor(p);
    WhiteboardElement? hit;
    for (final el in _elements.values) {
      if (elementHit(el, p, tolerance)) hit = el;
    }
    if (hit == null) {
      selectedId = null;
      _moveOrigin = null;
      _touch();
      return;
    }
    selectedId = hit.id;
    _moveOrigin = hit;
    _moveDelta = Offset.zero;
    _touch();
  }

  void moveBy(Offset canvasDelta) {
    final origin = _moveOrigin;
    if (origin == null) return;
    _moveDelta += canvasDelta;
    _elements[origin.id] = origin.translated(_moveDelta.dx, _moveDelta.dy);
    _touch();
  }

  void endMove() {
    final origin = _moveOrigin;
    final delta = _moveDelta;
    _moveOrigin = null;
    _moveDelta = Offset.zero;
    if (origin == null || delta == Offset.zero) return;
    final current = _elements[origin.id];
    if (current == null) return;
    _record(_UndoAction(before: [origin], after: [current]));
    _emit('whiteboard:elements-change', {
      'boardId': boardId,
      'updates': [current.toJson()],
      'deletes': <String>[],
    });
  }

  void deleteSelected() {
    final id = selectedId;
    if (id == null) return;
    final el = _elements.remove(id);
    selectedId = null;
    if (el == null) return;
    _record(_UndoAction(removed: [el]));
    _touch();
    _emit('whiteboard:elements-change', {
      'boardId': boardId,
      'updates': <Map<String, dynamic>>[],
      'deletes': [id],
    });
  }

  void _record(_UndoAction action) {
    _undoStack.add(action);
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _applyAction(_UndoAction action, {required bool inverse}) {
    final toRemove = inverse ? action.added : action.removed;
    final toAdd = inverse ? action.removed : action.added;
    final toRestore = inverse ? action.before : action.after;
    final deletes = <String>[];
    final updates = <Map<String, dynamic>>[];
    for (final el in toRemove) {
      if (_elements.remove(el.id) != null) deletes.add(el.id);
    }
    for (final el in toAdd) {
      _elements[el.id] = el;
      _emit('whiteboard:draw-element', {'boardId': boardId, 'element': el.toJson()});
    }
    for (final el in toRestore) {
      _elements[el.id] = el;
      updates.add(el.toJson());
    }
    if (selectedId != null && !_elements.containsKey(selectedId)) selectedId = null;
    _touch();
    if (deletes.isNotEmpty || updates.isNotEmpty) {
      _emit('whiteboard:elements-change', {'boardId': boardId, 'updates': updates, 'deletes': deletes});
    }
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final action = _undoStack.removeLast();
    _redoStack.add(action);
    _applyAction(action, inverse: true);
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final action = _redoStack.removeLast();
    _undoStack.add(action);
    _applyAction(action, inverse: false);
  }

  void clearAll() {
    if (_elements.isEmpty) return;
    final snapshot = Map<String, WhiteboardElement>.of(_elements);
    _elements.clear();
    selectedId = null;
    _undoStack.clear();
    _redoStack.clear();
    _touch();
    _emit(
      'whiteboard:clear',
      {'boardId': boardId},
      onFailure: () {
        _elements
          ..clear()
          ..addAll(snapshot);
        _touch();
      },
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pruneTimer?.cancel();
    if (_joined) {
      _socket.emit('whiteboard:leave', {'boardId': boardId});
    }
    _detach();
    _notices.close();
    super.dispose();
  }
}

double _segmentDistance(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSq = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSq == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lengthSq).clamp(0.0, 1.0);
  final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
  return (p - proj).distance;
}

final Map<String, TextPainter> _textCache = {};

TextPainter layoutText(WhiteboardElement e) {
  final key = '${e.id}|${e.text}|${e.fontSize}|${e.textColor.value}';
  final cached = _textCache[key];
  if (cached != null) return cached;
  if (_textCache.length > 300) _textCache.clear();
  final painter = TextPainter(
    text: TextSpan(
      text: e.text,
      style: TextStyle(color: e.textColor, fontSize: e.fontSize, height: 1.2),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 4000);
  _textCache[key] = painter;
  return painter;
}

Rect elementBounds(WhiteboardElement e) {
  switch (e.type) {
    case 'stroke':
    case 'line':
    case 'arrow':
      final pts = e.points;
      if (pts.isEmpty) return Rect.zero;
      var minX = pts.first.dx, maxX = pts.first.dx, minY = pts.first.dy, maxY = pts.first.dy;
      for (final p in pts) {
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
      }
      return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(e.strokeWidth / 2);
    case 'text':
      final tp = layoutText(e);
      return Offset(e.x, e.y) & tp.size;
    case 'rectangle':
    case 'ellipse':
    case 'diamond':
    case 'triangle':
      return Rect.fromLTWH(e.x, e.y, e.width, e.height).inflate(e.strokeWidth / 2);
    default:
      return Rect.zero;
  }
}

bool elementHit(WhiteboardElement e, Offset p, double tolerance) {
  final bounds = elementBounds(e);
  if (bounds == Rect.zero) return false;
  if (!bounds.inflate(tolerance).contains(p)) return false;
  if (e.type == 'rectangle' || e.type == 'ellipse' || e.type == 'diamond' || e.type == 'triangle') {
    if (e.fillColor != null) return true;
    return !bounds.deflate(tolerance + e.strokeWidth).contains(p);
  }
  if (e.isPointBased) {
    final pts = e.points;
    final reach = e.strokeWidth / 2 + tolerance;
    if (pts.length == 1) return (p - pts.first).distance <= reach;
    for (var i = 1; i < pts.length; i++) {
      if (_segmentDistance(p, pts[i - 1], pts[i]) <= reach) return true;
    }
    return false;
  }
  return true;
}
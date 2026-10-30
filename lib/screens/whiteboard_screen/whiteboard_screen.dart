import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'package:quorum_app/models/whiteboard_models.dart';
import 'whiteboard_controller.dart';
import 'whiteboard_emoji.dart';
import 'whiteboard_painter.dart';
import 'whiteboard_sheets.dart';

class WhiteboardScreen extends StatefulWidget {
  const WhiteboardScreen({
    super.key,
    required this.boardId,
    required this.name,
    this.meetingCode,
  });

  final String boardId;
  final String name;
  final String? meetingCode;

  @override
  State<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends State<WhiteboardScreen> {
  late final WhiteboardController _c = WhiteboardController(
    boardId: widget.boardId,
    meetingCode: widget.meetingCode,
  );
  StreamSubscription<String>? _noticeSub;

  final Map<int, Offset> _pointers = {};
  bool _multi = false;
  bool _gestureActive = false;
  bool _moved = false;
  Offset _downAt = Offset.zero;
  double _baseZoom = 1;
  double _baseDistance = 1;
  Offset _anchor = Offset.zero;

  static const _widths = <double>[2, 4, 8];

  @override
  void initState() {
    super.initState();
    _c.start();
    _noticeSub = _c.notices.listen((message) {
      if (mounted) orgToast(context, message, error: true);
    });
  }

  @override
  void dispose() {
    _noticeSub?.cancel();
    _c.dispose();
    super.dispose();
  }

  Offset _toCanvas(Offset screen) {
    final v = _c.viewState;
    return Offset(screen.dx / v.zoom - v.scrollX, screen.dy / v.zoom - v.scrollY);
  }

  double get _tolerance => 12 / _c.viewState.zoom;

  void _onDown(PointerDownEvent e) {
    if (_c.status != WhiteboardStatus.ready) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1) {
      _multi = false;
      _moved = false;
      _downAt = e.localPosition;
      _gestureActive = true;
      _begin(e.localPosition);
    } else {
      if (_gestureActive) {
        _c.cancelGesture();
        _gestureActive = false;
      }
      _multi = true;
      _startPinch();
    }
  }

  void _startPinch() {
    final pts = _pointers.values.take(2).toList();
    final focal = (pts[0] + pts[1]) / 2;
    _baseDistance = math.max((pts[0] - pts[1]).distance, 1);
    _baseZoom = _c.viewState.zoom;
    _anchor = _toCanvas(focal);
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (_multi) {
      if (_pointers.length >= 2) {
        final pts = _pointers.values.take(2).toList();
        final focal = (pts[0] + pts[1]) / 2;
        final distance = math.max((pts[0] - pts[1]).distance, 1);
        final zoom = (_baseZoom * distance / _baseDistance).clamp(0.2, 5.0).toDouble();
        _c.setView(
          zoom: zoom,
          scrollX: focal.dx / zoom - _anchor.dx,
          scrollY: focal.dy / zoom - _anchor.dy,
        );
      }
      return;
    }
    if (!_gestureActive) return;
    if ((e.localPosition - _downAt).distance > 8) _moved = true;
    _update(e.localPosition, e.delta);
  }

  void _onUp(PointerUpEvent e) {
    final pos = e.localPosition;
    _pointers.remove(e.pointer);
    if (_pointers.isNotEmpty) return;
    final wasMulti = _multi;
    _multi = false;
    if (!_gestureActive || wasMulti) {
      _gestureActive = false;
      return;
    }
    _gestureActive = false;
    _end(pos);
  }

  void _onCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    if (_gestureActive) _c.cancelGesture();
    _gestureActive = false;
    if (_pointers.isEmpty) _multi = false;
  }

  void _begin(Offset screen) {
    final p = _toCanvas(screen);
    switch (_c.tool) {
      case WhiteboardTool.pen:
        _c.beginStroke(p);
      case WhiteboardTool.eraser:
        _c.eraseAt(p, _tolerance);
      case WhiteboardTool.select:
        _c.beginMove(p, _tolerance);
      case WhiteboardTool.shape:
        _c.beginShape(p);
      case WhiteboardTool.pan:
      case WhiteboardTool.text:
      case WhiteboardTool.emoji:
        break;
    }
  }

  void _update(Offset screen, Offset delta) {
    final zoom = _c.viewState.zoom;
    final p = _toCanvas(screen);
    switch (_c.tool) {
      case WhiteboardTool.pen:
        _c.addStrokePoint(p);
      case WhiteboardTool.eraser:
        _c.eraseAt(p, _tolerance);
      case WhiteboardTool.select:
        _c.moveBy(delta / zoom);
      case WhiteboardTool.pan:
        _c.panBy(delta / zoom);
      case WhiteboardTool.shape:
        _c.updateShape(p);
      case WhiteboardTool.text:
      case WhiteboardTool.emoji:
        break;
    }
  }

  void _end(Offset screen) {
    switch (_c.tool) {
      case WhiteboardTool.pen:
        _c.endStroke();
      case WhiteboardTool.eraser:
        _c.endErase();
      case WhiteboardTool.select:
        _c.endMove();
      case WhiteboardTool.text:
        if (!_moved) _promptText(_toCanvas(screen));
      case WhiteboardTool.shape:
        _c.endShape();
      case WhiteboardTool.emoji:
        if (!_moved) _c.placeEmoji(_toCanvas(screen));
      case WhiteboardTool.pan:
        break;
    }
  }

  Color get _canvasColor => parseHexColor(_c.viewState.backgroundColor) ?? Colors.white;

  Future<void> _promptText(Offset at) async {
    final result = await showWhiteboardTextSheet(
      context,
      initialColor: _c.color,
      canvasColor: _canvasColor,
    );
    if (result != null) _c.addText(at, result);
  }

  Future<void> _editSelected() async {
    final el = _c.selected;
    if (el == null || el.type != 'text') return;
    final result = await showWhiteboardTextSheet(
      context,
      initialText: el.text,
      initialSize: el.fontSize,
      initialColor: el.textColor,
      canvasColor: _canvasColor,
      editing: true,
    );
    if (result != null) _c.updateText(el.id, result);
  }

  Future<void> _pickEmoji() async {
    final emoji = await showWhiteboardEmojiPicker(context, current: _c.emoji);
    if (emoji != null) _c.setEmoji(emoji);
  }

  Future<void> _confirmClear() async {
    if (_c.isEmpty) return;
    final ok = await orgConfirm(
      context,
      title: 'Clear whiteboard',
      body: 'This removes everything for everyone on this board.',
      action: 'Clear',
    );
    if (ok) _c.clearAll();
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
        title: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              Text(
                _c.offline
                    ? 'Reconnecting…'
                    : _c.status == WhiteboardStatus.ready
                        ? '${_c.users.length} online'
                        : 'Connecting…',
                style: TextStyle(color: _c.offline ? const Color(0xFFF59E0B) : orgMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Row(
              children: [
                _presence(),
                IconButton(
                  tooltip: 'Undo',
                  onPressed: _c.canUndo ? _c.undo : null,
                  icon: const Icon(Icons.undo_rounded),
                ),
                IconButton(
                  tooltip: 'Redo',
                  onPressed: _c.canRedo ? _c.redo : null,
                  icon: const Icon(Icons.redo_rounded),
                ),
                PopupMenuButton<String>(
                  color: orgCard,
                  onSelected: (v) {
                    if (v == 'clear') _confirmClear();
                    if (v == 'reset') _c.resetView();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'reset', child: Text('Reset view', style: TextStyle(color: Colors.white))),
                    PopupMenuItem(
                      value: 'clear',
                      child: Text('Clear board', style: TextStyle(color: Color(0xFFEF4444))),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _canvas()),
          _toolbar(),
        ],
      ),
    );
  }

  Widget _presence() {
    final users = _c.users;
    if (users.isEmpty) return const SizedBox.shrink();
    final shown = users.take(3).toList();
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        children: [
          for (final u in shown)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Tooltip(
                message: u.name,
                child: OrgAvatar(name: u.name, size: 26, circular: true),
              ),
            ),
          if (users.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '+${users.length - shown.length}',
                style: const TextStyle(color: orgMuted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _canvas() {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        if (_c.status == WhiteboardStatus.error) return _errorView();
        return Stack(
          children: [
            Positioned.fill(
              child: ClipRect(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onDown,
                  onPointerMove: _onMove,
                  onPointerUp: _onUp,
                  onPointerCancel: _onCancel,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: WhiteboardPainter(_c),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
            if (_c.status == WhiteboardStatus.joining)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x99090A10),
                  child: Center(child: CircularProgressIndicator(color: orgTeal)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: orgMuted, size: 42),
            const SizedBox(height: 12),
            Text(_c.error ?? 'Something went wrong.', textAlign: TextAlign.center, style: const TextStyle(color: orgMuted)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _c.retry,
              child: const Text('Retry', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolButton(WhiteboardTool tool, IconData icon, String label) {
    final active = _c.tool == tool;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _c.setTool(tool),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF16302F) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 21, color: active ? orgTeal : orgMuted),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 10, color: active ? orgTeal : orgMuted)),
            ],
          ),
        ),
      ),
    );
  }

  static const _shapeIcons = <ShapeKind, IconData>{
    ShapeKind.rectangle: Icons.crop_square_rounded,
    ShapeKind.ellipse: Icons.circle_outlined,
    ShapeKind.diamond: Icons.diamond_outlined,
    ShapeKind.triangle: Icons.change_history_rounded,
    ShapeKind.line: Icons.horizontal_rule_rounded,
    ShapeKind.arrow: Icons.arrow_right_alt_rounded,
  };

  Widget _swatches() {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final color in whiteboardPalette)
                  GestureDetector(
                    onTap: () => _c.setColor(color),
                    child: Container(
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.only(right: 8, top: 3, bottom: 3),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _c.color.value == color.value ? orgTeal : orgBorder,
                          width: _c.color.value == color.value ? 2.5 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (final w in _widths)
            GestureDetector(
              onTap: () => _c.setStrokeWidth(w),
              child: Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  color: _c.strokeWidth == w ? const Color(0xFF16302F) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Container(
                    width: 6 + w * 1.6,
                    height: 6 + w * 1.6,
                    decoration: BoxDecoration(
                      color: _c.strokeWidth == w ? orgTeal : orgMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _shapeRow() {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final entry in _shapeIcons.entries)
                  GestureDetector(
                    onTap: () => _c.setShape(entry.key),
                    child: Container(
                      width: 38,
                      height: 34,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: _c.shape == entry.key ? const Color(0xFF16302F) : orgField,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _c.shape == entry.key ? orgTeal : orgBorder),
                      ),
                      child: Icon(
                        entry.value,
                        size: 20,
                        color: _c.shape == entry.key ? orgTeal : orgMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_c.shape != ShapeKind.line && _c.shape != ShapeKind.arrow)
            GestureDetector(
              onTap: () => _c.setFillShapes(!_c.fillShapes),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: _c.fillShapes ? const Color(0xFF16302F) : orgField,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _c.fillShapes ? orgTeal : orgBorder),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.format_color_fill_rounded,
                      size: 17,
                      color: _c.fillShapes ? orgTeal : orgMuted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Fill',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _c.fillShapes ? orgTeal : orgMuted,
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

  Widget _emojiRow() {
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final e in whiteboardQuickEmojis)
                  GestureDetector(
                    onTap: () => _c.setEmoji(e),
                    child: Container(
                      width: 40,
                      height: 38,
                      margin: const EdgeInsets.only(right: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _c.emoji == e ? const Color(0xFF16302F) : orgField,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _c.emoji == e ? orgTeal : orgBorder),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _pickEmoji,
            child: Container(
              width: 40,
              height: 38,
              decoration: BoxDecoration(
                color: orgField,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: orgBorder),
              ),
              child: const Icon(Icons.grid_view_rounded, size: 19, color: orgTeal),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectRow() {
    final selected = _c.selected;
    final isText = selected?.type == 'text';
    return SizedBox(
      height: 38,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (selected == null)
            const Text('Tap an item to select it', style: TextStyle(color: orgMuted, fontSize: 13))
          else ...[
            if (isText)
              TextButton.icon(
                onPressed: _editSelected,
                icon: const Icon(Icons.edit_rounded, size: 18, color: orgTeal),
                label: const Text('Edit text', style: TextStyle(color: orgTeal, fontSize: 13)),
              ),
            TextButton.icon(
              onPressed: _c.deleteSelected,
              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
              label: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _toolbar() {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final disabled = _c.status != WhiteboardStatus.ready;
        final tool = _c.tool;
        return Container(
          decoration: const BoxDecoration(
            color: orgCard,
            border: Border(top: BorderSide(color: orgBorder)),
          ),
          child: SafeArea(
            top: false,
            child: IgnorePointer(
              ignoring: disabled,
              child: Opacity(
                opacity: disabled ? 0.5 : 1,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _toolButton(WhiteboardTool.pan, Icons.pan_tool_alt_outlined, 'Pan'),
                          _toolButton(WhiteboardTool.select, Icons.near_me_outlined, 'Select'),
                          _toolButton(WhiteboardTool.pen, Icons.edit_rounded, 'Pen'),
                          _toolButton(WhiteboardTool.eraser, Icons.cleaning_services_outlined, 'Eraser'),
                          _toolButton(WhiteboardTool.text, Icons.text_fields_rounded, 'Text'),
                          _toolButton(WhiteboardTool.shape, Icons.category_outlined, 'Shapes'),
                          _toolButton(WhiteboardTool.emoji, Icons.emoji_emotions_outlined, 'Emoji'),
                        ],
                      ),
                      if (tool == WhiteboardTool.select) ...[
                        const SizedBox(height: 6),
                        _selectRow(),
                      ] else if (tool == WhiteboardTool.pen || tool == WhiteboardTool.text) ...[
                        const SizedBox(height: 8),
                        _swatches(),
                      ] else if (tool == WhiteboardTool.shape) ...[
                        const SizedBox(height: 8),
                        _shapeRow(),
                        const SizedBox(height: 6),
                        _swatches(),
                      ] else if (tool == WhiteboardTool.emoji) ...[
                        const SizedBox(height: 8),
                        _emojiRow(),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 30,
                          child: Row(
                            children: [
                              const Text('Size', style: TextStyle(color: orgMuted, fontSize: 12.5)),
                              const Spacer(),
                              for (final w in _widths)
                                GestureDetector(
                                  onTap: () => _c.setStrokeWidth(w),
                                  child: Container(
                                    width: 34,
                                    height: 30,
                                    margin: const EdgeInsets.only(left: 4),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: _c.strokeWidth == w ? const Color(0xFF16302F) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '😀',
                                      style: TextStyle(fontSize: 10 + w * 1.5),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
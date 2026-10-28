import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'whiteboard_controller.dart';
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

  static const _palette = <Color>[
    Color(0xFF0F172A),
    Color(0xFFF8FAFC),
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFF22C55E),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
  ];

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
      case WhiteboardTool.pan:
      case WhiteboardTool.text:
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
      case WhiteboardTool.text:
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
      case WhiteboardTool.pan:
        break;
    }
  }

  Future<void> _promptText(Offset at) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const WhiteboardTextDialog(),
    );
    if (text != null) _c.addText(at, text);
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
              Icon(icon, size: 22, color: active ? orgTeal : orgMuted),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 10.5, color: active ? orgTeal : orgMuted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbar() {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final disabled = _c.status != WhiteboardStatus.ready;
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
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_c.tool == WhiteboardTool.select)
                        SizedBox(
                          height: 34,
                          child: Center(
                            child: TextButton.icon(
                              onPressed: _c.selectedId == null ? null : _c.deleteSelected,
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                              label: Text(
                                _c.selectedId == null ? 'Tap an item to select it' : 'Delete selected',
                                style: TextStyle(
                                  color: _c.selectedId == null ? orgMuted : const Color(0xFFEF4444),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        )
                      else if (_c.tool == WhiteboardTool.pen || _c.tool == WhiteboardTool.text)
                        SizedBox(
                          height: 34,
                          child: Row(
                            children: [
                              Expanded(
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    for (final color in _palette)
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
                        )
                      else
                        const SizedBox(height: 34),
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
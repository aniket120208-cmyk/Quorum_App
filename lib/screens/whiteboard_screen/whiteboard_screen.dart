import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/upload_service.dart';
import 'package:quorum_app/api/whiteboard_repository.dart';
import 'package:quorum_app/screens/organization_screen/organization_sheets.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'whiteboard_controller.dart';
import 'whiteboard_emoji.dart';
import 'whiteboard_painter.dart';
import 'whiteboard_sheets.dart';

const Color _panelTop = Color(0xFF2A2450);
const Color _panelBottom = Color(0xFF1A1633);
const Color _tileColor = Color(0xFF13111F);
const Color _tileActive = Color(0xFF2E2760);
const Color _accent = Color(0xFF8B7CFF);
const Color _iconSoft = Color(0xFFC4BAFF);
const Color _menuColor = Color(0xFF1E1A38);
const Color _lineColor = Color(0x24FFFFFF);

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
  Size _viewport = Size.zero;
  late String _name = widget.name;
  bool _expanded = true;
  bool _uploading = false;

  static const _widths = <double>[2, 4, 8];

  static const _stickyColors = <Color>[
    Color(0xFFFFE08A),
    Color(0xFFFFB4A2),
    Color(0xFFB8F2C8),
    Color(0xFFA5D8FF),
    Color(0xFFE4C1F9),
    Color(0xFFFFC6E5),
  ];

  static const _commentColors = <String, Color>{
    'Purple': Color(0xFF7C6CFF),
    'Teal': Color(0xFF14B8A6),
    'Amber': Color(0xFFF59E0B),
    'Pink': Color(0xFFEC4899),
    'Blue': Color(0xFF3B82F6),
  };

  static const _textSizes = <String, double>{
    'Small': 16,
    'Medium': 24,
    'Large': 36,
    'Extra large': 56,
  };

  static const _shapeIcons = <ShapeKind, IconData>{
    ShapeKind.rectangle: Icons.crop_square_rounded,
    ShapeKind.ellipse: Icons.circle_outlined,
    ShapeKind.diamond: Icons.diamond_outlined,
    ShapeKind.triangle: Icons.change_history_rounded,
    ShapeKind.line: Icons.horizontal_rule_rounded,
    ShapeKind.arrow: Icons.arrow_right_alt_rounded,
  };

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

  Offset get _viewCenter => _toCanvas(Offset(_viewport.width / 2, _viewport.height * 0.4));

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
      case WhiteboardTool.highlighter:
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
      case WhiteboardTool.sticky:
      case WhiteboardTool.comment:
        break;
    }
  }

  void _update(Offset screen, Offset delta) {
    final zoom = _c.viewState.zoom;
    final p = _toCanvas(screen);
    switch (_c.tool) {
      case WhiteboardTool.pen:
      case WhiteboardTool.highlighter:
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
      case WhiteboardTool.sticky:
      case WhiteboardTool.comment:
        break;
    }
  }

  void _end(Offset screen) {
    switch (_c.tool) {
      case WhiteboardTool.pen:
      case WhiteboardTool.highlighter:
        _c.endStroke();
      case WhiteboardTool.eraser:
        _c.endErase();
      case WhiteboardTool.select:
        _c.endMove();
      case WhiteboardTool.text:
        if (!_moved) _promptText(_toCanvas(screen));
      case WhiteboardTool.sticky:
        if (!_moved) _promptSticky(_toCanvas(screen));
      case WhiteboardTool.comment:
        if (!_moved) _promptComment(_toCanvas(screen));
      case WhiteboardTool.shape:
        _c.endShape();
      case WhiteboardTool.emoji:
        if (!_moved) _c.placeEmoji(_toCanvas(screen));
      case WhiteboardTool.pan:
        break;
    }
  }

  Future<String?> _ask({
    required String title,
    required String action,
    required String hint,
    String initial = '',
  }) {
    return showOrgSheet<String>(
      context,
      WhiteboardNameSheet(
        title: title,
        action: action,
        hint: hint,
        initialName: initial,
        maxLines: 4,
        maxLength: 300,
      ),
    );
  }

  Future<void> _promptText(Offset at) async {
    final result = await showWhiteboardTextSheet(
      context,
      initialSize: _c.textSize,
      initialColor: _c.color,
      canvasColor: whiteboardCanvasColor,
    );
    if (result != null) _c.addText(at, result);
  }

  Future<void> _promptSticky(Offset at) async {
    final value = await _ask(title: 'Sticky note', action: 'Add note', hint: 'Write a note');
    if (value != null) _c.placeSticky(at, value);
  }

  Future<void> _promptComment(Offset at) async {
    final value = await _ask(title: 'Comment', action: 'Add comment', hint: 'Write a comment');
    if (value != null) _c.placeComment(at, value);
  }

  Future<void> _editSelected() async {
    final el = _c.selected;
    if (el == null) return;
    if (el.type == 'text') {
      final result = await showWhiteboardTextSheet(
        context,
        initialText: el.text,
        initialSize: el.fontSize,
        initialColor: el.textColor,
        canvasColor: whiteboardCanvasColor,
        editing: true,
      );
      if (result != null) _c.updateText(el.id, result);
      return;
    }
    if (el.type == 'sticky' || el.type == 'comment') {
      final value = await _ask(
        title: el.type == 'sticky' ? 'Edit note' : 'Edit comment',
        action: 'Save',
        hint: 'Write something',
        initial: el.text,
      );
      if (value != null) {
        _c.updateText(el.id, WhiteboardTextResult(text: value, fontSize: el.fontSize, color: el.textColor));
      }
    }
  }

  Future<void> _pickEmoji() async {
    final emoji = await showWhiteboardEmojiPicker(context, current: _c.emoji);
    if (emoji != null) {
      _c.setEmoji(emoji);
      _c.setTool(WhiteboardTool.emoji);
    }
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

  Future<void> _rename() async {
    final name = await showOrgSheet<String>(
      context,
      WhiteboardNameSheet(title: 'Rename whiteboard', action: 'Save', initialName: _name),
    );
    if (name == null || name == _name || !mounted) return;
    try {
      await WhiteboardRepository.instance.rename(widget.boardId, name);
      if (mounted) setState(() => _name = name);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _addImage(ImageSource source) async {
    if (_uploading) return;
    final file = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 2000);
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final iw = frame.image.width.toDouble();
      final ih = frame.image.height.toDouble();
      frame.image.dispose();
      codec.dispose();
      final result = await UploadService.instance.upload(path: file.path, fileName: file.name);
      final scale = math.min(1.0, 320 / math.max(iw, ih));
      _c.addImage(_viewCenter, result.url, iw * scale, ih * scale);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _zoomTo(double target) {
    final zoom = target.clamp(0.2, 5.0).toDouble();
    final center = Offset(_viewport.width / 2, _viewport.height / 2);
    final anchor = _toCanvas(center);
    _c.setView(
      zoom: zoom,
      scrollX: center.dx / zoom - anchor.dx,
      scrollY: center.dy / zoom - anchor.dy,
    );
  }

  void _fit() {
    Rect? bounds;
    for (final el in _c.elements) {
      final r = elementBounds(el);
      if (r == Rect.zero) continue;
      bounds = bounds == null ? r : bounds.expandToInclude(r);
    }
    if (bounds == null || _viewport.isEmpty) {
      _c.resetView();
      return;
    }
    const pad = 80.0;
    final zoom = math
        .min(_viewport.width / (bounds.width + pad * 2), _viewport.height / (bounds.height + pad * 2))
        .clamp(0.2, 2.0)
        .toDouble();
    _c.setView(
      zoom: zoom,
      scrollX: _viewport.width / zoom / 2 - bounds.center.dx,
      scrollY: _viewport.height / zoom / 2 - bounds.center.dy,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: whiteboardCanvasColor,
      body: Stack(
        children: [
          Positioned.fill(child: _canvas()),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(bottom: false, child: _header()),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _toolbar()),
        ],
      ),
    );
  }

  BoxDecoration _pillDecoration([double radius = 24]) {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2D2658), Color(0xFF1D1938)],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _lineColor),
    );
  }

  Widget _header() {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final status = _c.offline
            ? 'Reconnecting…'
            : _c.status == WhiteboardStatus.ready
                ? null
                : 'Connecting…';
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                  ),
                  const Expanded(
                    child: Text(
                      'Whiteboard',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        status,
                        style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  _presence(),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _titlePill(),
              ),
              const SizedBox(height: 10),
              _controlPill(),
            ],
          ),
        );
      },
    );
  }

  Widget _titlePill() {
    return Container(
      height: 44,
      decoration: _pillDecoration(),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
              onTap: _rename,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.edit_rounded, size: 18, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(width: 1, height: 44, color: _lineColor),
          PopupMenuButton<String>(
            color: _menuColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: EdgeInsets.zero,
            onSelected: (v) {
              if (v == 'clear') _confirmClear();
              if (v == 'reset') _c.resetView();
            },
            itemBuilder: (context) => [
              _menuItem<String>('page', 'Page 1', icon: Icons.check_rounded, iconColor: _accent),
              const PopupMenuDivider(height: 1),
              _menuItem<String>('reset', 'Reset view', icon: Icons.center_focus_strong_outlined),
              _menuItem<String>('clear', 'Clear board', icon: Icons.delete_outline_rounded, danger: true),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                height: 44,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Page 1', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    SizedBox(width: 2),
                    Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlPill() {
    final zoom = (_c.viewState.zoom * 100).round();
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: _pillDecoration(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pillIcon(Icons.undo_rounded, _c.canUndo ? _c.undo : null),
          _pillIcon(Icons.redo_rounded, _c.canRedo ? _c.redo : null),
          PopupMenuButton<String>(
            color: _menuColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: EdgeInsets.zero,
            onSelected: (v) {
              switch (v) {
                case 'in':
                  _zoomTo(_c.viewState.zoom * 1.25);
                case 'out':
                  _zoomTo(_c.viewState.zoom / 1.25);
                case 'fit':
                  _fit();
                default:
                  _zoomTo((double.tryParse(v) ?? 100) / 100);
              }
            },
            itemBuilder: (context) => [
              _menuItem<String>('in', 'Zoom in', icon: Icons.zoom_in_rounded),
              _menuItem<String>('out', 'Zoom out', icon: Icons.zoom_out_rounded),
              const PopupMenuDivider(height: 1),
              _menuItem<String>('50', '50%'),
              _menuItem<String>('100', '100%'),
              _menuItem<String>('200', '200%'),
              const PopupMenuDivider(height: 1),
              _menuItem<String>('fit', 'Fit to content', icon: Icons.fit_screen_rounded),
            ],
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$zoom%', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
          _pillIcon(Icons.close_fullscreen_rounded, _fit),
        ],
      ),
    );
  }

  Widget _pillIcon(IconData icon, VoidCallback? onTap) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 22, color: onTap == null ? const Color(0x66FFFFFF) : Colors.white),
    );
  }

  PopupMenuItem<T> _menuItem<T>(
    T value,
    String label, {
    IconData? icon,
    Color? iconColor,
    Color? dot,
    bool danger = false,
    bool selected = false,
  }) {
    final color = danger ? const Color(0xFFEF4444) : Colors.white;
    return PopupMenuItem<T>(
      value: value,
      height: 44,
      child: Row(
        children: [
          if (dot != null)
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            )
          else if (icon != null)
            Icon(icon, size: 19, color: iconColor ?? color),
          if (dot != null || icon != null) const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500))),
          if (selected) const Icon(Icons.check_rounded, size: 18, color: _accent),
        ],
      ),
    );
  }

  Widget _presence() {
    final users = _c.users;
    if (users.isEmpty) return const SizedBox.shrink();
    final shown = users.take(3).toList();
    return Row(
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
    );
  }

  Widget _canvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.biggest;
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
                      color: Color(0x990F0E17),
                      child: Center(child: CircularProgressIndicator(color: _accent)),
                    ),
                  ),
              ],
            );
          },
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
              child: const Text('Retry', style: TextStyle(color: _accent, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glyph(IconData icon, Color a, Color b, {double size = 27}) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [a, b],
      ).createShader(rect),
      child: Icon(icon, size: size, color: Colors.white),
    );
  }

  BoxDecoration _tileDecoration(bool active) {
    return BoxDecoration(
      color: active ? _tileActive : _tileColor,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: active ? _accent : const Color(0x14FFFFFF), width: active ? 1.4 : 1),
    );
  }

  Widget _tile({required Widget child, required bool active, required VoidCallback onTap}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: _tileDecoration(active),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _dropTile({
    required Widget glyph,
    required bool active,
    required VoidCallback onTap,
    required Widget chevron,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Container(
          height: 48,
          decoration: _tileDecoration(active),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                  onTap: onTap,
                  child: Center(child: glyph),
                ),
              ),
              chevron,
            ],
          ),
        ),
      ),
    );
  }

  Widget _chevron() {
    return const Padding(
      padding: EdgeInsets.only(right: 5, left: 1),
      child: SizedBox(
        height: 48,
        child: Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: Color(0xFFB9B4D9)),
      ),
    );
  }

  Widget _plainChevron(VoidCallback onTap) {
    return InkWell(
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
      onTap: onTap,
      child: _chevron(),
    );
  }

  Widget _menuChevron<T>({
    required List<PopupMenuEntry<T>> Function(BuildContext) items,
    required ValueChanged<T> onSelected,
  }) {
    return PopupMenuButton<T>(
      color: _menuColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: EdgeInsets.zero,
      offset: const Offset(0, -8),
      onSelected: onSelected,
      itemBuilder: items,
      child: _chevron(),
    );
  }

  Widget _swatches({bool widths = true}) {
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
                          color: _c.color.value == color.value ? _accent : _lineColor,
                          width: _c.color.value == color.value ? 2.5 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (widths)
            for (final w in _widths)
              GestureDetector(
                onTap: () => _c.setStrokeWidth(w),
                child: Container(
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    color: _c.strokeWidth == w ? _tileActive : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Container(
                      width: 6 + w * 1.6,
                      height: 6 + w * 1.6,
                      decoration: BoxDecoration(
                        color: _c.strokeWidth == w ? _accent : orgMuted,
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
                      decoration: _tileDecoration(_c.shape == entry.key),
                      child: Icon(entry.value, size: 20, color: _c.shape == entry.key ? _accent : orgMuted),
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
                decoration: _tileDecoration(_c.fillShapes),
                child: Row(
                  children: [
                    Icon(Icons.format_color_fill_rounded, size: 17, color: _c.fillShapes ? _accent : orgMuted),
                    const SizedBox(width: 5),
                    Text(
                      'Fill',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _c.fillShapes ? _accent : orgMuted,
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

  Widget _stickyRow() {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final color in _stickyColors)
            GestureDetector(
              onTap: () => _c.setStickyColor(color),
              child: Container(
                width: 30,
                height: 26,
                margin: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _c.stickyColor.value == color.value ? _accent : _lineColor,
                    width: _c.stickyColor.value == color.value ? 2.5 : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emojiRow() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
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
                          decoration: _tileDecoration(_c.emoji == e),
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
                  decoration: _tileDecoration(false),
                  child: const Icon(Icons.grid_view_rounded, size: 19, color: _accent),
                ),
              ),
            ],
          ),
        ),
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
                      color: _c.strokeWidth == w ? _tileActive : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('😀', style: TextStyle(fontSize: 10 + w * 1.5)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _selectRow() {
    final selected = _c.selected;
    final editable = selected != null && (selected.type == 'text' || selected.type == 'sticky' || selected.type == 'comment');
    return SizedBox(
      height: 38,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (selected == null)
            const Text('Tap an item to select it', style: TextStyle(color: orgMuted, fontSize: 13))
          else ...[
            if (editable)
              TextButton.icon(
                onPressed: _editSelected,
                icon: const Icon(Icons.edit_rounded, size: 18, color: _accent),
                label: const Text('Edit', style: TextStyle(color: _accent, fontSize: 13)),
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

  Widget? _options() {
    switch (_c.tool) {
      case WhiteboardTool.pen:
      case WhiteboardTool.highlighter:
        return _swatches();
      case WhiteboardTool.text:
        return _swatches(widths: false);
      case WhiteboardTool.shape:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [_shapeRow(), const SizedBox(height: 6), _swatches()],
        );
      case WhiteboardTool.sticky:
        return _stickyRow();
      case WhiteboardTool.emoji:
        return _emojiRow();
      case WhiteboardTool.select:
        return _selectRow();
      case WhiteboardTool.pan:
      case WhiteboardTool.eraser:
      case WhiteboardTool.comment:
        return null;
    }
  }

  bool get _lineShape => _c.shape == ShapeKind.line || _c.shape == ShapeKind.arrow;

  Widget _toolRowTop() {
    final tool = _c.tool;
    return Row(
      children: [
        _tile(
          active: tool == WhiteboardTool.pen,
          onTap: () => _c.setTool(WhiteboardTool.pen),
          child: _glyph(Icons.draw_rounded, const Color(0xFFD8D0FF), const Color(0xFF7C6CFF)),
        ),
        _tile(
          active: tool == WhiteboardTool.highlighter,
          onTap: () => _c.setTool(WhiteboardTool.highlighter),
          child: _glyph(Icons.border_color_rounded, const Color(0xFFB5A7FF), const Color(0xFF5B49E6)),
        ),
        _tile(
          active: tool == WhiteboardTool.sticky,
          onTap: () => _c.setTool(WhiteboardTool.sticky),
          child: _glyph(Icons.sticky_note_2_rounded, const Color(0xFFF0A8FF), const Color(0xFF8B7CFF)),
        ),
        _tile(
          active: tool == WhiteboardTool.eraser,
          onTap: () => _c.setTool(WhiteboardTool.eraser),
          child: _glyph(Icons.auto_fix_normal_rounded, const Color(0xFFF1EEFF), const Color(0xFF6D5CF0)),
        ),
        _tile(
          active: tool == WhiteboardTool.shape && _lineShape,
          onTap: () {
            _c.setShape(ShapeKind.arrow);
            _c.setTool(WhiteboardTool.shape);
          },
          child: _glyph(Icons.north_east_rounded, const Color(0xFFA9B8FF), const Color(0xFF6D5CF0), size: 30),
        ),
        _tile(
          active: tool == WhiteboardTool.shape && !_lineShape,
          onTap: () {
            if (_lineShape) _c.setShape(ShapeKind.ellipse);
            _c.setTool(WhiteboardTool.shape);
          },
          child: Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
          ),
        ),
      ],
    );
  }

  Widget _toolRowBottom() {
    final tool = _c.tool;
    return Row(
      children: [
        _dropTile(
          glyph: _glyph(Icons.sentiment_satisfied_alt_rounded, const Color(0xFFD8D0FF), const Color(0xFF8B7CFF), size: 24),
          active: tool == WhiteboardTool.emoji,
          onTap: () => _c.setTool(WhiteboardTool.emoji),
          chevron: _plainChevron(_pickEmoji),
        ),
        _dropTile(
          glyph: _glyph(Icons.chat_bubble_outline_rounded, const Color(0xFFD8D0FF), const Color(0xFF8B7CFF), size: 23),
          active: tool == WhiteboardTool.comment,
          onTap: () => _c.setTool(WhiteboardTool.comment),
          chevron: _menuChevron<Color>(
            items: (context) => [
              for (final entry in _commentColors.entries)
                _menuItem<Color>(
                  entry.value,
                  entry.key,
                  dot: entry.value,
                  selected: _c.commentColor.value == entry.value.value,
                ),
            ],
            onSelected: (color) {
              _c.setCommentColor(color);
              _c.setTool(WhiteboardTool.comment);
            },
          ),
        ),
        _dropTile(
          glyph: _glyph(Icons.title_rounded, const Color(0xFFD8D0FF), const Color(0xFF8B7CFF), size: 25),
          active: tool == WhiteboardTool.text,
          onTap: () => _c.setTool(WhiteboardTool.text),
          chevron: _menuChevron<double>(
            items: (context) => [
              for (final entry in _textSizes.entries)
                _menuItem<double>(entry.value, entry.key, selected: _c.textSize == entry.value),
            ],
            onSelected: (size) {
              _c.setTextSize(size);
              _c.setTool(WhiteboardTool.text);
            },
          ),
        ),
        _dropTile(
          glyph: _uploading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                )
              : _glyph(Icons.image_outlined, const Color(0xFFD8D0FF), const Color(0xFF8B7CFF), size: 24),
          active: false,
          onTap: () => _addImage(ImageSource.gallery),
          chevron: _menuChevron<ImageSource>(
            items: (context) => [
              _menuItem<ImageSource>(ImageSource.gallery, 'Gallery', icon: Icons.photo_library_outlined),
              _menuItem<ImageSource>(ImageSource.camera, 'Camera', icon: Icons.photo_camera_outlined),
            ],
            onSelected: _addImage,
          ),
        ),
        _dropTile(
          glyph: _glyph(Icons.dashboard_outlined, const Color(0xFFD8D0FF), const Color(0xFF8B7CFF), size: 24),
          active: false,
          onTap: () => _c.insertTemplate(WhiteboardTemplate.frame, _viewCenter),
          chevron: _menuChevron<WhiteboardTemplate>(
            items: (context) => [
              _menuItem<WhiteboardTemplate>(WhiteboardTemplate.frame, 'Frame', icon: Icons.crop_free_rounded),
              _menuItem<WhiteboardTemplate>(WhiteboardTemplate.kanban, 'Kanban board', icon: Icons.view_column_outlined),
              _menuItem<WhiteboardTemplate>(WhiteboardTemplate.matrix, 'Matrix 2×2', icon: Icons.grid_view_rounded),
              _menuItem<WhiteboardTemplate>(WhiteboardTemplate.table, 'Table 3×3', icon: Icons.table_chart_outlined),
            ],
            onSelected: (kind) => _c.insertTemplate(kind, _viewCenter),
          ),
        ),
        _dropTile(
          glyph: _glyph(
            tool == WhiteboardTool.select ? Icons.near_me_rounded : Icons.back_hand_outlined,
            const Color(0xFFD8D0FF),
            const Color(0xFF8B7CFF),
            size: 24,
          ),
          active: tool == WhiteboardTool.pan || tool == WhiteboardTool.select,
          onTap: () => _c.setTool(WhiteboardTool.pan),
          chevron: _menuChevron<WhiteboardTool>(
            items: (context) => [
              _menuItem<WhiteboardTool>(
                WhiteboardTool.pan,
                'Pan',
                icon: Icons.back_hand_outlined,
                selected: tool == WhiteboardTool.pan,
              ),
              _menuItem<WhiteboardTool>(
                WhiteboardTool.select,
                'Select',
                icon: Icons.near_me_outlined,
                selected: tool == WhiteboardTool.select,
              ),
            ],
            onSelected: _c.setTool,
          ),
        ),
      ],
    );
  }

  Widget _handle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v > 150) setState(() => _expanded = false);
        if (v < -150) setState(() => _expanded = true);
      },
      child: SizedBox(
        height: 24,
        width: double.infinity,
        child: Center(
          child: Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0x80FFFFFF),
              borderRadius: BorderRadius.circular(2),
            ),
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
        final options = _options();
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_panelTop, _panelBottom],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _lineColor),
              ),
              child: IgnorePointer(
                ignoring: disabled,
                child: Opacity(
                  opacity: disabled ? 0.5 : 1,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _handle(),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 180),
                        alignment: Alignment.topCenter,
                        child: _expanded
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(7, 0, 7, 10),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (options != null)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(3, 0, 3, 10),
                                        child: options,
                                      ),
                                    _toolRowTop(),
                                    const SizedBox(height: 8),
                                    _toolRowBottom(),
                                  ],
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
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
import 'package:flutter/material.dart';
import 'package:quorum_app/models/whiteboard_models.dart';
import 'whiteboard_controller.dart';

class WhiteboardPainter extends CustomPainter {
  WhiteboardPainter(this.controller) : super(repaint: controller);
  final WhiteboardController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final view = controller.viewState;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = parseHexColor(view.backgroundColor) ?? Colors.white,
    );
    canvas.save();
    canvas.scale(view.zoom);
    canvas.translate(view.scrollX, view.scrollY);

    for (final el in controller.elements) {
      switch (el.type) {
        case 'stroke':
          _stroke(canvas, el.points, el.strokeColor, el.strokeWidth);
        case 'text':
          layoutText(el).paint(canvas, Offset(el.x, el.y));
      }
    }

    if (controller.livePoints.isNotEmpty) {
      _stroke(canvas, controller.livePoints, controller.color, controller.strokeWidth);
    }

    final selected = controller.selected;
    if (selected != null) {
      final rect = elementBounds(selected).inflate(6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..color = const Color(0xFF3DDCC4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 / view.zoom,
      );
    }

    canvas.restore();

    for (final cursor in controller.cursors) {
      final screen = Offset(
        (cursor.x + view.scrollX) * view.zoom,
        (cursor.y + view.scrollY) * view.zoom,
      );
      _cursor(canvas, screen, cursor);
    }
  }

  void _stroke(Canvas canvas, List<Offset> pts, Color color, double width) {
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      canvas.drawCircle(pts.first, width / 2, Paint()..color = color);
      return;
    }
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = Offset((pts[i].dx + pts[i + 1].dx) / 2, (pts[i].dy + pts[i + 1].dy) / 2);
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  Color _cursorColor(String key) {
    final hash = key.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0xFFFF);
    return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.75, 0.5).toColor();
  }

  void _cursor(Canvas canvas, Offset p, RemoteCursor cursor) {
    final color = _cursorColor(cursor.key);
    final arrow = Path()
      ..moveTo(p.dx, p.dy)
      ..lineTo(p.dx, p.dy + 16)
      ..lineTo(p.dx + 4.5, p.dy + 12)
      ..lineTo(p.dx + 11, p.dy + 11)
      ..close();
    canvas.drawPath(arrow, Paint()..color = color);
    final tp = TextPainter(
      text: TextSpan(
        text: cursor.name,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 120);
    final label = Rect.fromLTWH(p.dx + 12, p.dy + 14, tp.width + 10, tp.height + 4);
    canvas.drawRRect(RRect.fromRectAndRadius(label, const Radius.circular(8)), Paint()..color = color);
    tp.paint(canvas, Offset(label.left + 5, label.top + 2));
  }

  @override
  bool shouldRepaint(covariant WhiteboardPainter oldDelegate) => oldDelegate.controller != controller;
}
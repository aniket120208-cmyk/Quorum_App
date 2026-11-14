import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:quorum_app/models/whiteboard_models.dart';
import 'whiteboard_controller.dart';

class WhiteboardPainter extends CustomPainter {
  WhiteboardPainter(this.controller) : super(repaint: controller);
  final WhiteboardController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final view = controller.viewState;
    canvas.drawRect(Offset.zero & size, Paint()..color = whiteboardCanvasColor);
    _grid(canvas, size, view);
    canvas.save();
    canvas.scale(view.zoom);
    canvas.translate(view.scrollX, view.scrollY);

    for (final el in controller.elements) {
      switch (el.type) {
        case 'stroke':
          final highlight = el.json['highlight'] == true;
          _stroke(
            canvas,
            el.points,
            highlight ? el.strokeColor.withOpacity(0.4) : _visible(el.strokeColor),
            el.strokeWidth,
          );
        case 'text':
          layoutText(el).paint(canvas, Offset(el.x, el.y));
        case 'sticky':
          _sticky(canvas, el);
        case 'comment':
          _comment(canvas, el);
        case 'image':
          _image(canvas, el);
        case 'frame':
          _frame(canvas, el);
        case 'rectangle':
        case 'ellipse':
        case 'diamond':
        case 'triangle':
        case 'line':
        case 'arrow':
          _shape(canvas, el);
      }
    }
    final liveShape = controller.liveShape;
    if (liveShape != null) _shape(canvas, liveShape);

    if (controller.livePoints.isNotEmpty) {
      _stroke(
        canvas,
        controller.livePoints,
        controller.liveHighlight ? controller.color.withOpacity(0.4) : controller.color,
        controller.liveStrokeWidth,
      );
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

  Color _visible(Color c) => c.computeLuminance() < 0.05 ? const Color(0xFFF8FAFC) : c;

  void _grid(Canvas canvas, Size size, WhiteboardViewState view) {
    final gap = 26 * view.zoom;
    if (gap < 9) return;
    final startX = (view.scrollX * view.zoom) % gap;
    final startY = (view.scrollY * view.zoom) % gap;
    final points = <Offset>[];
    for (var x = startX; x < size.width; x += gap) {
      for (var y = startY; y < size.height; y += gap) {
        points.add(Offset(x, y));
      }
    }
    canvas.drawPoints(
      ui.PointMode.points,
      points,
      Paint()
        ..color = const Color(0x33FFFFFF)
        ..strokeWidth = math.max(1.4, 1.6 * view.zoom)
        ..strokeCap = StrokeCap.round,
    );
  }

  void _sticky(Canvas canvas, WhiteboardElement el) {
    final rect = Rect.fromLTWH(el.x, el.y, el.width, el.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(
      rrect.shift(const Offset(0, 4)),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(rrect, Paint()..color = el.fillColor ?? const Color(0xFFFFE08A));
    final tp = layoutBoxText(
      el,
      maxWidth: math.max(el.width - 28, 10),
      fontSize: 17,
      color: const Color(0xFF1F2937),
      maxLines: ((el.height - 28) / (17 * 1.25)).floor().clamp(1, 20).toInt(),
    );
    tp.paint(canvas, Offset(rect.left + 14, rect.top + 14));
  }

  void _comment(Canvas canvas, WhiteboardElement el) {
    final rect = Rect.fromLTWH(el.x, el.y, el.width, el.height);
    final fill = Paint()..color = el.fillColor ?? const Color(0xFF7C6CFF);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(14)), fill);
    final tail = Path()
      ..moveTo(rect.left + 14, rect.bottom - 1)
      ..lineTo(rect.left + 10, rect.bottom + 12)
      ..lineTo(rect.left + 30, rect.bottom - 1)
      ..close();
    canvas.drawPath(tail, fill);
    final tp = layoutBoxText(
      el,
      maxWidth: math.max(el.width - 28, 10),
      fontSize: 16,
      color: Colors.white,
    );
    tp.paint(canvas, Offset(rect.left + 14, rect.top + 11));
  }

  void _image(Canvas canvas, WhiteboardElement el) {
    final rect = Rect.fromLTWH(el.x, el.y, el.width, el.height);
    final image = controller.imageFor((el.json['url'] ?? '').toString());
    if (image == null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        Paint()..color = const Color(0x14FFFFFF),
      );
      return;
    }
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  void _frame(Canvas canvas, WhiteboardElement el) {
    final rect = Rect.fromLTWH(el.x, el.y, el.width, el.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.drawRRect(rrect, Paint()..color = const Color(0x0DFFFFFF));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0x66A9A4D6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    if (el.text.isEmpty) return;
    final tp = layoutBoxText(
      el,
      maxWidth: math.max(el.width - 24, 10),
      fontSize: 14,
      color: const Color(0xFFC4BEFF),
      maxLines: 1,
    );
    tp.paint(canvas, Offset(rect.left + 12, rect.top + 8));
  }

  void _shape(Canvas canvas, WhiteboardElement el) {
    final line = Paint()
      ..color = _visible(el.strokeColor)
      ..strokeWidth = el.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (el.type == 'line' || el.type == 'arrow') {
      final pts = el.points;
      if (pts.length < 2) return;
      final a = pts.first;
      final b = pts.last;
      canvas.drawLine(a, b, line);
      if (el.type == 'arrow' && (b - a).distance > 0.5) {
        final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
        final head = math.max(12.0, el.strokeWidth * 4);
        for (final delta in const [0.5, -0.5]) {
          canvas.drawLine(
            b,
            Offset(b.dx - head * math.cos(angle - delta), b.dy - head * math.sin(angle - delta)),
            line,
          );
        }
      }
      return;
    }

    final rect = Rect.fromLTWH(el.x, el.y, el.width, el.height);
    final path = Path();
    switch (el.type) {
      case 'rectangle':
        path.addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)));
      case 'ellipse':
        path.addOval(rect);
      case 'diamond':
        path
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.center.dx, rect.bottom)
          ..lineTo(rect.left, rect.center.dy)
          ..close();
      case 'triangle':
        path
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close();
      default:
        return;
    }
    final fill = el.fillColor;
    if (fill != null) {
      canvas.drawPath(path, Paint()..color = _visible(fill).withOpacity(0.28));
    }
    canvas.drawPath(path, line);
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
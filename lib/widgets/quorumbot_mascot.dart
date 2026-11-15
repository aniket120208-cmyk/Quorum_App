import 'dart:math' as math;
import 'package:flutter/material.dart';

class UltronMascot extends StatefulWidget {
  final double size;
  final bool thinking;
  final bool animate;

  const UltronMascot({
    super.key,
    this.size = 48,
    this.thinking = false,
    this.animate = true,
  });

  @override
  State<UltronMascot> createState() => _UltronMascotState();
}

class _UltronMascotState extends State<UltronMascot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 6000));
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant UltronMascot old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) _c.repeat();
    if (!widget.animate && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: UltronPainter(t: _c.value, thinking: widget.thinking),
        ),
      ),
    );
  }
}

class UltronPainter extends CustomPainter {
  final double t;
  final bool thinking;

  const UltronPainter({required this.t, required this.thinking});

  static const Color _teal = Color(0xFF3DDCC4);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _shell = Color(0xFFD9DFEA);
  static const Color _shade = Color(0xFFA9B2C3);
  static const Color _metal = Color(0xFF7B8494);
  static const Color _dark = Color(0xFF232733);
  static const Color _visorTop = Color(0xFF111726);
  static const Color _visorBottom = Color(0xFF05070C);

  double get _wave {
    if (thinking) return 0;
    if (t < 0.08) return t / 0.08;
    if (t < 0.45) return 1;
    if (t < 0.55) return 1 - (t - 0.45) / 0.1;
    return 0;
  }

  double get _blink {
    double dip(double c) {
      final d = (t - c).abs();
      return d < 0.015 ? 1 - d / 0.015 : 0;
    }

    return math.max(dip(0.68), dip(0.9));
  }

  Paint _shellPaint(Rect r) => Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [_white, _shell, _shade],
      stops: [0.0, 0.6, 1.0],
    ).createShader(r);

  Paint _metalPaint(Rect r) => Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFB5BDCB), _metal, _dark],
    ).createShader(r);

  void _arm(Canvas canvas, Offset shoulder, double angle, {required bool mirror}) {
    canvas.save();
    canvas.translate(shoulder.dx, shoulder.dy);
    canvas.rotate(angle);
    if (mirror) canvas.scale(-1, 1);

    final upper = RRect.fromRectAndRadius(const Rect.fromLTWH(-3.6, 0, 7.2, 13), const Radius.circular(3.6));
    canvas.drawRRect(upper, _shellPaint(upper.outerRect));
    canvas.drawRRect(
      upper,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = _shade,
    );

    final elbow = Rect.fromCircle(center: const Offset(0, 13), radius: 3.4);
    canvas.drawOval(elbow, _metalPaint(elbow));

    final fore = RRect.fromRectAndRadius(const Rect.fromLTWH(-3, 13, 6, 9), const Radius.circular(3));
    canvas.drawRRect(fore, _shellPaint(fore.outerRect));

    final hand = Rect.fromCircle(center: const Offset(0, 25), radius: 4.2);
    canvas.drawOval(hand, _metalPaint(hand));
    final thumb = Rect.fromCenter(center: const Offset(3.6, 23.4), width: 3.2, height: 5);
    canvas.drawOval(thumb, _metalPaint(thumb));
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height) / 100;
    canvas.save();
    canvas.scale(s);

    final bob = math.sin(t * 2 * math.pi * 3) * 1.2;
    final tilt = math.sin(t * 2 * math.pi * 2) * 0.025 + (thinking ? math.sin(t * 2 * math.pi * 6) * 0.04 : 0);
    final pulse = (math.sin(t * 2 * math.pi * (thinking ? 8 : 3)) + 1) / 2;

    canvas.save();
    canvas.translate(0, bob);

    final wave = _wave;
    final swing = wave * math.sin(t * 2 * math.pi * 14) * (16 * math.pi / 180);
    final armAngle = -(12 + 133 * wave) * math.pi / 180 + swing;
    final sway = math.sin(t * 2 * math.pi * 3 + 1) * 0.04;

    _arm(canvas, const Offset(27, 72), 0.16 + sway, mirror: true);

    final torso = RRect.fromRectAndCorners(
      const Rect.fromLTWH(31, 64, 38, 40),
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: const Radius.circular(8),
      bottomRight: const Radius.circular(8),
    );
    canvas.drawRRect(torso, _shellPaint(torso.outerRect));
    canvas.drawRRect(
      torso,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = _shade,
    );

    final belt = RRect.fromRectAndRadius(const Rect.fromLTWH(38, 86, 24, 6), const Radius.circular(3));
    canvas.drawRRect(belt, Paint()..color = _dark.withOpacity(0.85));
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(Offset(43 + i * 5.0, 87), Offset(43 + i * 5.0, 91), Paint()
        ..color = _metal
        ..strokeWidth = 0.8);
    }

    final chest = Offset(60, 75);
    canvas.drawCircle(
      chest,
      5.5,
      Paint()
        ..color = _teal.withOpacity(0.35 + 0.35 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(chest, 4.2, Paint()..color = _dark);
    canvas.drawCircle(chest, 3.2, Paint()..color = _teal.withOpacity(0.75 + 0.25 * pulse));
    canvas.drawCircle(chest, 1.4, Paint()..color = _white.withOpacity(0.9));

    _arm(canvas, const Offset(73, 72), armAngle, mirror: false);

    final neck = RRect.fromRectAndRadius(const Rect.fromLTWH(44, 58, 12, 8), const Radius.circular(3));
    canvas.drawRRect(neck, Paint()..color = _dark);

    canvas.save();
    canvas.translate(50, 60);
    canvas.rotate(tilt);
    canvas.translate(-50, -60);

    final antPulse = 0.5 + 0.5 * pulse;
    for (final side in const [-1.0, 1.0]) {
      final base = Offset(50 + side * 24, 12);
      final tip = Offset(50 + side * 30, 2.5);
      canvas.drawLine(
        base,
        tip,
        Paint()
          ..color = _metal
          ..strokeWidth = 1.3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        tip,
        3.6,
        Paint()
          ..color = _teal.withOpacity(0.55 * antPulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
      );
      canvas.drawCircle(tip, 2.1, Paint()..color = _teal);
    }

    for (final side in const [-1.0, 1.0]) {
      final c = Offset(50 + side * 36, 36);
      final pod = Rect.fromCenter(center: c, width: 11, height: 22);
      canvas.drawOval(pod, _shellPaint(pod));
      canvas.drawOval(
        pod,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = _shade,
      );
      final ring = Rect.fromCenter(center: c, width: 6, height: 15);
      canvas.drawOval(
        ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = _teal.withOpacity(0.9),
      );
    }

    final helmet = Rect.fromCenter(center: const Offset(50, 35), width: 66, height: 56);
    final helmetRR = RRect.fromRectAndRadius(helmet, const Radius.circular(27));
    canvas.drawRRect(
      helmetRR,
      Paint()
        ..color = Colors.black.withOpacity(0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawRRect(helmetRR, _shellPaint(helmet));
    canvas.drawRRect(
      helmetRR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = _shade,
    );
    canvas.drawArc(
      Rect.fromCenter(center: const Offset(42, 20), width: 24, height: 10),
      math.pi * 1.05,
      math.pi * 0.7,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withOpacity(0.9),
    );

    final visor = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(50, 37), width: 52, height: 34),
      const Radius.circular(15),
    );
    canvas.drawRRect(
      visor,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_visorTop, _visorBottom],
        ).createShader(visor.outerRect),
    );
    canvas.drawRRect(
      visor,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = _teal.withOpacity(0.25),
    );

    final look = thinking ? math.sin(t * 2 * math.pi * 4) * 2.4 : math.sin(t * 2 * math.pi) * 0.8;
    final eyeH = 6.2 * (1 - 0.9 * _blink);
    for (final side in const [-1.0, 1.0]) {
      final c = Offset(50 + side * 10 + look, 35);
      final eye = Rect.fromCenter(center: c, width: 8.6, height: eyeH * 2);
      canvas.drawOval(
        eye.inflate(1.6),
        Paint()
          ..color = _teal.withOpacity(0.35 + 0.15 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.6),
      );
      canvas.drawOval(eye, Paint()..color = _teal);
      canvas.drawOval(
        Rect.fromCenter(center: c.translate(-1.2, -eyeH * 0.4), width: 2.6, height: math.max(0.4, eyeH * 0.5)),
        Paint()..color = Colors.white.withOpacity(0.75),
      );
    }

    final smile = Path();
    if (thinking) {
      smile
        ..moveTo(46.5, 47)
        ..quadraticBezierTo(50, 44.5, 53.5, 47);
    } else {
      smile
        ..moveTo(45, 45.5)
        ..quadraticBezierTo(50, 50.5 + wave * 1.2, 55, 45.5);
    }
    canvas.drawPath(
      smile,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = _teal,
    );

    canvas.restore();
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant UltronPainter old) => old.t != t || old.thinking != thinking;
}
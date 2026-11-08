import 'dart:math' as math;
import 'package:flutter/material.dart';

enum SwipeDirection { left, right }

class SwipeCardDeck<T> extends StatefulWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Future<bool> Function(T item, SwipeDirection direction) onSwipe;
  final void Function(T item, SwipeDirection direction) onSwiped;
  final String rightLabel;
  final String leftLabel;
  final Color rightColor;
  final Color leftColor;
  final int visibleCount;

  const SwipeCardDeck({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.onSwipe,
    required this.onSwiped,
    this.rightLabel = 'YES',
    this.leftLabel = 'NOPE',
    this.rightColor = const Color(0xFF22C55E),
    this.leftColor = const Color(0xFFEF4444),
    this.visibleCount = 3,
  });

  @override
  State<SwipeCardDeck<T>> createState() => SwipeCardDeckState<T>();
}

class SwipeCardDeckState<T> extends State<SwipeCardDeck<T>> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  Animation<Offset>? _offsetAnim;
  Offset _drag = Offset.zero;
  bool _busy = false;
  double _width = 320;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this)
      ..addListener(() {
        final a = _offsetAnim;
        if (a != null && mounted) setState(() => _drag = a.value);
      });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _animate(Offset end, Duration duration, Curve curve) async {
    _offsetAnim = Tween<Offset>(begin: _drag, end: end).animate(CurvedAnimation(parent: _anim, curve: curve));
    _anim.duration = duration;
    await _anim.forward(from: 0);
  }

  Future<void> swipe(SwipeDirection direction) => _commit(direction);

  Future<void> _commit(SwipeDirection direction) async {
    if (_busy || widget.items.isEmpty) return;
    _busy = true;
    final item = widget.items.first;
    final sign = direction == SwipeDirection.right ? 1.0 : -1.0;
    if (_drag.dx.abs() < _width * 0.3) {
      await _animate(Offset(sign * _width * 0.45, -24), const Duration(milliseconds: 160), Curves.easeOut);
      if (!mounted) return;
    }
    final accepted = await widget.onSwipe(item, direction);
    if (!mounted) return;
    if (accepted) {
      await _animate(Offset(sign * _width * 1.7, _drag.dy), const Duration(milliseconds: 230), Curves.easeIn);
      if (!mounted) return;
      setState(() => _drag = Offset.zero);
      widget.onSwiped(item, direction);
    } else {
      await _animate(Offset.zero, const Duration(milliseconds: 320), Curves.easeOutBack);
    }
    _busy = false;
  }

  void _onPanStart(DragStartDetails d) {
    if (_busy) return;
    _anim.stop();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_busy) return;
    setState(() => _drag += d.delta);
  }

  void _onPanEnd(DragEndDetails d) {
    if (_busy) return;
    final vx = d.velocity.pixelsPerSecond.dx;
    if (_drag.dx > _width * 0.28 || (vx > 900 && _drag.dx > 20)) {
      _commit(SwipeDirection.right);
    } else if (_drag.dx < -_width * 0.28 || (vx < -900 && _drag.dx < -20)) {
      _commit(SwipeDirection.left);
    } else {
      _animate(Offset.zero, const Duration(milliseconds: 300), Curves.easeOutBack);
    }
  }

  Widget _stamp(String label, Color color, double angle) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        final count = math.min(widget.items.length, widget.visibleCount);
        final progress = (_drag.dx.abs() / (_width * 0.3)).clamp(0.0, 1.0);
        final rightOpacity = (_drag.dx / (_width * 0.25)).clamp(0.0, 1.0);
        final leftOpacity = (-_drag.dx / (_width * 0.25)).clamp(0.0, 1.0);
        final children = <Widget>[];
        for (var i = count - 1; i >= 1; i--) {
          final depth = i - progress;
          children.add(
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(0, 14 * depth),
                child: Transform.scale(
                  scale: 1 - 0.05 * depth,
                  child: widget.itemBuilder(context, widget.items[i]),
                ),
              ),
            ),
          );
        }
        children.add(
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: Transform.translate(
                offset: _drag,
                child: Transform.rotate(
                  angle: (_drag.dx / _width) * 0.35,
                  alignment: Alignment.bottomCenter,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      widget.itemBuilder(context, widget.items.first),
                      Positioned(
                        top: 28,
                        left: 24,
                        child: IgnorePointer(
                          child: Opacity(opacity: rightOpacity, child: _stamp(widget.rightLabel, widget.rightColor, -0.25)),
                        ),
                      ),
                      Positioned(
                        top: 28,
                        right: 24,
                        child: IgnorePointer(
                          child: Opacity(opacity: leftOpacity, child: _stamp(widget.leftLabel, widget.leftColor, 0.25)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        return Stack(clipBehavior: Clip.none, children: children);
      },
    );
  }
}
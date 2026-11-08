import 'dart:math' as math;
import 'package:flutter/material.dart';

class WalletCardStack extends StatefulWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int>? onTap;
  final ValueChanged<int>? onFrontChanged;
  final double cardHeight;
  final double peek;
  final int maxVisible;
  final double? maxHeight;
  final double minPeek;

  const WalletCardStack({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.onTap,
    this.onFrontChanged,
    this.cardHeight = 190,
    this.peek = 40,
    this.maxVisible = 4,
    this.maxHeight,
    this.minPeek = 8,
  });

  @override
  State<WalletCardStack> createState() => _WalletCardStackState();
}

class _WalletCardStackState extends State<WalletCardStack> with SingleTickerProviderStateMixin {
  static const double _threshold = 110;

  late final AnimationController _anim;
  Animation<Offset>? _offsetAnim;
  int _front = 0;
  Offset _drag = Offset.zero;
  bool _flying = false;

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

  void _animateTo(Offset end, Duration duration, Curve curve, VoidCallback onDone) {
    _offsetAnim = Tween<Offset>(begin: _drag, end: end).animate(CurvedAnimation(parent: _anim, curve: curve));
    _anim.duration = duration;
    _anim.forward(from: 0).whenComplete(onDone);
  }

  void _onPanStart(DragStartDetails d) {
    if (_flying) return;
    _anim.stop();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_flying) return;
    setState(() => _drag += d.delta);
  }

  void _onPanEnd(DragEndDetails d) {
    if (_flying) return;
    final n = widget.itemCount;
    final dist = _drag.distance;
    final fast = d.velocity.pixelsPerSecond.distance > 900 && dist > 30;
    if (n > 1 && (dist > _threshold || fast)) {
      _flying = true;
      final dir = dist < 1 ? const Offset(0, -1) : _drag / dist;
      _animateTo(dir * 700, const Duration(milliseconds: 240), Curves.easeIn, () {
        if (!mounted) return;
        setState(() {
          _front = (_front + 1) % n;
          _drag = Offset.zero;
          _flying = false;
        });
        widget.onFrontChanged?.call(_front);
      });
    } else {
      _animateTo(Offset.zero, const Duration(milliseconds: 320), Curves.easeOutBack, () {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.itemCount;
    if (n == 0) return const SizedBox.shrink();
    final visible = math.min(n, widget.maxVisible);
    final front = _front % n;
    final progress = (_drag.distance / _threshold).clamp(0.0, 1.0);
    var peek = widget.peek;
    final limit = widget.maxHeight;
    if (limit != null && visible > 1) {
      peek = math.min(peek, math.max(widget.minPeek, (limit - widget.cardHeight) / (visible - 1)));
    }
    final scaleStep = visible > 1 ? math.min(0.045, 0.15 / (visible - 1)) : 0.0;
    final totalHeight = widget.cardHeight + (visible - 1) * peek;
    final children = <Widget>[];
    for (var d = visible - 1; d >= 0; d--) {
      final index = (front + d) % n;
      if (d == 0) {
        final fade = _drag.distance > 140 ? (1 - (_drag.distance - 140) / 260).clamp(0.0, 1.0) : 1.0;
        children.add(
          Positioned(
            key: ValueKey('wallet-front-$index'),
            top: (visible - 1) * peek,
            left: 0,
            right: 0,
            height: widget.cardHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onTap?.call(index),
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: Opacity(
                opacity: fade,
                child: Transform.translate(
                  offset: _drag,
                  child: Transform.rotate(
                    angle: (_drag.dx / 600).clamp(-0.45, 0.45),
                    child: widget.itemBuilder(context, index),
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        final depth = d - progress;
        final scale = 1 - scaleStep * depth;
        children.add(
          Positioned(
            key: ValueKey('wallet-back-$index'),
            top: (visible - 1 - depth) * peek,
            left: 0,
            right: 0,
            height: widget.cardHeight,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topCenter,
              child: widget.itemBuilder(context, index),
            ),
          ),
        );
      }
    }

    return SizedBox(
      height: totalHeight,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }
}
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:quorum_app/models/meeting_models.dart';

class _Floating {
  _Floating({
    required this.reaction,
    required this.controller,
    required this.lane,
    required this.sway,
  });

  final MeetingReaction reaction;
  final AnimationController controller;
  final double lane;
  final double sway;
}

class FloatingReactions extends StatefulWidget {
  const FloatingReactions({super.key, required this.stream, required this.selfId});

  final Stream<MeetingReaction> stream;
  final String selfId;

  @override
  State<FloatingReactions> createState() => _FloatingReactionsState();
}

class _FloatingReactionsState extends State<FloatingReactions> with TickerProviderStateMixin {
  static const int _maxActive = 24;

  final _random = Random();
  final List<_Floating> _items = [];
  StreamSubscription<MeetingReaction>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.stream.listen(_add);
  }

  @override
  void didUpdateWidget(covariant FloatingReactions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.stream, widget.stream)) {
      _sub?.cancel();
      _sub = widget.stream.listen(_add);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final item in _items) {
      item.controller.dispose();
    }
    _items.clear();
    super.dispose();
  }

  void _add(MeetingReaction reaction) {
    if (!mounted || _items.length >= _maxActive) return;
    final controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 2600 + _random.nextInt(700)),
    );
    final item = _Floating(
      reaction: reaction,
      controller: controller,
      lane: 0.35 + _random.nextDouble() * 0.6,
      sway: 0.04 + _random.nextDouble() * 0.06,
    );
    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      setState(() => _items.remove(item));
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    });
    setState(() => _items.add(item));
    controller.forward();
  }

  double _opacity(double t) {
    if (t < 0.1) return t / 0.1;
    if (t > 0.75) return (1 - t) / 0.25;
    return 1;
  }

  Widget _entry(_Floating item) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: item.controller,
        builder: (context, _) {
          final t = item.controller.value;
          final scale = 0.6 + 0.4 * Curves.easeOutBack.transform(min(t / 0.15, 1.0));
          final x = item.lane + item.sway * sin(t * 2 * pi * 1.5);
          final y = 1.0 - 1.7 * Curves.easeOut.transform(t);
          final mine = item.reaction.userId == widget.selfId;
          return Align(
            alignment: Alignment(x, y),
            child: Opacity(
              opacity: _opacity(t).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.reaction.emoji, style: const TextStyle(fontSize: 36)),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        mine ? 'You' : item.reaction.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [for (final item in _items) _entry(item)],
      ),
    );
  }
}
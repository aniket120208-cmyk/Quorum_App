import 'package:flutter/material.dart';

class DraggablePipView extends StatefulWidget {
  const DraggablePipView({
    super.key,
    required this.child,
    this.topInset = 0,
    this.bottomInset = 0,
    this.width = 110,
    this.height = 150,
  });

  final Widget child;
  final double topInset;
  final double bottomInset;
  final double width;
  final double height;

  @override
  State<DraggablePipView> createState() => _DraggablePipViewState();
}

class _DraggablePipViewState extends State<DraggablePipView> {
  static const double _margin = 12;
  Offset? _offset;
  bool _dragging = false;

  Offset _clamp(Offset o, Size area) {
    final maxX = area.width - widget.width - _margin;
    final maxY = area.height - widget.height - widget.bottomInset;
    return Offset(
      o.dx.clamp(_margin, maxX < _margin ? _margin : maxX),
      o.dy.clamp(widget.topInset, maxY < widget.topInset ? widget.topInset : maxY),
    );
  }

  Offset _snap(Offset o, Size area) {
    final left = o.dx + widget.width / 2 < area.width / 2;
    final x = left ? _margin : area.width - widget.width - _margin;
    return _clamp(Offset(x, o.dy), area);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final area = Size(c.maxWidth, c.maxHeight);
        final current = _clamp(
          _offset ?? Offset(area.width - widget.width - _margin, widget.topInset),
          area,
        );
        return Stack(
          children: [
            AnimatedPositioned(
              duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              left: current.dx,
              top: current.dy,
              width: widget.width,
              height: widget.height,
              child: GestureDetector(
                onPanStart: (_) => setState(() {
                  _dragging = true;
                  _offset = current;
                }),
                onPanUpdate: (d) => setState(() {
                  _offset = _clamp((_offset ?? current) + d.delta, area);
                }),
                onPanEnd: (_) => setState(() {
                  _dragging = false;
                  _offset = _snap(_offset ?? current, area);
                }),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
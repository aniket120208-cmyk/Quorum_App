import 'package:flutter/material.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const Color barColor = Color(0xFF1B1646);
  static const Color edgeColor = Color(0xFF2B2566);
  static const Color activeColor = Color(0xFF7F77FF);
  static const Color inactiveColor = Color(0xFFE8E6FF);
  static const double barHeight = 68;
  static const double overhang = 20;
  static const double buttonSize = 56;
  static const Duration duration = Duration(milliseconds: 280);
  static const List<_Item> _items = [
    _Item(Icons.home_outlined, 'Home'),
    _Item(Icons.chat_bubble_outline_rounded, 'Chat'),
    _Item(Icons.videocam_outlined, 'Video Call'),
    _Item(Icons.groups_2_outlined, 'Community'),
    _Item(Icons.auto_awesome_outlined, 'AI Assistant'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final selected = currentIndex.clamp(0, _items.length - 1);

    return SizedBox(
      height: barHeight + overhang + bottomInset,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slot = constraints.maxWidth / _items.length;
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(end: selected.toDouble()),
            duration: duration,
            curve: Curves.easeOutCubic,
            builder: (context, position, _) {
              final centerX = (position + 0.5) * slot;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: barHeight + bottomInset,
                    child: CustomPaint(
                      painter: _NotchedBarPainter(
                        color: barColor,
                        edgeColor: edgeColor,
                        centerX: centerX,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: bottomInset,
                    height: barHeight,
                    child: Row(
                      children: [
                        for (var i = 0; i < _items.length; i++)
                          _NavItem(
                            item: _items[i],
                            isSelected: i == selected,
                            onTap: () => onTap(i),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: overhang - 18,
                    left: centerX - buttonSize / 2,
                    width: buttonSize,
                    height: buttonSize,
                    child: Semantics(
                      label: _items[selected].label,
                      button: true,
                      selected: true,
                      child: GestureDetector(
                        onTap: () => onTap(selected),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: edgeColor,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.35),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder: (child, animation) => FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(scale: animation, child: child),
                            ),
                            child: Icon(
                              _items[selected].icon,
                              key: ValueKey<int>(selected),
                              size: 26,
                              color: activeColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Item {
  final IconData icon;
  final String label;
  const _Item(this.icon, this.label);
}

class _NavItem extends StatelessWidget {
  final _Item item;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        label: item.label,
        button: true,
        selected: isSelected,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: isSelected ? 0 : 1,
              child: Icon(
                item.icon,
                size: 25,
                color: CustomBottomNavBar.inactiveColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotchedBarPainter extends CustomPainter {
  final Color color;
  final Color edgeColor;
  final double centerX;
  
  _NotchedBarPainter({
    required this.color,
    required this.edgeColor,
    required this.centerX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const notchHalf = 52.0;
    const depth = 40.0;
    const shoulder = 22.0;
    final cx = centerX;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(cx - notchHalf - shoulder, 0)
      ..cubicTo(
        cx - notchHalf + 6,
        0,
        cx - notchHalf + 8,
        depth,
        cx,
        depth,
      )
      ..cubicTo(
        cx + notchHalf - 8,
        depth,
        cx + notchHalf - 6,
        0,
        cx + notchHalf + shoulder,
        0,
      )
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawShadow(path, Colors.black, 8, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = edgeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _NotchedBarPainter old) =>
      old.color != color || old.edgeColor != edgeColor || old.centerX != centerX;
}
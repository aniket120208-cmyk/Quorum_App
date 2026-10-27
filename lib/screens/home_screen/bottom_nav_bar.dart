import 'package:flutter/material.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const Color barBackgroundColor = Color(0xFF0F101A);
    const Color activeColor = Color(0xFF7F77FF);
    const Color inactiveColor = Color(0xFF6E7385);

    return SizedBox(
      height: 90,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: currentIndex.toDouble(),
                end: currentIndex.toDouble(),
              ),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              builder: (context, animValue, child) {
                return CustomPaint(
                  size: Size(MediaQuery.of(context).size.width, 70),
                  painter: _NavBarPainter(
                    selectedIndex: animValue,
                    backgroundColor: barBackgroundColor,
                  ),
                );
              },
            ),
          ),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavItem(
                    icon: Icons.home_rounded,
                    label: 'Home',
                    isSelected: currentIndex == 0,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    onTap: () => onTap(0),
                    isFloating: currentIndex == 0,
                  ),
                  _NavItem(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Chat',
                    isSelected: currentIndex == 1,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    onTap: () => onTap(1),
                    isFloating: currentIndex == 1,
                  ),
                  _NavItem(
                    icon: Icons.videocam_outlined,
                    label: 'Video Call',
                    isSelected: currentIndex == 2,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    onTap: () => onTap(2),
                    isFloating: currentIndex == 2,
                  ),
                  _NavItem(
                    icon: Icons.groups_2_outlined,
                    label: 'Community',
                    isSelected: currentIndex == 3,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    onTap: () => onTap(3),
                    isFloating: currentIndex == 3,
                  ),
                  _NavItem(
                    icon: Icons.auto_awesome,
                    label: 'AI Assistant',
                    isSelected: currentIndex == 4,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    onTap: () => onTap(4),
                    isFloating: currentIndex == 4,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavBarPainter extends CustomPainter {
  final double selectedIndex;
  final Color backgroundColor;

  _NavBarPainter({
    required this.selectedIndex,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;

    final Paint borderPaint = Paint()
      ..color = const Color(0xFF1E202E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final Path path = Path();
    final double itemWidth = size.width / 5;
    final double currentCenterX = itemWidth * selectedIndex + (itemWidth / 2);

    const double cornerRadius = 24.0;
    const double notchRadius = 32.0;

    path.moveTo(0, cornerRadius);
    path.quadraticBezierTo(0, 0, cornerRadius, 0);

    final double leftCutoutStart = currentCenterX - 42;
    if (leftCutoutStart > cornerRadius) {
      path.lineTo(leftCutoutStart, 0);
    }

    path.cubicTo(
      currentCenterX - 24,
      0,
      currentCenterX - 28,
      notchRadius + 4,
      currentCenterX,
      notchRadius + 4,
    );
    path.cubicTo(
      currentCenterX + 28,
      notchRadius + 4,
      currentCenterX + 24,
      0,
      currentCenterX + 42,
      0,
    );

    final double rightCutoutEnd = size.width - cornerRadius;
    path.lineTo(rightCutoutEnd, 0);
    path.quadraticBezierTo(size.width, 0, size.width, cornerRadius);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(_NavBarPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;
  final bool isFloating;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
    required this.isFloating,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? activeColor : inactiveColor;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 60,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                top: isFloating ? -26 : 4,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  padding: EdgeInsets.all(isFloating ? 12 : 0),
                  decoration: BoxDecoration(
                    color: isFloating ? const Color(0xFF0F101A) : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: isFloating ? 26 : 24,
                    color: color,
                  ),
                ),
              ),
              Positioned(
                bottom: 2,
                child: Opacity(
                  opacity: isFloating ? 0.0 : 1.0,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
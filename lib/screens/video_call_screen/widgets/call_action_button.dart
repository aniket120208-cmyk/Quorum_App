import 'package:flutter/material.dart';

class CallActionButton extends StatelessWidget {
  const CallActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.label,
    this.isActive = false,
    this.backgroundColor,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? label;
  final bool isActive;
  final Color? backgroundColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? (isActive ? Colors.white : Colors.white24);
    final fg = iconColor ?? (isActive ? const Color(0xFF0B0C10) : Colors.white);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(icon, color: fg, size: 24),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 6),
          Text(
            label!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ],
    );
  }
}
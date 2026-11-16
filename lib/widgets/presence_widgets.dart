import 'package:flutter/material.dart';
import 'package:quorum_app/api/presence_service.dart';
import 'package:quorum_app/models/presence_models.dart';

class PresenceDot extends StatelessWidget {
  const PresenceDot({
    super.key,
    required this.status,
    this.size = 12,
    this.ringColor = const Color(0xFF0F172A),
  });

  final PresenceStatus status;
  final double size;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    final offline = status == PresenceStatus.offline;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: offline ? ringColor : status.color,
        border: Border.all(color: offline ? status.color : ringColor, width: size * 0.16),
      ),
      child: status == PresenceStatus.doNotDisturb
          ? Center(
              child: Container(
                width: size * 0.5,
                height: size * 0.14,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
              ),
            )
          : null,
    );
  }
}

class PresenceBadge extends StatefulWidget {
  const PresenceBadge({
    super.key,
    required this.userId,
    this.size = 12,
    this.ringColor = const Color(0xFF0F172A),
  });

  final String userId;
  final double size;
  final Color ringColor;

  @override
  State<PresenceBadge> createState() => _PresenceBadgeState();
}

class _PresenceBadgeState extends State<PresenceBadge> {
  @override
  void initState() {
    super.initState();
    PresenceService.instance.watch(widget.userId);
  }

  @override
  void didUpdateWidget(covariant PresenceBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) PresenceService.instance.watch(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PresenceService.instance,
      builder: (context, _) {
        final p = PresenceService.instance.of(widget.userId);
        if (p == null) return const SizedBox.shrink();
        return PresenceDot(status: p.effective, size: widget.size, ringColor: widget.ringColor);
      },
    );
  }
}

class PresenceWrap extends StatelessWidget {
  const PresenceWrap({
    super.key,
    required this.userId,
    required this.avatarSize,
    required this.child,
    this.ringColor = const Color(0xFF0F172A),
  });

  final String? userId;
  final double avatarSize;
  final Widget child;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    final id = userId;
    if (id == null || id.isEmpty) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -avatarSize * 0.04,
          bottom: -avatarSize * 0.04,
          child: PresenceBadge(userId: id, size: (avatarSize * 0.3).clamp(9.0, 16.0), ringColor: ringColor),
        ),
      ],
    );
  }
}

class PresenceLine extends StatefulWidget {
  const PresenceLine({
    super.key,
    required this.userId,
    this.style = const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
    this.ringColor = const Color(0xFF0F172A),
  });

  final String userId;
  final TextStyle style;
  final Color ringColor;

  @override
  State<PresenceLine> createState() => _PresenceLineState();
}

class _PresenceLineState extends State<PresenceLine> {
  @override
  void initState() {
    super.initState();
    PresenceService.instance.watch(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PresenceService.instance,
      builder: (context, _) {
        final p = PresenceService.instance.of(widget.userId);
        if (p == null) return const SizedBox.shrink();
        return Text(p.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: widget.style);
      },
    );
  }
}

class PresenceCountPill extends StatefulWidget {
  const PresenceCountPill({super.key, required this.userIds, this.onTap});
  final List<String> userIds;
  final VoidCallback? onTap;

  @override
  State<PresenceCountPill> createState() => _PresenceCountPillState();
}

class _PresenceCountPillState extends State<PresenceCountPill> {
  @override
  void initState() {
    super.initState();
    PresenceService.instance.watchAll(widget.userIds);
  }

  @override
  void didUpdateWidget(covariant PresenceCountPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    PresenceService.instance.watchAll(widget.userIds);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PresenceService.instance,
      builder: (context, _) {
        final n = PresenceService.instance.onlineCount(widget.userIds);
        if (n == 0) return const SizedBox.shrink();
        return GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: PresenceStatus.available.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(
                  '$n Online',
                  style: const TextStyle(color: Color(0xFF22C55E), fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/notification_router.dart';
import 'package:quorum_app/api/notification_service.dart';
import 'package:quorum_app/app_navigator.dart';
import 'package:quorum_app/models/notification_models.dart';

class NotificationBanner {
  NotificationBanner._();

  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(NotificationItem n) {
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    dismiss();
    final entry = OverlayEntry(
      builder: (_) => _BannerView(
        item: n,
        onTap: () {
          dismiss();
          NotificationService.instance.markRead(n);
          NotificationRouter.openItem(n);
        },
        onDismiss: dismiss,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(const Duration(seconds: 5), dismiss);
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

IconData notificationIcon(NotificationType t) {
  switch (t) {
    case NotificationType.orgInvite:
      return Icons.business_rounded;
    case NotificationType.teamInvite:
      return Icons.group_add_rounded;
    case NotificationType.communityInvite:
      return Icons.groups_2_rounded;
    case NotificationType.communityPostComment:
      return Icons.chat_bubble_rounded;
    case NotificationType.meetingStarted:
      return Icons.videocam_rounded;
    case NotificationType.directMessage:
      return Icons.mail_rounded;
    case NotificationType.eventReminder:
      return Icons.event_rounded;
    case NotificationType.system:
      return Icons.campaign_rounded;
  }
}

class _BannerView extends StatefulWidget {
  const _BannerView({required this.item, required this.onTap, required this.onDismiss});
  final NotificationItem item;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  State<_BannerView> createState() => _BannerViewState();
}

class _BannerViewState extends State<_BannerView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.item;
    final avatar = n.actor?.avatar;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero)
              .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
          child: Dismissible(
            key: ValueKey('banner-${n.id}'),
            direction: DismissDirection.up,
            onDismissed: (_) => widget.onDismiss(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: widget.onTap,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1C2B),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x33FFFFFF)),
                      boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: const Color(0xFF2A2C4A),
                          backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                          child: avatar == null
                              ? Icon(notificationIcon(n.type), color: const Color(0xFF7F77FF), size: 20)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                n.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                n.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFF9EA3AE), fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
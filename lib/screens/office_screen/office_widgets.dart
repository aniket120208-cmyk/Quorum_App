import 'package:flutter/material.dart';
import 'package:quorum_app/models/office_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';

const Color officeGreen = Color(0xFF22C55E);
const Color officeRed = Color(0xFFEF4444);
const Color officeAmber = Color(0xFFFBBF24);
const Color officePurple = Color(0xFF8B5CF6);

Color officePresenceColor(OfficePresence p) {
  switch (p) {
    case OfficePresence.available:
      return officeGreen;
    case OfficePresence.busy:
    case OfficePresence.doNotDisturb:
      return officeRed;
    case OfficePresence.away:
    case OfficePresence.beRightBack:
      return officeAmber;
    case OfficePresence.offline:
      return orgMuted;
  }
}

class OfficeAvatar extends StatelessWidget {
  const OfficeAvatar({super.key, required this.member, this.size = 44, this.showBadge = true});
  final OfficeMember member;
  final double size;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final dimmed = member.presence == OfficePresence.away;
    final badge = _badge();
    return Opacity(
      opacity: dimmed ? 0.5 : 1,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            OrgAvatar(name: member.name, logo: member.avatarUrl, size: size, circular: true),
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.3,
                height: size * 0.3,
                decoration: BoxDecoration(
                  color: officePresenceColor(member.presence),
                  shape: BoxShape.circle,
                  border: Border.all(color: orgCard, width: 2),
                ),
              ),
            ),
            if (showBadge && badge != null)
              Positioned(
                left: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: orgCard, shape: BoxShape.circle),
                  child: Icon(badge.$1, size: size * 0.3, color: badge.$2),
                ),
              ),
          ],
        ),
      ),
    );
  }

  (IconData, Color)? _badge() {
    if (member.presence == OfficePresence.busy || member.isInMeeting) {
      return (Icons.headphones_rounded, officeRed);
    }
    if (member.presence == OfficePresence.doNotDisturb) return (Icons.shield_rounded, officeRed);
    if (member.presence == OfficePresence.beRightBack) return (Icons.coffee_rounded, officeAmber);
    return null;
  }
}

class OfficeZoneCard extends StatelessWidget {
  const OfficeZoneCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.accent = orgTeal,
    this.highlight = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Color accent;
  final bool highlight;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x24FFFFFF), Color(0x0AFFFFFF)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: highlight ? accent : const Color(0x1FFFFFFF), width: highlight ? 1.6 : 1),
        boxShadow: [
          BoxShadow(
            color: highlight ? accent.withValues(alpha: 0.28) : Colors.black.withValues(alpha: 0.22),
            blurRadius: highlight ? 16 : 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    Text(subtitle, style: const TextStyle(color: orgMuted, fontSize: 12)),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class OfficePeopleRow extends StatelessWidget {
  const OfficePeopleRow({super.key, required this.members, required this.emptyText, required this.onTap});
  final List<OfficeMember> members;
  final String emptyText;
  final ValueChanged<OfficeMember> onTap;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return Text(emptyText, style: const TextStyle(color: orgMuted, fontSize: 12.5));
    }
    return Wrap(
      spacing: 14,
      runSpacing: 12,
      children: [
        for (final m in members)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onTap(m),
            child: SizedBox(
              width: 64,
              child: Column(
                children: [
                  OfficeAvatar(member: m, size: 44),
                  const SizedBox(height: 6),
                  Text(
                    m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                  if (m.statusMessage != null)
                    Text(
                      m.statusMessage!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: orgMuted, fontSize: 10),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class OfficeDeskTile extends StatelessWidget {
  const OfficeDeskTile({super.key, required this.desk, required this.member, required this.isMine, required this.onTap});
  final OfficeDesk desk;
  final OfficeMember? member;
  final bool isMine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final empty = desk.isEmpty;
    final color = empty ? orgBorder : officePresenceColor(m?.presence ?? OfficePresence.available);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
          color: isMine ? orgTeal.withValues(alpha: 0.1) : orgField,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isMine ? orgTeal : color.withValues(alpha: empty ? 1 : 0.55)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Desk ${desk.deskNumber}', style: const TextStyle(color: orgMuted, fontSize: 10.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (m == null)
              const Icon(Icons.event_seat_rounded, color: orgMuted, size: 30)
            else
              OfficeAvatar(member: m, size: 36),
            const SizedBox(height: 6),
            Text(
              m == null ? 'Empty' : (isMine ? 'You' : m.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: m == null ? orgMuted : Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (m?.isInMeeting == true || m?.statusMessage != null)
              Text(
                m!.statusMessage ?? 'In a meeting',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: orgMuted, fontSize: 9.5),
              ),
          ],
        ),
      ),
    );
  }
}


class OfficePillButton extends StatelessWidget {
  const OfficePillButton({super.key, required this.label, required this.onTap, this.icon, this.color = officePurple});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(color, Colors.white, 0.18)!, color],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:quorum_app/models/meeting_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';

String meetingStartLabel(BuildContext context, DateTime date) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final time = MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(date));
  return '${days[date.weekday - 1]}, ${months[date.month - 1]} ${date.day} · $time';
}

IconData meetingScopeIcon(MeetingScope scope) {
  switch (scope) {
    case MeetingScope.personal:
      return Icons.person_outline_rounded;
    case MeetingScope.organization:
      return Icons.business_rounded;
    case MeetingScope.team:
      return Icons.groups_2_outlined;
  }
}

class MeetingStatusChip extends StatelessWidget {
  const MeetingStatusChip({super.key, required this.status});
  final MeetingStatus status;

  @override
  Widget build(BuildContext context) {
    final live = status == MeetingStatus.active;
    final color = live ? orgTeal : const Color(0xFF60A5FA);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        live ? 'Live' : 'Scheduled',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class MeetingCard extends StatelessWidget {
  const MeetingCard({
    super.key,
    required this.meeting,
    required this.isHost,
    required this.canCancel,
    required this.onJoin,
    required this.onCopy,
    required this.onCancel,
  });

  final ScopedMeeting meeting;
  final bool isHost;
  final bool canCancel;
  final VoidCallback onJoin;
  final VoidCallback onCopy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final canJoin = meeting.canJoin(isHost: isHost);
    final start = meeting.scheduledStartTime;
    final opens = meeting.joinOpensAt;
    final joinLabel = meeting.isScheduled && isHost ? 'Start' : 'Join';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: orgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: orgBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  meeting.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              MeetingStatusChip(status: meeting.status),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(meetingScopeIcon(meeting.scope), color: orgMuted, size: 15),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  meeting.scopeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: orgMuted, fontSize: 12.5),
                ),
              ),
              if (meeting.hostName.isNotEmpty) ...[
                const Text('  ·  ', style: TextStyle(color: orgMuted, fontSize: 12.5)),
                Flexible(
                  child: Text(
                    isHost ? 'You are hosting' : meeting.hostName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: orgMuted, fontSize: 12.5),
                  ),
                ),
              ],
            ],
          ),
          if (start != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, color: orgMuted, size: 15),
                const SizedBox(width: 6),
                Text(
                  meetingStartLabel(context, start),
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ],
          if (meeting.isScheduled && !canJoin && opens != null) ...[
            const SizedBox(height: 6),
            Text(
              'You can join from ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(opens))}',
              style: const TextStyle(color: orgMuted, fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                height: 38,
                child: FilledButton(
                  onPressed: canJoin ? onJoin : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: orgAccent,
                    disabledBackgroundColor: orgField,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(joinLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Copy link',
                onPressed: onCopy,
                icon: const Icon(Icons.link_rounded, color: orgMuted, size: 20),
              ),
              const Spacer(),
              if (canCancel)
                TextButton(
                  onPressed: onCancel,
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
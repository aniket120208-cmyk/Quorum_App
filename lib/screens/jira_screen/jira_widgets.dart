import 'package:flutter/material.dart';
import 'package:quorum_app/models/jira_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';

Color jiraColumnColor(JiraColumn column) {
  switch (column) {
    case JiraColumn.todo:
      return const Color(0xFF60A5FA);
    case JiraColumn.inProgress:
      return const Color(0xFFFBBF24);
    case JiraColumn.done:
      return orgTeal;
  }
}

Color jiraPriorityColor(String? priority) {
  switch ((priority ?? '').toLowerCase()) {
    case 'highest':
    case 'high':
      return const Color(0xFFEF4444);
    case 'medium':
      return const Color(0xFFFBBF24);
    case 'low':
    case 'lowest':
      return const Color(0xFF60A5FA);
    default:
      return orgMuted;
  }
}

String jiraTimeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

class JiraChip extends StatelessWidget {
  const JiraChip({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class JiraTicketCard extends StatelessWidget {
  const JiraTicketCard({
    super.key,
    required this.ticket,
    this.onMove,
    this.myAccountId,
    this.showAssignee = true,
  });
  final JiraTicket ticket;
  final ValueChanged<JiraColumn>? onMove;
  final String? myAccountId;
  final bool showAssignee;

  @override
  Widget build(BuildContext context) {
    final column = ticket.column;
    final color = jiraColumnColor(column);
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: orgField,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  ticket.jiraKey,
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
              if (ticket.priority != null) ...[
                const SizedBox(width: 8),
                JiraChip(label: ticket.priority!, color: jiraPriorityColor(ticket.priority)),
              ],
              const Spacer(),
              if (onMove != null)
                PopupMenuButton<JiraColumn>(
                  tooltip: 'Move ticket',
                  padding: EdgeInsets.zero,
                  color: orgField,
                  icon: const Icon(Icons.more_vert_rounded, color: orgMuted, size: 20),
                  onSelected: onMove,
                  itemBuilder: (_) => [
                    for (final target in JiraColumn.values)
                      if (target != column)
                        PopupMenuItem<JiraColumn>(
                          value: target,
                          child: Text(
                            'Move to ${target.label}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ticket.jiraSummary,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.35),
          ),
          if (showAssignee) ...[
            const SizedBox(height: 8),
            JiraAssigneeLabel(assigneeAccountId: ticket.assigneeAccountId, myAccountId: myAccountId),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              JiraChip(label: ticket.jiraStatus.isEmpty ? column.label : ticket.jiraStatus, color: color),
              const Spacer(),
              if (ticket.lastSyncedAt != null)
                Text(
                  'Synced ${jiraTimeAgo(ticket.lastSyncedAt!)}',
                  style: const TextStyle(color: orgMuted, fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class JiraAssigneeLabel extends StatelessWidget {
  const JiraAssigneeLabel({super.key, required this.assigneeAccountId, this.myAccountId});
  final String? assigneeAccountId;
  final String? myAccountId;

  @override
  Widget build(BuildContext context) {
    final assigned = assigneeAccountId != null && assigneeAccountId!.isNotEmpty;
    final mine = assigned && assigneeAccountId == myAccountId;
    final color = mine ? orgTeal : (assigned ? Colors.white70 : orgMuted);
    final text = mine ? 'Assigned to you' : (assigned ? 'Assigned' : 'Unassigned');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(assigned ? Icons.person_rounded : Icons.person_outline_rounded, size: 15, color: color),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: color, fontSize: 12.5, fontWeight: mine ? FontWeight.w600 : FontWeight.w500)),
      ],
    );
  }
}

class JiraMessageView extends StatelessWidget {
  const JiraMessageView({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: orgMuted, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted, height: 1.4)),
            if (actionLabel != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel!, style: const TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'organization_widgets.dart';

Color taskStatusColor(TaskStatus status) {
  switch (status) {
    case TaskStatus.todo:
      return const Color(0xFF60A5FA);
    case TaskStatus.inProgress:
      return const Color(0xFFFBBF24);
    case TaskStatus.completed:
      return orgTeal;
  }
}

IconData taskStatusIcon(TaskStatus status) {
  switch (status) {
    case TaskStatus.todo:
      return Icons.radio_button_unchecked_rounded;
    case TaskStatus.inProgress:
      return Icons.timelapse_rounded;
    case TaskStatus.completed:
      return Icons.check_circle_rounded;
  }
}

String taskDueLabel(DateTime date) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    this.showTeam = false,
    this.onStatusChange,
  });

  final TeamTask task;
  final bool showTeam;
  final ValueChanged<TaskStatus>? onStatusChange;

  @override
  Widget build(BuildContext context) {
    final color = taskStatusColor(task.status);
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        color: task.status == TaskStatus.completed ? orgMuted : Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        decoration: task.status == TaskStatus.completed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (showTeam && task.teamName != null) ...[
                      const SizedBox(height: 3),
                      Text(task.teamName!, style: const TextStyle(color: orgTeal, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
              if (onStatusChange != null)
                PopupMenuButton<TaskStatus>(
                  color: orgCard,
                  icon: const Icon(Icons.more_vert_rounded, color: orgMuted, size: 20),
                  onSelected: onStatusChange,
                  itemBuilder: (context) => [
                    for (final status in TaskStatus.values)
                      if (status != task.status)
                        PopupMenuItem<TaskStatus>(
                          value: status,
                          child: Row(
                            children: [
                              Icon(taskStatusIcon(status), color: taskStatusColor(status), size: 18),
                              const SizedBox(width: 10),
                              Text('Mark as ${status.label}', style: const TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                  ],
                ),
            ],
          ),
          if (task.description != null) ...[
            const SizedBox(height: 8),
            Text(
              task.description!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: orgMuted, fontSize: 12.5, height: 1.4),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _chip(taskStatusIcon(task.status), task.status.label, color),
              if (task.dueDate != null)
                _chip(
                  Icons.event_rounded,
                  task.isOverdue ? 'Overdue · ${taskDueLabel(task.dueDate!)}' : 'Due ${taskDueLabel(task.dueDate!)}',
                  task.isOverdue ? const Color(0xFFEF4444) : orgMuted,
                ),
              if (task.assignee != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OrgAvatar(name: task.assignee!.name, logo: task.assignee!.avatar, size: 20, circular: true),
                    const SizedBox(width: 6),
                    Text(task.assignee!.name, style: const TextStyle(color: orgMuted, fontSize: 12)),
                  ],
                )
              else if (task.createdBy != null)
                Text('From ${task.createdBy!.name}', style: const TextStyle(color: orgMuted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
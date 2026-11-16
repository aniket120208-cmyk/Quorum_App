import 'package:flutter/material.dart';
import 'package:quorum_app/models/project_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';

const Color projAmber = Color(0xFFFBBF24);
const Color projGreen = Color(0xFF22C55E);
const Color projRed = Color(0xFFEF4444);
const Color projBlue = Color(0xFF60A5FA);

String projDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

String projMoney(double v) {
  final whole = v == v.roundToDouble();
  return '\$${whole ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';
}

String projFileSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

Color projStatusColor(ProjectTaskStatus s) {
  switch (s) {
    case ProjectTaskStatus.todo:
      return projBlue;
    case ProjectTaskStatus.inProgress:
      return projAmber;
    case ProjectTaskStatus.inReview:
      return const Color(0xFFA78BFA);
    case ProjectTaskStatus.completed:
      return projGreen;
    case ProjectTaskStatus.cancelled:
      return orgMuted;
  }
}

Color projPriorityColor(ProjectTaskPriority p) {
  switch (p) {
    case ProjectTaskPriority.low:
      return orgMuted;
    case ProjectTaskPriority.medium:
      return projBlue;
    case ProjectTaskPriority.high:
      return projAmber;
    case ProjectTaskPriority.urgent:
      return projRed;
  }
}

Color projRoleColor(ProjectRole r) {
  switch (r) {
    case ProjectRole.projectManager:
      return projAmber;
    case ProjectRole.internalMember:
      return projAmber;
    case ProjectRole.freelancer:
      return orgTeal;
    case ProjectRole.client:
      return const Color(0xFFA78BFA);
  }
}

class ProjChip extends StatelessWidget {
  const ProjChip({super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class ProjSheetTitle extends StatelessWidget {
  const ProjSheetTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class ProjDateField extends StatelessWidget {
  const ProjDateField({super.key, required this.label, required this.value, required this.onChanged});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 1),
          lastDate: DateTime(now.year + 10),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: orgInputDecoration(label).copyWith(
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today_rounded, size: 18, color: orgMuted)
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: orgMuted),
                  onPressed: () => onChanged(null),
                ),
        ),
        child: Text(
          value == null ? 'Not set' : projDate(value!),
          style: TextStyle(color: value == null ? const Color(0xFF5A5E6B) : Colors.white),
        ),
      ),
    );
  }
}

class ProjMemberCard extends StatelessWidget {
  const ProjMemberCard({
    super.key,
    required this.member,
    required this.showRate,
    this.onTap,
    this.trailing,
  });

  final ProjectMember member;
  final bool showRate;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: orgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: orgBorder),
        ),
        child: Row(
          children: [
            OrgAvatar(name: member.user.name, logo: member.user.avatar, size: 44, circular: true, presenceUserId: member.user.id),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                  if (member.user.email != null)
                    Text(
                      member.user.email!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: orgMuted, fontSize: 12),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ProjChip(label: member.role.label, color: projRoleColor(member.role)),
                      if (member.companyName != null)
                        ProjChip(
                          label: member.companyName!,
                          color: const Color(0xFF7C5CFC),
                          icon: Icons.business_rounded,
                        ),
                      if (showRate && member.hourlyRate != null)
                        ProjChip(label: '${projMoney(member.hourlyRate!)} / hr', color: projGreen),
                    ],
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class ProjTaskCard extends StatelessWidget {
  const ProjTaskCard({
    super.key,
    required this.task,
    required this.isManager,
    required this.isAssignee,
    required this.busy,
    required this.onTap,
    required this.onStart,
    required this.onSubmit,
    required this.onApprove,
    required this.onRequestChanges,
    required this.onOpenDeliverable,
    required this.onOpenFeedbackFile,
  });

  final ProjectTask task;
  final bool isManager;
  final bool isAssignee;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onStart;
  final VoidCallback onSubmit;
  final VoidCallback onApprove;
  final VoidCallback onRequestChanges;
  final VoidCallback onOpenDeliverable;
  final VoidCallback onOpenFeedbackFile;

  bool get _canWork => isAssignee;

  @override
  Widget build(BuildContext context) {
    final color = projStatusColor(task.status);
    final done = task.status == ProjectTaskStatus.completed;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
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
                          color: done ? orgMuted : Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          decoration: done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (task.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          task.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: orgMuted, fontSize: 12.5, height: 1.35),
                        ),
                      ],
                    ],
                  ),
                ),
                if (task.assignee != null) ...[
                  const SizedBox(width: 8),
                  OrgAvatar(name: task.assignee!.name, logo: task.assignee!.avatar, size: 28, circular: true),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ProjChip(label: task.status.label, color: color),
                ProjChip(label: task.priority.label, color: projPriorityColor(task.priority), icon: Icons.flag_rounded),
                if (task.dueDate != null)
                  ProjChip(
                    label: projDate(task.dueDate!),
                    color: task.isOverdue ? projRed : orgMuted,
                    icon: Icons.event_rounded,
                  ),
              ],
            ),
            ..._actions(),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions() {
    switch (task.status) {
      case ProjectTaskStatus.todo:
        if (!_canWork) return const [];
        return [
          const SizedBox(height: 12),
          _button('Start Task', Icons.play_arrow_rounded, orgAccent, busy ? null : onStart),
        ];
      case ProjectTaskStatus.inProgress:
        return [
          if (task.reviewFeedback != null || task.reviewFeedbackUrl != null) ...[
            const SizedBox(height: 10),
            _note('Changes requested', task.reviewFeedback ?? 'Please see the attached file.', projRed),
            if (task.reviewFeedbackUrl != null) ...[
              const SizedBox(height: 6),
              _fileRow(task.reviewFeedbackUrl!, onOpenFeedbackFile),
            ],
          ],
          if (_canWork) ...[
            const SizedBox(height: 12),
            _button('Submit Deliverable', Icons.upload_rounded, orgAccent, busy ? null : onSubmit),
          ],
        ];
      case ProjectTaskStatus.inReview:
        return [
          const SizedBox(height: 10),
          if (task.deliverableUrl != null) _deliverableRow(),
          if (task.deliverableNote != null) ...[
            const SizedBox(height: 6),
            Text(task.deliverableNote!, style: const TextStyle(color: orgMuted, fontSize: 12.5, height: 1.35)),
          ],
          const SizedBox(height: 10),
          if (isManager)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFA78BFA).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Deliverable ready for review',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _button('Approve', Icons.check_rounded, projGreen, busy ? null : onApprove)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _button('Request Changes', Icons.undo_rounded, projRed, busy ? null : onRequestChanges),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: projAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.hourglass_top_rounded, size: 16, color: projAmber),
                  SizedBox(width: 8),
                  Text(
                    'Awaiting Manager Approval',
                    style: TextStyle(color: projAmber, fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ];
      case ProjectTaskStatus.completed:
        return [
          const SizedBox(height: 10),
          const ProjChip(label: 'Approved', color: projGreen, icon: Icons.verified_rounded),
          if (task.deliverableUrl != null) ...[
            const SizedBox(height: 8),
            _deliverableRow(),
          ],
          if (task.reviewFeedback != null) ...[
            const SizedBox(height: 8),
            _note('Manager feedback', task.reviewFeedback!, projGreen),
          ],
          if (task.reviewFeedbackUrl != null) ...[
            const SizedBox(height: 6),
            _fileRow(task.reviewFeedbackUrl!, onOpenFeedbackFile),
          ],
        ];
      case ProjectTaskStatus.cancelled:
        return const [];
    }
  }

  Widget _deliverableRow() => _fileRow(task.deliverableUrl!, onOpenDeliverable);

  Widget _fileRow(String url, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            const Icon(Icons.attach_file_rounded, size: 16, color: orgTeal),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: orgTeal,
                  fontSize: 12.5,
                  decoration: TextDecoration.underline,
                  decorationColor: orgTeal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _note(String title, String body, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(body, style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.35)),
        ],
      ),
    );
  }

  Widget _button(String label, IconData icon, Color color, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.4),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white60,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
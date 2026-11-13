import 'package:flutter/material.dart';
import 'package:quorum_app/api/recording_uploader.dart';
import 'package:quorum_app/models/recording_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';

String recDuration(int? seconds) {
  if (seconds == null) return '--:--';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String recSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String recDate(DateTime? d) {
  if (d == null) return '';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final mm = d.minute.toString().padLeft(2, '0');
  return '${months[d.month - 1]} ${d.day}, ${d.year} · $h:$mm ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String recExpiry(DateTime? expiresAt) {
  if (expiresAt == null) return '';
  final left = expiresAt.difference(DateTime.now());
  if (left.isNegative) return 'Expired';
  if (left.inDays >= 1) return 'Deleted in ${left.inDays} day${left.inDays == 1 ? '' : 's'}';
  if (left.inHours >= 1) return 'Deleted in ${left.inHours} h';
  return 'Deleted soon';
}

Color recStatusColor(RecordingStatus s) {
  switch (s) {
    case RecordingStatus.recording:
      return const Color(0xFFEF4444);
    case RecordingStatus.processing:
      return const Color(0xFFFBBF24);
    case RecordingStatus.completed:
      return const Color(0xFF22C55E);
    case RecordingStatus.failed:
      return const Color(0xFFEF4444);
  }
}

String recStatusLabel(RecordingStatus s) {
  switch (s) {
    case RecordingStatus.recording:
      return 'Recording';
    case RecordingStatus.processing:
      return 'Processing';
    case RecordingStatus.completed:
      return 'Ready';
    case RecordingStatus.failed:
      return 'Failed';
  }
}

class RecStatusChip extends StatelessWidget {
  const RecStatusChip({super.key, required this.status});
  final RecordingStatus status;

  @override
  Widget build(BuildContext context) {
    final color = recStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
      child: Text(
        recStatusLabel(status),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class RecUploadCard extends StatelessWidget {
  const RecUploadCard({super.key, required this.job, required this.onRetry, required this.onDismiss});
  final RecordingJob job;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: job,
      builder: (context, _) {
        final failed = job.stage == RecordingJobStage.failed;
        final done = job.stage == RecordingJobStage.done;
        final color = failed ? const Color(0xFFEF4444) : done ? const Color(0xFF22C55E) : orgTeal;
        final String title;
        switch (job.stage) {
          case RecordingJobStage.queued:
          case RecordingJobStage.preparing:
            title = 'Preparing upload...';
          case RecordingJobStage.uploading:
            title = 'Uploading recording ${(job.progress * 100).clamp(0, 100).toStringAsFixed(0)}%';
          case RecordingJobStage.finalizing:
            title = 'Finalizing recording...';
          case RecordingJobStage.done:
            title = 'Recording uploaded. Processing...';
          case RecordingJobStage.failed:
            title = 'Upload failed';
        }
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: orgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    failed ? Icons.error_outline_rounded : done ? Icons.check_circle_rounded : Icons.cloud_upload_rounded,
                    color: color,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (failed || done)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onDismiss,
                      icon: const Icon(Icons.close_rounded, color: orgMuted, size: 18),
                    ),
                ],
              ),
              if (!failed && !done) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: job.stage == RecordingJobStage.uploading ? job.progress : null,
                    minHeight: 6,
                    color: orgTeal,
                    backgroundColor: orgField,
                  ),
                ),
              ],
              if (failed) ...[
                const SizedBox(height: 6),
                Text(job.error ?? 'Something went wrong.', style: const TextStyle(color: orgMuted, fontSize: 12.5)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry upload'),
                    style: FilledButton.styleFrom(
                      backgroundColor: orgAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
import 'package:flutter/material.dart';
import 'package:quorum_app/models/meeting_models.dart';
import 'package:quorum_app/screens/document_screen/document_editor_screen.dart';

class MeetingDocumentPanel extends StatelessWidget {
  const MeetingDocumentPanel({
    super.key,
    required this.document,
    required this.meetingCode,
    required this.canClose,
    required this.onHide,
    required this.onClose,
  });

  final MeetingDocument document;
  final String meetingCode;
  final bool canClose;
  final VoidCallback onHide;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: DocumentEditorScreen(
          key: ValueKey(document.documentId),
          documentId: document.documentId,
          initialTitle: document.title,
          meetingCode: meetingCode,
          embedded: true,
          headerActions: [
            IconButton(
              tooltip: 'Hide document',
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              onPressed: onHide,
            ),
            if (canClose)
              IconButton(
                tooltip: 'Close for everyone',
                icon: const Icon(Icons.close_rounded),
                onPressed: onClose,
              ),
          ],
        ),
      ),
    );
  }
}
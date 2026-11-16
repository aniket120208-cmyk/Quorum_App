import 'package:flutter/material.dart';
import 'package:quorum_app/widgets/copyable_id_tile.dart';

Future<void> showIdDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String value,
  required Color background,
  required Color titleColor,
  required Color mutedColor,
  required Color valueColor,
  required Color borderColor,
  required Color accentColor,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: titleColor, fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              CopyableIdTile(
                label: label,
                value: value,
                labelColor: mutedColor,
                valueColor: valueColor,
                borderColor: borderColor,
                accentColor: accentColor,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text('Close', style: TextStyle(color: mutedColor)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

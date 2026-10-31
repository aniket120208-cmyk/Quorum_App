import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CopyableIdTile extends StatelessWidget {
  const CopyableIdTile({
    super.key,
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
    required this.borderColor,
    required this.accentColor,
  });

  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;
  final Color borderColor;
  final Color accentColor;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$label copied'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: labelColor, fontSize: 11.5)),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: TextStyle(
                    color: valueColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy ID',
            onPressed: () => _copy(context),
            icon: Icon(Icons.copy_rounded, size: 18, color: accentColor),
          ),
        ],
      ),
    );
  }
}
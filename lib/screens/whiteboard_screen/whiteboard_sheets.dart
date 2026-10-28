import 'package:flutter/material.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';

class WhiteboardNameSheet extends StatefulWidget {
  const WhiteboardNameSheet({
    super.key,
    required this.title,
    required this.action,
    this.initialName = '',
  });

  final String title;
  final String action;
  final String initialName;

  @override
  State<WhiteboardNameSheet> createState() => _WhiteboardNameSheetState();
}

class _WhiteboardNameSheetState extends State<WhiteboardNameSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _name.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 80,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Whiteboard name',
              hintStyle: const TextStyle(color: orgMuted),
              errorText: _error,
              counterText: '',
              filled: true,
              fillColor: orgField,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: orgAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(widget.action, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class WhiteboardTextDialog extends StatefulWidget {
  const WhiteboardTextDialog({super.key});

  @override
  State<WhiteboardTextDialog> createState() => _WhiteboardTextDialogState();
}

class _WhiteboardTextDialogState extends State<WhiteboardTextDialog> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: orgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Add text', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: _text,
        autofocus: true,
        minLines: 1,
        maxLines: 5,
        maxLength: 500,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Type something',
          hintStyle: const TextStyle(color: orgMuted),
          filled: true,
          fillColor: orgField,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: orgMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _text.text),
          child: const Text('Add', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
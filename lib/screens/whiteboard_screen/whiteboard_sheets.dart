import 'package:flutter/material.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'whiteboard_controller.dart';

const List<Color> whiteboardPalette = [
  Color(0xFF0F172A),
  Color(0xFFF8FAFC),
  Color(0xFFEF4444),
  Color(0xFFF59E0B),
  Color(0xFF22C55E),
  Color(0xFF3B82F6),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
];

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

const List<double> _textSizes = [16, 24, 36, 56];
const List<String> _textSizeLabels = ['S', 'M', 'L', 'XL'];

Future<WhiteboardTextResult?> showWhiteboardTextSheet(
  BuildContext context, {
  String initialText = '',
  double initialSize = 24,
  required Color initialColor,
  required Color canvasColor,
  bool editing = false,
}) {
  return showModalBottomSheet<WhiteboardTextResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: orgCard,
    shape: orgSheetShape,
    builder: (_) => WhiteboardTextSheet(
      initialText: initialText,
      initialSize: initialSize,
      initialColor: initialColor,
      canvasColor: canvasColor,
      editing: editing,
    ),
  );
}

class WhiteboardTextSheet extends StatefulWidget {
  const WhiteboardTextSheet({
    super.key,
    required this.initialText,
    required this.initialSize,
    required this.initialColor,
    required this.canvasColor,
    required this.editing,
  });

  final String initialText;
  final double initialSize;
  final Color initialColor;
  final Color canvasColor;
  final bool editing;

  @override
  State<WhiteboardTextSheet> createState() => _WhiteboardTextSheetState();
}

class _WhiteboardTextSheetState extends State<WhiteboardTextSheet> {
  late final TextEditingController _text = TextEditingController(text: widget.initialText);
  late double _size = widget.initialSize;
  late Color _color = widget.initialColor;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(context, WhiteboardTextResult(text: value, fontSize: _size, color: _color));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.editing ? 'Edit text' : 'Add text',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: orgMuted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 84, maxHeight: 150),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: widget.canvasColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: orgBorder),
                ),
                child: SingleChildScrollView(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _text,
                    builder: (context, value, _) => Text(
                      value.text.isEmpty ? 'Preview' : value.text,
                      style: TextStyle(
                        color: value.text.isEmpty ? _color.withOpacity(0.4) : _color,
                        fontSize: _size,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _text,
                autofocus: true,
                minLines: 1,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(color: Colors.white),
                cursorColor: orgTeal,
                decoration: InputDecoration(
                  hintText: 'Type something',
                  hintStyle: const TextStyle(color: orgMuted),
                  filled: true,
                  fillColor: orgField,
                  counterStyle: const TextStyle(color: orgMuted),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: orgTeal, width: 1.2),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (var i = 0; i < _textSizes.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_textSizeLabels[i]),
                        selected: _size == _textSizes[i],
                        onSelected: (_) => setState(() => _size = _textSizes[i]),
                        selectedColor: const Color(0xFF16302F),
                        backgroundColor: orgField,
                        side: BorderSide(color: _size == _textSizes[i] ? orgTeal : orgBorder),
                        labelStyle: TextStyle(
                          color: _size == _textSizes[i] ? orgTeal : orgMuted,
                          fontWeight: FontWeight.w700,
                        ),
                        showCheckmark: false,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final c in whiteboardPalette)
                      GestureDetector(
                        onTap: () => setState(() => _color = c),
                        child: Container(
                          width: 30,
                          height: 30,
                          margin: const EdgeInsets.only(right: 10, top: 2, bottom: 2),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color.value == c.value ? orgTeal : orgBorder,
                              width: _color.value == c.value ? 2.5 : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _text,
                builder: (context, value, _) => SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: value.text.trim().isEmpty ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: orgAccent,
                      disabledBackgroundColor: orgField,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      widget.editing ? 'Save' : 'Add to board',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
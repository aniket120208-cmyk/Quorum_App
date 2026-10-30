import 'package:flutter/material.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';

const Map<String, List<String>> whiteboardEmojiGroups = {
  'Faces': [
    '😀', '😁', '😂', '🤣', '😊', '😍', '😎', '🤔', '😮', '😢', '😡', '🥳',
    '😴', '🤯', '🙄', '😇', '😅', '😉', '🥹', '😬', '🤩', '😭', '🤗', '🫡',
  ],
  'Gestures': [
    '👍', '👎', '👏', '🙌', '🙏', '💪', '👀', '✌️', '👌', '🤝', '👋', '☝️',
    '🤞', '🫶', '✍️', '👉',
  ],
  'Symbols': [
    '❤️', '🔥', '⭐', '✨', '💡', '✅', '❌', '⚠️', '❓', '❗', '🎯', '🚀',
    '🎉', '💯', '🔔', '🚩', '➕', '➖', '🔁', '⏰',
  ],
  'Work': [
    '📌', '📎', '📅', '💻', '📱', '🔒', '🔑', '📊', '📈', '📉', '💬', '📝',
    '📁', '🧩', '🛠️', '🧪', '🏆', '💰', '📣', '🗂️',
  ],
  'Nature & Food': [
    '🌟', '🌈', '☀️', '🌙', '🌱', '🌳', '🌸', '🍕', '☕', '🍎', '🍔', '🍰',
    '🐶', '🐱', '🦄', '🌍',
  ],
};

const List<String> whiteboardQuickEmojis = [
  '😀', '😂', '😍', '🤔', '👍', '👏', '❤️', '🔥', '⭐', '✅', '❌', '💡', '🎯', '🚀', '🎉', '📌',
];

Future<String?> showWhiteboardEmojiPicker(BuildContext context, {String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: orgCard,
    shape: orgSheetShape,
    builder: (_) => _EmojiSheet(current: current),
  );
}

class _EmojiSheet extends StatelessWidget {
  const _EmojiSheet({this.current});
  final String? current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          shrinkWrap: true,
          children: [
            const Text(
              'Choose an emoji',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            for (final entry in whiteboardEmojiGroups.entries) ...[
              const SizedBox(height: 16),
              Text(
                entry.key,
                style: const TextStyle(color: orgMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final emoji in entry.value)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(context, emoji),
                      child: Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: emoji == current ? const Color(0xFF16302F) : orgField,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: emoji == current ? orgTeal : Colors.transparent),
                        ),
                        child: Text(emoji, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:quorum_app/models/chat_models.dart';
import 'chat_widgets.dart';

const Color mentionAmber = Color(0xFFFBBF24);

Set<String> mentionNamesFor(ChatMessage message, List<ChatUser> members) {
  final names = <String>{};
  for (final u in message.mentionedUsers) {
    if (u.name.isNotEmpty) names.add(u.name);
  }
  for (final id in message.mentionedUserIds) {
    for (final u in members) {
      if (u.id == id && u.name.isNotEmpty) names.add(u.name);
    }
  }
  return names;
}

Set<String> myMentionNamesFor(ChatMessage message, List<ChatUser> members, String myId) {
  final names = <String>{};
  if (!message.mentions(myId)) return names;
  for (final u in message.mentionedUsers) {
    if (u.id == myId && u.name.isNotEmpty) names.add(u.name);
  }
  for (final u in members) {
    if (u.id == myId && u.name.isNotEmpty) names.add(u.name);
  }
  return names;
}

class MentionSuggestionList extends StatelessWidget {
  const MentionSuggestionList({super.key, required this.users, required this.onPick});
  final List<ChatUser> users;
  final ValueChanged<ChatUser> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: users.length,
        itemBuilder: (_, i) {
          final u = users[i];
          final email = u.email;
          return ListTile(
            dense: true,
            leading: ChatAvatar(name: u.name, imageUrl: u.avatarUrl, radius: 15),
            title: Text(
              u.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: (email != null && email.isNotEmpty)
                ? Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  )
                : null,
            onTap: () => onPick(u),
          );
        },
      ),
    );
  }
}

class MentionText extends StatelessWidget {
  const MentionText({
    super.key,
    required this.text,
    required this.names,
    required this.myNames,
    required this.isMe,
    required this.style,
  });

  final String text;
  final Set<String> names;
  final Set<String> myNames;
  final bool isMe;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return Text(text, style: style);
    final sorted = names.toList()..sort((a, b) => b.length.compareTo(a.length));
    final pattern = RegExp(
      '@(${sorted.map(RegExp.escape).join('|')})(?!\\w)',
      caseSensitive: false,
    );
    final lowerMine = myNames.map((e) => e.toLowerCase()).toSet();
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > cursor) spans.add(TextSpan(text: text.substring(cursor, m.start)));
      final mine = lowerMine.contains(m.group(1)!.toLowerCase());
      final Color fg = mine ? mentionAmber : (isMe ? Colors.white : AppColors.primaryLight);
      final Color bg = mine
          ? mentionAmber.withValues(alpha: 0.22)
          : (isMe ? Colors.white.withValues(alpha: 0.18) : AppColors.primary.withValues(alpha: 0.2));
      spans.add(TextSpan(
        text: m.group(0),
        style: TextStyle(fontWeight: FontWeight.w700, color: fg, backgroundColor: bg),
      ));
      cursor = m.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}
import 'package:flutter/material.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';

class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.data});
  final String data;
  static final RegExp _bullet = RegExp(r'^(\s*)[-*•]\s+(.*)$');
  static final RegExp _task = RegExp(r'^\[( |x|X)\]\s+(.*)$');
  static final RegExp _numbered = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$');
  static final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*)$');

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    final lines = data.replaceAll('\r\n', '\n').split('\n');
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 8));
        continue;
      }
      final heading = _heading.firstMatch(line.trim());
      if (heading != null) {
        final level = heading.group(1)!.length;
        children.add(Padding(
          padding: EdgeInsets.only(top: level <= 2 ? 14 : 10, bottom: 4),
          child: Text(
            _strip(heading.group(2)!),
            style: TextStyle(
              color: Colors.white,
              fontSize: level == 1 ? 20 : level == 2 ? 18 : 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ));
        continue;
      }
      final bullet = _bullet.firstMatch(line);
      if (bullet != null) {
        final indent = (bullet.group(1)!.length ~/ 2).clamp(0, 4) * 14.0;
        final body = bullet.group(2)!;
        final task = _task.firstMatch(body);
        children.add(Padding(
          padding: EdgeInsets.only(left: indent, top: 3, bottom: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (task != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 1),
                  child: Icon(
                    task.group(1) == ' ' ? Icons.check_box_outline_blank_rounded : Icons.check_box_rounded,
                    size: 18,
                    color: task.group(1) == ' ' ? orgMuted : orgTeal,
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(right: 10, top: 8),
                  child: Icon(Icons.circle, size: 5, color: orgTeal),
                ),
              Expanded(child: _rich(task != null ? task.group(2)! : body)),
            ],
          ),
        ));
        continue;
      }
      final numbered = _numbered.firstMatch(line);
      if (numbered != null) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '${numbered.group(2)}.',
                  style: const TextStyle(color: orgTeal, fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(child: _rich(numbered.group(3)!)),
            ],
          ),
        ));
        continue;
      }
      children.add(Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: _rich(line.trim())));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  String _strip(String text) => text.replaceAll('**', '').replaceAll('__', '').replaceAll('`', '');

  Widget _rich(String text) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(\*\*[^*]+\*\*|__[^_]+__|`[^`]+`)');
    var last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final token = m.group(0)!;
      if (token.startsWith('`')) {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: const TextStyle(fontFamily: 'monospace', color: orgTeal, backgroundColor: Color(0x22FFFFFF)),
        ));
      } else {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
        ));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(
      TextSpan(children: spans),
      style: const TextStyle(color: Color(0xFFD7DAE0), fontSize: 14, height: 1.45),
    );
  }
}
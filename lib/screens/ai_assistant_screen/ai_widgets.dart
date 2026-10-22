import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quorum_app/models/ai_model.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';

void showToast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF334155),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
}

Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showToast(context, 'Copied');
}

class AiRichText extends StatelessWidget {
  const AiRichText(this.text, {super.key});
  final String text;

  static const TextStyle _base = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 14,
    height: 1.45,
  );

  List<InlineSpan> _inline(String s) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`');
    var last = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > last) spans.add(TextSpan(text: s.substring(last, m.start)));
      if (m.group(1) != null) {
        spans.add(TextSpan(
          text: m.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ));
      } else {
        spans.add(TextSpan(
          text: m.group(2),
          style: const TextStyle(
            fontFamily: 'monospace',
            backgroundColor: Color(0x33FFFFFF),
          ),
        ));
      }
      last = m.end;
    }
    if (last < s.length) spans.add(TextSpan(text: s.substring(last)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    final bullet = RegExp(r'^\s*[-*•]\s+(.*)$');
    final numbered = RegExp(r'^\s*(\d+)[.)]\s+(.*)$');
    final heading = RegExp(r'^\s*#{1,6}\s+(.*)$');

    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 8));
        continue;
      }

      final h = heading.firstMatch(line);
      if (h != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text.rich(
            TextSpan(
              children: _inline(h.group(1)!),
              style: _base.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryLight,
              ),
            ),
          ),
        ));
        continue;
      }

      final b = bullet.firstMatch(line);
      final n = numbered.firstMatch(line);
      if (b != null || n != null) {
        final marker = b != null ? '•' : '${n!.group(1)}.';
        final body = b != null ? b.group(1)! : n!.group(2)!;
        children.add(Padding(
          padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text(marker, style: _base),
              ),
              Expanded(
                child: Text.rich(TextSpan(children: _inline(body), style: _base)),
              ),
            ],
          ),
        ));
        continue;
      }

      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Text.rich(TextSpan(children: _inline(line), style: _base)),
      ));
    }

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class UserPromptBubble extends StatelessWidget {
  const UserPromptBubble({super.key, required this.turn});
  final AiTurn turn;

  @override
  Widget build(BuildContext context) {
    final text = turn.prompt.isEmpty ? (turn.caption ?? '') : turn.prompt;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(turn.mode.icon, size: 12, color: Colors.white70),
                const SizedBox(width: 4),
                Text(
                  turn.mode.label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              text,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
            if (turn.caption != null && turn.prompt.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  turn.caption!,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AiResponseCard extends StatelessWidget {
  const AiResponseCard({super.key, required this.turn, required this.onRetry});
  final AiTurn turn;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.92,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    switch (turn.state) {
      case TurnState.loading:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
            SizedBox(width: 12),
            Text('Thinking…', style: TextStyle(color: AppColors.textSecondary)),
          ],
        );
      case TurnState.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    turn.error ?? 'Something went wrong.',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.surfaceBorder),
              ),
            ),
          ],
        );
      case TurnState.done:
        return _result(context, turn.result ?? const AiResult());
    }
  }

  Widget _result(BuildContext context, AiResult r) {
    final children = <Widget>[];

    if (r.project != null) {
      children.add(ProjectInfoCard(project: r.project!));
      children.add(const SizedBox(height: 10));
    }

    if (r.facts.isNotEmpty) {
      children.add(Wrap(
        spacing: 8,
        runSpacing: 8,
        children: r.facts.entries
            .map((e) => InfoChip(label: e.key, value: '${e.value}'))
            .toList(),
      ));
      children.add(const SizedBox(height: 10));
    }

    if (r.target != null && r.target!.isNotEmpty) {
      children.add(Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F101A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          r.target!,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ));
      children.add(const SizedBox(height: 10));
    }

    if (r.answer.isNotEmpty) {
      children.add(AiRichText(r.answer));
    }

    if (r.suggestions.isNotEmpty) {
      for (var i = 0; i < r.suggestions.length; i++) {
        children.add(SuggestionTile(index: i + 1, text: r.suggestions[i]));
      }
    }

    if (r.sources.isNotEmpty) {
      children.add(const SizedBox(height: 12));
      children.add(const Text(
        'Sources',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ));
      children.add(const SizedBox(height: 6));
      for (final s in r.sources) {
        children.add(SourceTile(source: s));
      }
    } else if (turn.mode == AiMode.search && r.answer.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(const Text(
        'No sources were returned for this answer.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ));
    }

    if (r.disclaimer != null && r.disclaimer!.isNotEmpty) {
      children.add(const SizedBox(height: 10));
      children.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              r.disclaimer!,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ));
    }

    if (r.note != null && r.note!.isNotEmpty) {
      children.add(const SizedBox(height: 6));
      children.add(Text(
        'Data source: ${r.note!.replaceAll('_', ' ')}',
        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
      ));
    }

    if (r.answer.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(Row(
        children: [
          if (r.meta != null && r.meta!.model.isNotEmpty)
            Expanded(
              child: Text(
                r.meta!.model,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
              ),
            )
          else
            const Spacer(),
          InkWell(
            onTap: () => copyText(context, r.answer),
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_rounded, size: 14, color: AppColors.textSecondary),
                  SizedBox(width: 4),
                  Text('Copy',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ));
    }

    if (children.isEmpty) {
      return const Text(
        'No response was returned.',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F101A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppColors.primaryLight,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class ProjectInfoCard extends StatelessWidget {
  const ProjectInfoCard({super.key, required this.project});
  final AiProject project;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F101A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  project.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  project.type,
                  style: const TextStyle(
                    color: AppColors.primaryLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (project.description != null && project.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              project.description!,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InfoChip(label: 'members', value: '${project.memberCount}'),
              if (project.teamCount != null)
                InfoChip(label: 'teams', value: '${project.teamCount}'),
              if (project.discussionCount != null)
                InfoChip(label: 'discussions', value: '${project.discussionCount}'),
            ],
          ),
        ],
      ),
    );
  }
}

class SuggestionTile extends StatelessWidget {
  const SuggestionTile({super.key, required this.index, required this.text});
  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F101A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              '$index',
              style: const TextStyle(
                color: AppColors.primaryLight,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.textSecondary),
            onPressed: () => copyText(context, text),
          ),
        ],
      ),
    );
  }
}

class SourceTile extends StatelessWidget {
  const SourceTile({super.key, required this.source});
  final AiSource source;

  IconData get _icon {
    switch (source.type) {
      case 'message':
        return Icons.chat_bubble_outline;
      case 'community_post':
        return Icons.forum_outlined;
      case 'organization':
        return Icons.business_outlined;
      case 'meeting':
        return Icons.event_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(source.url ?? '');
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showErrorSnack(context, 'Could not open this link');
  }

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (source.author.isNotEmpty) source.author,
      if (source.createdAt != null) formatListTime(source.createdAt!),
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F101A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: (source.url == null || source.url!.isEmpty)
            ? null
            : () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon, size: 18, color: AppColors.primaryLight),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (source.snippet.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          source.snippet,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          meta,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
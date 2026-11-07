import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quorum_app/models/github_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';

const Color githubOpen = Color(0xFF3FB950);
const Color githubMerged = Color(0xFFA371F7);
const Color githubClosed = Color(0xFFF85149);
const Color githubDraft = Color(0xFF8B949E);

String githubTimeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30}mo ago';
  return '${diff.inDays ~/ 365}y ago';
}

Color githubLabelColor(String? hex) {
  if (hex == null) return orgMuted;
  final cleaned = hex.replaceAll('#', '');
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null || cleaned.length != 6) return orgMuted;
  return Color(0xFF000000 | value);
}

Future<void> openGithubUrl(BuildContext context, String? url) async {
  if (url == null || url.isEmpty) {
    orgToast(context, 'No link available', error: true);
    return;
  }
  try {
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) orgToast(context, 'Could not open the link', error: true);
  } catch (_) {
    if (context.mounted) orgToast(context, 'Could not open the link', error: true);
  }
}

class GithubChip extends StatelessWidget {
  const GithubChip({super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class GithubLabelChip extends StatelessWidget {
  const GithubLabelChip({super.key, required this.label});
  final GithubLabel label;

  @override
  Widget build(BuildContext context) {
    final color = githubLabelColor(label.color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: orgField,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label.name, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class GithubAvatar extends StatelessWidget {
  const GithubAvatar({super.key, required this.login, this.url, this.size = 22});
  final String login;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: orgAccent, shape: BoxShape.circle),
      child: Text(
        login.isEmpty ? '?' : login[0].toUpperCase(),
        style: TextStyle(color: Colors.white, fontSize: size * 0.5, fontWeight: FontWeight.w700),
      ),
    );
    final src = url;
    if (src == null || src.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        src,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => fallback,
      ),
    );
  }
}

class GithubAvatarStack extends StatelessWidget {
  const GithubAvatarStack({super.key, required this.users, this.size = 22, this.max = 4});
  final List<GithubUser> users;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = users.take(max).toList();
    final extra = users.length - shown.length;
    final overlap = size * 0.7;
    return SizedBox(
      height: size,
      width: shown.isEmpty ? 0 : overlap * (shown.length - 1) + size + (extra > 0 ? 26 : 0),
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * overlap,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: orgCard, width: 1.5),
                ),
                child: GithubAvatar(login: shown[i].login, url: shown[i].avatarUrl, size: size),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: overlap * (shown.length - 1) + size + 6,
              top: 0,
              bottom: 0,
              child: Center(
                child: Text('+$extra', style: const TextStyle(color: orgMuted, fontSize: 11)),
              ),
            ),
        ],
      ),
    );
  }
}

class GithubMessageView extends StatelessWidget {
  const GithubMessageView({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: orgMuted, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted, height: 1.4)),
            if (actionLabel != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel!, style: const TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class GithubStateFilter extends StatelessWidget {
  const GithubStateFilter({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [('open', 'Open'), ('closed', 'Closed'), ('all', 'All')];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          for (final option in options) ...[
            ChoiceChip(
              label: Text(option.$2),
              selected: option.$1 == value,
              onSelected: (_) => onChanged(option.$1),
              showCheckmark: false,
              selectedColor: orgAccent,
              backgroundColor: orgField,
              side: const BorderSide(color: orgBorder),
              labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class GithubIssueCard extends StatelessWidget {
  const GithubIssueCard({super.key, required this.issue, required this.onToggleState, required this.onOpen});
  final GithubIssue issue;
  final VoidCallback onToggleState;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final open = issue.isOpen;
    final color = open ? githubOpen : githubMerged;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: orgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: orgBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(open ? Icons.adjust_rounded : Icons.check_circle_outline_rounded, color: color, size: 18),
                const SizedBox(width: 8),
                Text('#${issue.number}', style: const TextStyle(color: orgMuted, fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                GithubChip(label: open ? 'Open' : 'Closed', color: color),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'Issue actions',
                  padding: EdgeInsets.zero,
                  color: orgField,
                  icon: const Icon(Icons.more_vert_rounded, color: orgMuted, size: 20),
                  onSelected: (value) => value == 'toggle' ? onToggleState() : onOpen(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(open ? 'Close issue' : 'Reopen issue', style: const TextStyle(color: Colors.white)),
                    ),
                    const PopupMenuItem(
                      value: 'open',
                      child: Text('View on GitHub', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              issue.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.35),
            ),
            if (issue.labels.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final label in issue.labels) GithubLabelChip(label: label)],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (issue.user != null) ...[
                  GithubAvatar(login: issue.user!.login, url: issue.user!.avatarUrl, size: 20),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      issue.user!.login,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
                if (issue.createdAt != null) ...[
                  const SizedBox(width: 8),
                  Text(githubTimeAgo(issue.createdAt!), style: const TextStyle(color: orgMuted, fontSize: 11.5)),
                ],
                const Spacer(),
                if (issue.assignees.isNotEmpty) ...[
                  GithubAvatarStack(users: issue.assignees, size: 20),
                  const SizedBox(width: 10),
                ],
                const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: orgMuted),
                const SizedBox(width: 4),
                Text('${issue.comments}', style: const TextStyle(color: orgMuted, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class GithubPullCard extends StatelessWidget {
  const GithubPullCard({super.key, required this.pull, required this.onOpen});
  final GithubPull pull;
  final VoidCallback onOpen;

  Color get _color {
    if (pull.merged) return githubMerged;
    if (pull.draft) return githubDraft;
    return pull.isOpen ? githubOpen : githubClosed;
  }

  String get _label {
    if (pull.merged) return 'Merged';
    if (pull.draft) return 'Draft';
    return pull.isOpen ? 'Open' : 'Closed';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: orgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: orgBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.call_merge_rounded, color: _color, size: 18),
              const SizedBox(width: 8),
              Text('#${pull.number}', style: const TextStyle(color: orgMuted, fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              GithubChip(label: _label, color: _color),
              const Spacer(),
              if (pull.createdAt != null)
                Text(githubTimeAgo(pull.createdAt!), style: const TextStyle(color: orgMuted, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            pull.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.35),
          ),
          if (pull.headRef != null || pull.baseRef != null) ...[
            const SizedBox(height: 10),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                _branch(pull.headRef ?? '?'),
                const Icon(Icons.arrow_forward_rounded, size: 14, color: orgMuted),
                _branch(pull.baseRef ?? '?'),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (pull.user != null) ...[
                GithubAvatar(login: pull.user!.login, url: pull.user!.avatarUrl, size: 20),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    pull.user!.login,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
              const Spacer(),
              if (pull.reviewers.isNotEmpty) ...[
                const Text('Reviewers', style: TextStyle(color: orgMuted, fontSize: 11)),
                const SizedBox(width: 8),
                GithubAvatarStack(users: pull.reviewers, size: 20),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_rounded, size: 16, color: orgTeal),
              label: const Text(
                'Review on GitHub ↗',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: orgBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _branch(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: orgField, borderRadius: BorderRadius.circular(8)),
      child: Text(
        name,
        style: const TextStyle(color: orgTeal, fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class GithubCommitTile extends StatelessWidget {
  const GithubCommitTile({super.key, required this.commit, required this.onOpen});
  final GithubCommit commit;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: orgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: orgBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: orgField, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    commit.shortSha,
                    style: const TextStyle(
                      color: orgTeal,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(Icons.open_in_new_rounded, size: 15, color: orgMuted),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              commit.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                GithubAvatar(login: commit.displayAuthor, url: commit.author?.avatarUrl, size: 20),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    commit.displayAuthor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                if (commit.date != null) ...[
                  const SizedBox(width: 8),
                  Text('committed ${githubTimeAgo(commit.date!)}', style: const TextStyle(color: orgMuted, fontSize: 11.5)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
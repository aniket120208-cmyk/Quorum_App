import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quorum_app/models/poll_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';

String pollVoteLabel(int count) => count == 1 ? '1 vote' : '$count votes';

class PollCard extends StatelessWidget {
  const PollCard({
    super.key,
    required this.poll,
    required this.myId,
    this.mine = false,
    this.onVote,
    this.onClose,
    this.pending = false,
  });

  final Poll poll;
  final String myId;
  final bool mine;
  final ValueChanged<String>? onVote;
  final VoidCallback? onClose;
  final bool pending;

  String get _hint {
    if (poll.isClosed) return 'Poll closed';
    if (pending) return 'Sending poll…';
    return poll.allowMultipleAnswers ? 'Select one or more' : 'Select one';
  }

  @override
  Widget build(BuildContext context) {
    final muted = mine ? Colors.white70 : AppColors.textSecondary;
    final interactive = onVote != null && !poll.isClosed && !pending;
    final total = poll.totalVotes;
    final canOpenVoters = total > 0 && !pending && onVote != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.poll_rounded, size: 18, color: muted),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  poll.question,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(_hint, style: TextStyle(color: muted, fontSize: 12)),
          ),
          const SizedBox(height: 10),
          for (final option in poll.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _PollOptionRow(
                option: option,
                selected: poll.votedFor(option.id),
                multiple: poll.allowMultipleAnswers,
                fraction: total == 0 ? 0 : (option.voteCount / total).clamp(0.0, 1.0).toDouble(),
                mine: mine,
                onTap: interactive ? () => onVote!(option.id) : null,
              ),
            ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: canOpenVoters ? () => showPollVotersSheet(context, poll, myId) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          total == 0 ? 'No votes yet' : pollVoteLabel(poll.uniqueVotersCount),
                          style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        if (canOpenVoters) ...[
                          const SizedBox(width: 2),
                          Icon(Icons.chevron_right_rounded, size: 16, color: muted),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (onClose != null && !poll.isClosed)
                TextButton(
                  onPressed: onClose,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Close poll', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PollOptionRow extends StatelessWidget {
  const _PollOptionRow({
    required this.option,
    required this.selected,
    required this.multiple,
    required this.fraction,
    required this.mine,
    required this.onTap,
  });

  final PollOption option;
  final bool selected;
  final bool multiple;
  final double fraction;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final track = Colors.white.withValues(alpha: mine ? 0.14 : 0.06);
    final fill = mine
        ? Colors.white.withValues(alpha: selected ? 0.34 : 0.18)
        : AppColors.primary.withValues(alpha: selected ? 0.55 : 0.24);
    final icon = selected
        ? (multiple ? Icons.check_box_rounded : Icons.radio_button_checked_rounded)
        : (multiple ? Icons.check_box_outline_blank_rounded : Icons.radio_button_unchecked_rounded);
    final iconColor = selected ? Colors.white : (mine ? Colors.white60 : AppColors.textMuted);

    final row = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        color: track,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                alignment: Alignment.centerLeft,
                widthFactor: fraction,
                heightFactor: 1,
                child: ColoredBox(color: fill),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: iconColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      option.text,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${option.voteCount}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap!();
      },
      child: row,
    );
  }
}

Future<void> showPollVotersSheet(BuildContext context, Poll poll, String myId) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      final maxHeight = MediaQuery.of(ctx).size.height * 0.7;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(
                poll.question,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                pollVoteLabel(poll.uniqueVotersCount),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 14),
              if (!poll.hasVoterDetails)
                const Text(
                  'Voter details are not available for this poll.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              for (final option in poll.options) ...[
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.only(bottom: 6),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.surfaceBorder)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          option.text,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        pollVoteLabel(option.voteCount),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                for (final voter in option.voters)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        ChatAvatar(name: voter.user.name, imageUrl: voter.user.avatarUrl, radius: 16),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            voter.userId == myId
                                ? 'You'
                                : (voter.user.name.isEmpty ? 'Unknown' : voter.user.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Future<PollDraft?> showCreatePollSheet(BuildContext context, {String submitLabel = 'Send poll'}) {
  return showModalBottomSheet<PollDraft>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _CreatePollSheet(submitLabel: submitLabel),
  );
}

class _CreatePollSheet extends StatefulWidget {
  const _CreatePollSheet({required this.submitLabel});
  final String submitLabel;

  @override
  State<_CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends State<_CreatePollSheet> {
  final TextEditingController _question = TextEditingController();
  final List<TextEditingController> _options = [TextEditingController(), TextEditingController()];
  bool _multiple = false;
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_options.length >= pollMaxOptions) return;
    setState(() => _options.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_options.length <= pollMinOptions) return;
    final removed = _options.removeAt(index);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  void _submit() {
    final question = _question.text.trim();
    final options = _options.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (question.isEmpty) {
      setState(() => _error = 'Enter a question');
      return;
    }
    if (options.length < pollMinOptions) {
      setState(() => _error = 'Add at least $pollMinOptions options');
      return;
    }
    if (options.map((o) => o.toLowerCase()).toSet().length != options.length) {
      setState(() => _error = 'Options must be different from each other');
      return;
    }
    Navigator.pop(
      context,
      PollDraft(question: question, options: options, allowMultipleAnswers: _multiple),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        counterText: '',
        filled: true,
        fillColor: const Color(0xFF0F101A),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text(
                'Create poll',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              const Text(
                'Question',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _question,
                maxLength: pollMaxQuestionLength,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: _decoration('Ask a question'),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Options',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              for (var i = 0; i < _options.length; i++)
                Padding(
                  key: ObjectKey(_options[i]),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _options[i],
                          maxLength: pollMaxOptionLength,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: _decoration('Option ${i + 1}'),
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: _options.length > pollMinOptions
                            ? IconButton(
                                tooltip: 'Remove option',
                                icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
                                onPressed: () => _removeOption(i),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              if (_options.length < pollMaxOptions)
                TextButton.icon(
                  onPressed: _addOption,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('Add option'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.primaryLight),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeTrackColor: AppColors.primary,
                title: const Text(
                  'Allow multiple answers',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                ),
                value: _multiple,
                onChanged: (v) => setState(() => _multiple = v),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(widget.submitLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
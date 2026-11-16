import 'package:flutter/material.dart';
import 'package:quorum_app/api/presence_service.dart';
import 'package:quorum_app/models/presence_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'package:quorum_app/widgets/presence_widgets.dart';

Future<void> showSetStatusSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _SetStatusSheet(),
  );
}

class _Duration {
  const _Duration(this.label, this.minutes);
  final String label;
  final int? minutes;
}

const List<_Duration> _durations = [
  _Duration('30 Minutes', 30),
  _Duration('1 Hour', 60),
  _Duration('Today / 4 Hours', 240),
  _Duration('Never', null),
];

const List<(PresenceStatus, String)> _choices = [
  (PresenceStatus.available, 'Available'),
  (PresenceStatus.busy, 'Busy'),
  (PresenceStatus.doNotDisturb, 'Do Not Disturb'),
  (PresenceStatus.beRightBack, 'Be Right Back'),
  (PresenceStatus.away, 'Appear Away'),
];

class _SetStatusSheet extends StatefulWidget {
  const _SetStatusSheet();

  @override
  State<_SetStatusSheet> createState() => _SetStatusSheetState();
}

class _SetStatusSheetState extends State<_SetStatusSheet> {
  final _message = TextEditingController();
  PresenceStatus _status = PresenceStatus.available;
  int _durationIndex = 3;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final mine = PresenceService.instance.mine;
    if (mine != null && mine.effective != PresenceStatus.offline) {
      _status = mine.effective;
      _message.text = mine.message ?? '';
    }
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _update() async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await PresenceService.instance.setStatus(
      status: _status,
      message: _message.text,
      clearAfterMinutes: _durations[_durationIndex].minutes,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      _toast(error);
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _reset() async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await PresenceService.instance.reset();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      _toast(error);
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Set status',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _choices)
                    ChoiceChip(
                      selected: _status == c.$1,
                      onSelected: (_) => setState(() => _status = c.$1),
                      backgroundColor: AppColors.surface,
                      selectedColor: c.$1.color.withValues(alpha: 0.22),
                      side: BorderSide(color: _status == c.$1 ? c.$1.color : AppColors.surfaceBorder),
                      showCheckmark: false,
                      avatar: PresenceDot(status: c.$1, size: 14, ringColor: Colors.transparent),
                      label: Text(
                        c.$2,
                        style: TextStyle(
                          color: _status == c.$1 ? AppColors.textPrimary : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _message,
                maxLength: 100,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: "What's on your mind?",
                  hintStyle: const TextStyle(color: AppColors.textSecondary),
                  counterStyle: const TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.surfaceBorder.withValues(alpha: 0.35),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Clear after',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _durations.length; i++)
                    ChoiceChip(
                      selected: _durationIndex == i,
                      onSelected: (_) => setState(() => _durationIndex = i),
                      backgroundColor: AppColors.surface,
                      selectedColor: AppColors.primary.withValues(alpha: 0.25),
                      side: BorderSide(color: _durationIndex == i ? AppColors.primary : AppColors.surfaceBorder),
                      showCheckmark: false,
                      label: Text(
                        _durations[i].label,
                        style: TextStyle(
                          color: _durationIndex == i ? AppColors.textPrimary : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _reset,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.surfaceBorder),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Reset to Default'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _update,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Update Status'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
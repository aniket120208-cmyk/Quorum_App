import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/meeting_api.dart';
import 'package:quorum_app/models/meeting_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'package:quorum_app/screens/organization_screen/organization_sheets.dart';
import 'package:quorum_app/screens/recording_screen/meeting_recordings_screen.dart';
import 'meeting_launcher.dart';
import 'meeting_room_screen.dart';
import 'video_call_controller.dart';

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key});
  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final VideoCallController _controller = VideoCallController();
  final TextEditingController _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.loadHistory();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openRoom(String code, {required String title, bool isHost = false}) async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.of(context).push<MeetingResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MeetingRoomScreen(
          meetingCode: code,
          title: title,
          isHostHint: isHost,
        ),
      ),
    );
    if (result == null || !result.joined) return;
    await _controller.recordMeeting(result);
    if (!mounted) return;
    _snack('You left the meeting • ${result.formattedDuration}');
  }

  void _handleJoin() {
    final input = _codeCtrl.text.trim();
    if (input.isEmpty) return;
    final code = MeetingApi.codeFromLink(input);
    if (code == null) {
      _snack("That doesn't look like a valid meeting code");
      return;
    }
    _codeCtrl.clear();
    _openRoom(code, title: 'Joined Meeting');
  }

  Future<void> _createMeeting() async {
    try {
      final meeting = await _controller.createMeeting();
      if (!mounted) return;
      _showLinkDialog(meeting);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(errorText(e));
    }
  }

  void _copyLink(String code) {
    Clipboard.setData(ClipboardData(text: MeetingApi.linkFor(code)));
    _snack('Meeting link copied');
  }

  void _showLinkDialog(CreatedMeeting meeting) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Meeting ready', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share this link with others, then start the meeting.',
              style: TextStyle(fontSize: 13, color: Colors.white54),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: SelectableText(
                meeting.link,
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primaryLight),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: meeting.link));
              _snack('Meeting link copied');
            },
            icon: const Icon(Icons.copy, color: Colors.white),
            label: const Text('Copy', style: TextStyle(color: Colors.white)),
          ),
          TextButton.icon(
            onPressed: () => Share.share('Join my Quorum meeting: ${meeting.link}'),
            icon: const Icon(Icons.share, color: Colors.white),
            label: const Text('Share', style: TextStyle(color: Colors.white)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              Navigator.pop(dialogCtx);
              _openRoom(meeting.code, title: 'Instant Meeting', isHost: true);
            },
            child: const Text('Start now', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatWhen(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return 'Today, $time';
    if (diff == 1) return 'Yesterday, $time';
    return '${dt.day}/${dt.month}/${dt.year}, $time';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: const Text(
          'Meetings',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            return ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                24 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                const Text(
                  'Start a video call or join one with a code.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 20),
                _buildHeroCard(_controller.creating),
                const SizedBox(height: 28),
                const Text(
                  'Recent meetings',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (_controller.history.isEmpty)
                  _buildEmptyState()
                else
                  for (var i = 0; i < _controller.history.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildHistoryTile(_controller.history[i], i),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeroCard(bool loading) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: loading ? null : _createMeeting,
              icon: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Icon(Icons.videocam_rounded, color: Colors.white),
              label: const Text(
                'New meeting',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: Divider(color: AppColors.surfaceBorder)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or join with a code',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
              Expanded(child: Divider(color: AppColors.surfaceBorder)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.go,
                  autocorrect: false,
                  onSubmitted: (_) => _handleJoin(),
                  decoration: InputDecoration(
                    hintText: 'abc-defg-hij or link',
                    hintStyle: const TextStyle(color: Colors.white30),
                    prefixIcon: const Icon(Icons.keyboard_rounded, color: AppColors.textSecondary),
                    filled: true,
                    fillColor: Colors.black26,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.surfaceBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.surfaceBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.primaryLight),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _codeCtrl,
                builder: (context, value, _) {
                  return SizedBox(
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: value.text.trim().isNotEmpty ? _handleJoin : null,
                      child: const Text('Join', style: TextStyle(color: Colors.white)),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      alignment: Alignment.center,
      child: const Column(
        children: [
          Icon(Icons.history_toggle_off_rounded, size: 48, color: Colors.white24),
          SizedBox(height: 12),
          Text('No meetings yet', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600)),
          SizedBox(height: 4),
          Text(
            'Meetings you join will show up here.',
            style: TextStyle(color: Colors.white30, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(MeetingHistoryItem item, int index) {
    return Dismissible(
      key: ValueKey('${item.code}-${item.timestamp.millisecondsSinceEpoch}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) {
        _controller.removeMeeting(item);
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        final snack = messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 4),
            content: const Text('Removed from history'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => _controller.restoreMeeting(item, index),
            ),
          ),
        );
        Timer(const Duration(seconds: 4), snack.close);
      },
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openRoom(item.code, title: item.title),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.videocam_rounded, color: AppColors.primaryLight, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.code} • ${_formatWhen(item.timestamp)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 13, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            item.duration,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Recordings',
                  icon: const Icon(Icons.video_library_outlined, color: AppColors.textSecondary),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MeetingRecordingsScreen(meetingCode: item.code, title: item.title),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy link',
                  icon: const Icon(Icons.link_rounded, color: AppColors.textSecondary),
                  onPressed: () => _copyLink(item.code),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
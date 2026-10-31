import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/meeting_api.dart';
import 'package:quorum_app/api/notification_service.dart';
import 'package:quorum_app/models/calendar_models.dart';
import 'package:quorum_app/models/notification_models.dart';
import 'package:quorum_app/screens/home_screen/calendar_helpers.dart';
import 'package:quorum_app/models/meeting_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'package:quorum_app/screens/meetings_screen/meetings_list_screen.dart';
import 'package:quorum_app/screens/meetings_screen/schedule_meeting_sheet.dart';
import 'package:quorum_app/screens/organization_screen/organization_sheets.dart';
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
  StreamSubscription<NotificationItem>? _notificationSub;

  @override
  void initState() {
    super.initState();
    _controller.loadHistory();
    _controller.loadUpcoming();
    _notificationSub = NotificationService.instance.incoming.listen((item) {
      if (item.type == NotificationType.eventReminder) {
        _controller.loadUpcoming();
      }
    });
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
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
    if (result == null || !result.joined || !mounted) return;
    _controller.recordMeeting(result);
    _snack('You left the meeting • ${result.formattedDuration}');
  }

  Future<void> _joinScheduled(CalendarEvent event) async {
    final link = event.meetingLink;
    if (link == null) return;
    if (MeetingApi.isQuorumLink(link)) {
      final code = MeetingApi.codeFromLink(link);
      if (code != null) {
        await _openRoom(code, title: event.title);
        return;
      }
    }
    final opened = await MeetingLauncher.join(link, title: event.title);
    if (!opened) _snack('Unable to open the meeting link');
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

  Future<void> _scheduleMeeting() async {
    final meeting = await showOrgSheet<ScopedMeeting>(context, const ScheduleMeetingSheet());
    if (meeting == null || !mounted) return;
    if (meeting.isActive) {
      _showLinkDialog(
        CreatedMeeting(code: meeting.code, link: meeting.link ?? MeetingApi.linkFor(meeting.code)),
      );
      return;
    }
    _snack('Meeting scheduled');
  }

  void _openUpcoming() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MeetingsListScreen.upcoming()),
    );
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
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
          TextButton.icon(
            onPressed: () => Share.share('Join my Quorum meeting: ${meeting.link}'),
            icon: const Icon(Icons.share),
            label: const Text('Share'),
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
      backgroundColor: const Color(0xFF090A10),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final history = _controller.history;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                const Text(
                  'Meetings',
                  style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Start a video call or join one with a code.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 20),
                _buildHeroCard(_controller.creating),
                if (_controller.upcoming.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  const Text(
                    'Scheduled meetings',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  for (final event in _controller.upcoming)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildScheduledTile(event),
                    ),
                ],
                const SizedBox(height: 28),
                Row(
                  children: [
                    const Text(
                      'Recent meetings',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (history.isNotEmpty)
                      Text('${history.length}', style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 12),
                if (history.isEmpty)
                  _buildEmptyState()
                else
                  for (var i = 0; i < history.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildHistoryTile(history[i], i),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _scheduledWhen(CalendarEvent event) {
    final now = DateTime.now();
    final time = calendarTimeLabel(context, event);
    if (calendarSameDay(event.startDate, now)) return 'Today, $time';
    if (calendarSameDay(event.startDate, now.add(const Duration(days: 1)))) {
      return 'Tomorrow, $time';
    }
    return '${event.startDate.day}/${event.startDate.month}/${event.startDate.year}, $time';
  }

  Widget _buildScheduledTile(CalendarEvent event) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
            child: const Icon(Icons.event_rounded, color: AppColors.primaryLight, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  _scheduledWhen(event),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _joinScheduled(event),
            child: const Text('Join', style: TextStyle(color: Colors.white)),
          ),
        ],
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
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: loading ? null : _scheduleMeeting,
                  icon: const Icon(Icons.event_available_rounded, size: 18, color: Colors.white),
                  label: const Text('Schedule', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    side: const BorderSide(color: AppColors.surfaceBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openUpcoming,
                  icon: const Icon(Icons.event_note_rounded, size: 18, color: Colors.white),
                  label: const Text('Upcoming', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    side: const BorderSide(color: AppColors.surfaceBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
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
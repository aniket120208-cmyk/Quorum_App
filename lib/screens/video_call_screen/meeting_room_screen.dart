import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/auth_service.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/meeting_api.dart';
import 'package:quorum_app/api/meeting_service.dart';
import 'package:quorum_app/models/meeting_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'package:quorum_app/screens/whiteboard_screen/meeting_whiteboard_sheet.dart';
import 'package:quorum_app/screens/whiteboard_screen/whiteboard_screen.dart';
import 'widgets/call_action_button.dart';
import 'widgets/draggable_pip_view.dart';

enum _Phase { lobby, joining, waiting, inCall, leaving }

enum _LeaveChoice { stay, leave, endForAll }

String _initial(String name) => name.isEmpty ? '?' : name.characters.first.toUpperCase();

class MeetingRoomScreen extends StatefulWidget {
  const MeetingRoomScreen({
    super.key,
    required this.meetingCode,
    this.title = 'Meeting',
    this.isHostHint = false,
  });

  final String meetingCode;
  final String title;
  final bool isHostHint;

  @override
  State<MeetingRoomScreen> createState() => _MeetingRoomScreenState();
}

class _MeetingRoomScreenState extends State<MeetingRoomScreen> {
  MeetingService? _svcOrNull;
  StreamSubscription<String>? _noticeSub;
  bool _permissionDenied = false;
  bool _checkingMeeting = true;
  bool _whiteboardAllowed = false;
  bool _mediaReady = false;
  String? _lobbyError;
  _Phase _phase = _Phase.lobby;
  bool _controlsVisible = true;
  bool _dialogOpen = false;
  DateTime? _joinedAt;
  final ValueNotifier<int> _seconds = ValueNotifier<int>(0);
  Timer? _callTimer;
  Timer? _hideTimer;

  MeetingService get _svc => _svcOrNull!;
  String get _link => MeetingApi.linkFor(widget.meetingCode);
  List<RemotePeer> get _remote => _svc.participants;
  bool get _micMuted => _svc.isMuted;
  bool get _cameraOff => _svc.isVideoOff || !_svc.hasLocalVideo;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _hideTimer?.cancel();
    _noticeSub?.cancel();
    _seconds.dispose();
    _svcOrNull?.removeListener(_onService);
    _svcOrNull?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    bool isHost = widget.isHostHint;
    bool whiteboardAllowed = false;
    try {
      if (!CurrentUser.isLoaded) {
        CurrentUser.setFromProfile(await AuthService.instance.getUserProfile());
      }
      if (!CurrentUser.isLoaded) throw ApiException('Unable to load your profile.');
      final info = await MeetingApi.instance.getMeeting(widget.meetingCode);
      isHost = isHost || (info.hostId.isNotEmpty && info.hostId == CurrentUser.id);
      whiteboardAllowed = info.scope != MeetingScope.personal;
    } catch (e) {
      if (mounted) {
        setState(() {
          _checkingMeeting = false;
          _lobbyError = errorText(e);
        });
      }
      return;
    }
    if (!mounted) return;

    final svc = MeetingService(
      meetingCode: widget.meetingCode,
      userId: CurrentUser.id,
      userName: CurrentUser.name,
      isHost: isHost,
    )..addListener(_onService);
    _svcOrNull = svc;
    _noticeSub = svc.notices.listen(_snack);
    setState(() {
      _checkingMeeting = false;
      _whiteboardAllowed = whiteboardAllowed;
    });

    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!mounted) return;
    _permissionDenied = !cam.isGranted;
    await svc.initLocalMedia(audio: mic.isGranted, video: cam.isGranted);
    if (mounted) setState(() => _mediaReady = true);
  }

  void _onService() {
    if (!mounted) return;
    final msg = _svc.message;
    switch (_svc.phase) {
      case MeetingPhase.waitingRoom:
        if (_phase == _Phase.joining) _phase = _Phase.waiting;
        break;
      case MeetingPhase.inCall:
        if (_phase == _Phase.joining || _phase == _Phase.waiting) {
          _phase = _Phase.inCall;
          _joinedAt = DateTime.now();
          _callTimer = Timer.periodic(const Duration(seconds: 1), (_) => _seconds.value++);
          _scheduleHideControls();
        }
        break;
      case MeetingPhase.failed:
        if (_phase == _Phase.joining || _phase == _Phase.waiting) {
          _phase = _Phase.lobby;
          if (msg != null) _snack(msg);
        } else if (_phase == _Phase.inCall) {
          if (msg != null) _snack(msg);
          _exit(skipServer: true);
        }
        break;
      case MeetingPhase.rejected:
      case MeetingPhase.ended:
        if (_phase != _Phase.leaving) {
          if (msg != null) _snack(msg);
          _exit(skipServer: true);
        }
        break;
      default:
        break;
    }
    setState(() {});
  }

  void _joinMeeting() {
    if (_phase != _Phase.lobby || _lobbyError != null || !_mediaReady) return;
    HapticFeedback.mediumImpact();
    setState(() => _phase = _Phase.joining);
    _svc.join();
  }

  Future<void> _toggleCamera() async {
    if (_permissionDenied || !_svc.hasLocalVideo) {
      _snack(
        'Camera permission is turned off',
        action: SnackBarAction(label: 'Settings', onPressed: openAppSettings),
      );
      return;
    }
    HapticFeedback.selectionClick();
    _svc.toggleCamera();
    _showControls();
  }

  Future<void> _toggleScreenShare() async {
    HapticFeedback.selectionClick();
    if (_svc.isScreenSharing) {
      await _svc.stopScreenShare();
    } else {
      await _svc.startScreenShare();
    }
    _showControls();
  }

  Future<void> _switchCamera() async {
    if (!_svc.hasLocalVideo || _svc.isVideoOff) return;
    HapticFeedback.selectionClick();
    await _svc.switchCamera();
    _showControls();
  }

  void _toggleMic() {
    HapticFeedback.selectionClick();
    _svc.toggleMic();
    _showControls();
  }

  Future<void> _requestLeave() async {
    if (_phase == _Phase.leaving || _dialogOpen) return;
    if (_phase != _Phase.inCall) {
      await _exit();
      return;
    }

    _hideTimer?.cancel();
    setState(() => _controlsVisible = true);
    _dialogOpen = true;

    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Leave meeting?'),
        content: Text(
          _svc.isHost
              ? 'You can leave and let others continue, or end the meeting for everyone.'
              : 'You can rejoin anytime with the same code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_LeaveChoice.stay),
            child: const Text('Stay'),
          ),
          if (_svc.isHost)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.of(ctx).pop(_LeaveChoice.endForAll),
              child: const Text('End for all', style: TextStyle(color: Colors.white)),
            ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _svc.isHost ? AppColors.primary : Colors.redAccent,
            ),
            onPressed: () => Navigator.of(ctx).pop(_LeaveChoice.leave),
            child: const Text('Leave', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    _dialogOpen = false;
    if (!mounted) return;

    switch (choice) {
      case _LeaveChoice.leave:
        await _exit();
      case _LeaveChoice.endForAll:
        await _exit(endForAll: true);
      default:
        _showControls();
    }
  }

  Future<void> _exit({bool endForAll = false, bool skipServer = false}) async {
    if (_phase == _Phase.leaving) return;

    _callTimer?.cancel();
    _hideTimer?.cancel();

    final result = MeetingResult(
      code: widget.meetingCode,
      title: widget.title,
      joined: _joinedAt != null,
      joinedAt: _joinedAt,
      durationSeconds: _seconds.value,
    );

    HapticFeedback.mediumImpact();
    setState(() => _phase = _Phase.leaving);

    if (!skipServer && _svcOrNull != null) {
      await _svc.leave(endForAll: endForAll && _svc.isHost);
      if (endForAll && _svc.isHost) {
        try {
          await MeetingApi.instance.endMeeting(widget.meetingCode);
        } catch (_) {}
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _phase == _Phase.inCall) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    if (!mounted || _phase != _Phase.inCall) return;
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHideControls();
  }

  void _toggleControls() {
    if (_phase != _Phase.inCall) return;
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  void _snack(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: _link));
    _snack('Meeting link copied');
  }

  void _shareLink() {
    Share.share('Join my Quorum meeting: $_link');
  }

  Future<void> _openWhiteboard() async {
    _hideTimer?.cancel();
    final board = await MeetingWhiteboardSheet.show(context, widget.meetingCode);
    if (board != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WhiteboardScreen(
            boardId: board.id,
            name: board.name,
            meetingCode: widget.meetingCode,
          ),
        ),
      );
    }
    _showControls();
  }

  Future<void> _showMoreMenu() async {
    _hideTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              ListTile(
                leading: const Icon(Icons.people_alt_rounded, color: Colors.white),
                title: Text('People (${_remote.length + 1})', style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showParticipants();
                },
              ),
              ListTile(
                leading: Icon(
                  _svc.isScreenSharing ? Icons.stop_screen_share_rounded : Icons.screen_share_rounded,
                  color: _svc.isScreenSharing ? Colors.redAccent : Colors.white,
                ),
                title: Text(
                  _svc.isScreenSharing ? 'Stop sharing' : 'Share screen',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _toggleScreenShare();
                },
              ),
              if (_whiteboardAllowed)
                ListTile(
                  leading: const Icon(Icons.draw_rounded, color: Colors.white),
                  title: const Text('Whiteboard', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openWhiteboard();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.ios_share_rounded, color: Colors.white),
                title: const Text('Share invite link', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _shareLink();
                },
              ),
            ],
          ),
        ),
      ),
    );
    _showControls();
  }

  Future<void> _showChat() async {
    _hideTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ChatBottomSheet(svc: _svc, onSnack: _snack),
    );
    _showControls();
  }

  Future<void> _showParticipants() async {
    _hideTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => ListenableBuilder(
        listenable: _svc,
        builder: (ctx, _) {
          final people = _svc.participants;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_svc.isHost && _svc.waitingList.isNotEmpty) ...[
                    Text(
                      'Waiting to join (${_svc.waitingList.length})',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    for (final g in _svc.waitingList)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                          child: Text(_initial(g.name), style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(g.name, style: const TextStyle(color: Colors.white)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
                              onPressed: () => _svc.reject(g.userId),
                            ),
                            IconButton(
                              icon: const Icon(Icons.check_rounded, color: Colors.greenAccent),
                              onPressed: () => _svc.admit(g.userId),
                            ),
                          ],
                        ),
                      ),
                    const Divider(color: AppColors.surfaceBorder),
                  ],
                  Text(
                    'Participants (${people.length + 1})',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  _participantTile('You', muted: _svc.isMuted, subtitle: _svc.isHost ? 'Host' : null),
                  for (final p in people)
                    _participantTile(
                      p.name,
                      muted: p.isMuted,
                      onMute: _svc.isHost && !p.isMuted ? () => _svc.muteParticipant(p.userId) : null,
                    ),
                  if (people.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('No one else has joined yet.', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copyLink,
                          icon: const Icon(Icons.link_rounded, size: 18),
                          label: const Text('Copy link'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _shareLink,
                          icon: const Icon(Icons.ios_share_rounded, size: 18, color: Colors.white),
                          label: const Text('Invite', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    _showControls();
  }

  Widget _participantTile(String name, {bool muted = false, String? subtitle, VoidCallback? onMute}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: 0.25),
        child: Text(_initial(name), style: const TextStyle(color: Colors.white)),
      ),
      title: Text(name, style: const TextStyle(color: Colors.white)),
      subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(color: Colors.white54)),
      trailing: IconButton(
        onPressed: onMute,
        tooltip: onMute == null ? null : 'Mute participant',
        icon: Icon(
          muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          color: muted ? Colors.redAccent : Colors.white54,
          size: 20,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestLeave();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0C10),
        body: switch (_phase) {
          _Phase.lobby => _buildLobby(),
          _Phase.leaving => _buildLeaving(),
          _ => _buildCall(),
        },
      ),
    );
  }

  Widget _buildLeaving() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text('Leaving...', style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _selfView() {
    final svc = _svcOrNull;
    if (svc != null && !_cameraOff) {
      return RTCVideoView(
        svc.localRenderer,
        mirror: svc.isFrontCamera,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }

    final message = _permissionDenied
        ? 'Camera permission denied'
        : (svc == null || !svc.hasLocalVideo)
            ? 'Camera unavailable'
            : 'Camera is off';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E222A), Color(0xFF0F1115)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.primary.withValues(alpha: 0.25),
              child: const Icon(Icons.person_rounded, size: 46, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildLobby() {
    final ready = !_checkingMeeting && _mediaReady && _lobbyError == null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _requestLeave,
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
                const Spacer(),
              ],
            ),
            const Text(
              'Ready to join?',
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(widget.title, style: const TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 18),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _selfView(),
                        if (ready)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 16,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CallActionButton(
                                  icon: _micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                                  isActive: _micMuted,
                                  onPressed: _svc.toggleMic,
                                ),
                                const SizedBox(width: 16),
                                CallActionButton(
                                  icon: _cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                                  isActive: _cameraOff,
                                  onPressed: _toggleCamera,
                                ),
                                if (_svc.hasLocalVideo) ...[
                                  const SizedBox(width: 16),
                                  CallActionButton(
                                    icon: Icons.cameraswitch_rounded,
                                    onPressed: _switchCamera,
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (_lobbyError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _lobbyError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),
            if (_permissionDenied && _mediaReady)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Flexible(
                      child: Text(
                        'Camera access is off. You can still join with audio.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                      ),
                    ),
                    TextButton(onPressed: openAppSettings, child: const Text('Settings')),
                  ],
                ),
              ),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _copyLink,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.meeting_room_rounded, size: 16, color: Colors.white70),
                    const SizedBox(width: 8),
                    Text(
                      widget.meetingCode,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.copy_rounded, size: 14, color: Colors.white54),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: ready ? _joinMeeting : null,
                child: Text(
                  _checkingMeeting
                      ? 'Checking meeting…'
                      : !_mediaReady && _lobbyError == null
                          ? 'Preparing camera & mic…'
                          : (widget.isHostHint ? 'Start now' : 'Join now'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fade({required bool visible, required Offset hidden, required Widget child}) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : hidden,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: visible ? 1 : 0,
          child: child,
        ),
      ),
    );
  }

  Widget _buildCall() {
    final pad = MediaQuery.of(context).padding;
    final joining = _phase == _Phase.joining || _phase == _Phase.waiting;
    final inCall = _phase == _Phase.inCall;
    final alone = _remote.isEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          child: alone ? _selfView() : _remoteStage(pad),
        ),
        IgnorePointer(
          child: Column(
            children: [
              Container(
                height: pad.top + 110,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
              ),
              const Spacer(),
              Container(
                height: pad.bottom + 190,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_remote.length == 1 && inCall)
          Positioned.fill(
            child: DraggablePipView(
              topInset: pad.top + 72,
              bottomInset: pad.bottom + 120,
              child: _selfView(),
            ),
          ),
        if (joining) _buildJoiningOverlay(),
        if (inCall) ...[
          Positioned(
            top: pad.top + 8,
            left: 16,
            right: 16,
            child: _fade(
              visible: _controlsVisible,
              hidden: const Offset(0, -1),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        ValueListenableBuilder<int>(
                          valueListenable: _seconds,
                          builder: (context, s, _) => Text(
                            formatDuration(s),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _copyLink,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          Text(
                            widget.meetingCode,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    style: IconButton.styleFrom(backgroundColor: Colors.black45),
                    icon: Icon(
                      _svc.soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      _svc.toggleSound();
                      _showControls();
                    },
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    style: IconButton.styleFrom(backgroundColor: Colors.black45),
                    icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
                    onPressed: _switchCamera,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: pad.top + 64,
            left: 16,
            right: 16,
            child: Row(
              children: [
                if (_svc.isHost && _svc.waitingList.isNotEmpty) ...[
                  GestureDetector(
                    onTap: _showParticipants,
                    child: _chip('🔔', '${_svc.waitingList.length} waiting'),
                  ),
                ],
                const Spacer(),
                if (_micMuted) _chip(null, 'Muted', icon: Icons.mic_off_rounded),
              ],
            ),
          ),
          if (alone)
            Positioned(
              left: 16,
              right: 16,
              bottom: pad.bottom + 128,
              child: _fade(
                visible: _controlsVisible,
                hidden: const Offset(0, 0.6),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "You're the only one here",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Share the link so others can join.',
                        style: TextStyle(color: Colors.white60, fontSize: 12.5),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _copyLink,
                              icon: const Icon(Icons.link_rounded, size: 18),
                              label: const Text('Copy link'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _shareLink,
                              icon: const Icon(Icons.ios_share_rounded, size: 18, color: Colors.white),
                              label: const Text('Invite', style: TextStyle(color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_svc.isScreenSharing)
            Positioned(
              top: pad.top + 64,
              left: 16,
              right: 16,
              child: _sharingBanner(),
            ),
          Positioned(
            left: 20,
            right: 20,
            bottom: pad.bottom + 12,
            child: _fade(
              visible: _controlsVisible,
              hidden: const Offset(0, 1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: CallActionButton(
                        icon: _micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        label: _micMuted ? 'Unmute' : 'Mic',
                        isActive: _micMuted,
                        onPressed: _toggleMic,
                      ),
                    ),
                    Expanded(
                      child: CallActionButton(
                        icon: _cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                        label: 'Camera',
                        isActive: _cameraOff,
                        onPressed: _toggleCamera,
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.none,
                        children: [
                          CallActionButton(
                            icon: Icons.chat_bubble_rounded,
                            label: 'Chat',
                            onPressed: _showChat,
                          ),
                          if (_svc.unreadChat > 0)
                            Positioned(
                              top: -2,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _svc.unreadChat > 9 ? '9+' : '${_svc.unreadChat}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: CallActionButton(
                        icon: Icons.more_vert_rounded,
                        label: 'More',
                        onPressed: _showMoreMenu,
                      ),
                    ),
                    Expanded(
                      child: CallActionButton(
                        icon: Icons.call_end_rounded,
                        label: 'Leave',
                        backgroundColor: Colors.redAccent,
                        iconColor: Colors.white,
                        onPressed: _requestLeave,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _sharingBanner() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.screen_share_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'You are sharing your screen',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: _toggleScreenShare,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.black.withValues(alpha: 0.25),
              minimumSize: const Size(56, 34),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Stop', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildJoiningOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 18),
              Text(
                _phase == _Phase.waiting ? 'Waiting for the host to let you in…' : 'Joining meeting...',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(widget.meetingCode, style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 16),
              TextButton(onPressed: _requestLeave, child: const Text('Cancel')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String? emoji, String text, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji != null) Text(emoji, style: const TextStyle(fontSize: 14)),
          if (icon != null) Icon(icon, size: 14, color: Colors.redAccent),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _remoteStage(EdgeInsets pad) {
    if (_remote.length == 1) {
      return SizedBox.expand(child: _remoteTile(_remote.first, rounded: false));
    }

    final tiles = <Widget>[
      for (final p in _remote) _remoteTile(p, rounded: true),
      _selfTile(),
    ];
    final n = tiles.length;
    const cols = 2;
    final rowCount = (n + cols - 1) ~/ cols;

    return Padding(
      padding: EdgeInsets.fromLTRB(4, pad.top + 60, 4, pad.bottom + 100),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final visibleRows = rowCount < 2 ? rowCount : 2;
          final rowHeight = constraints.maxHeight / visibleRows;
          return ListView.builder(
            physics: rowCount > 2
                ? const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())
                : const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: rowCount,
            itemBuilder: (context, rowIndex) {
              final start = rowIndex * cols;
              final end = (start + cols) > n ? n : start + cols;
              final row = tiles.sublist(start, end);
              return SizedBox(
                height: rowHeight,
                child: Row(
                  children: [
                    for (final t in row)
                      Expanded(child: Padding(padding: const EdgeInsets.all(4), child: t)),
                    for (var k = row.length; k < cols; k++) const Spacer(),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _remoteTile(RemotePeer p, {required bool rounded}) {
    final content = Container(
      color: const Color(0xFF1E222A),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (p.hasVideo && !p.isVideoOff)
            RTCVideoView(
              p.renderer,
              objectFit: p.fitContain ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            Center(
              child: CircleAvatar(
                radius: rounded ? 32 : 48,
                backgroundColor: AppColors.primary.withValues(alpha: 0.3),
                child: Text(
                  _initial(p.name),
                  style: TextStyle(fontSize: rounded ? 24 : 36, color: Colors.white),
                ),
              ),
            ),
          Positioned(
            left: 12,
            bottom: rounded ? 10 : 130,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (p.isScreenSharing)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.screen_share_rounded, color: Colors.white, size: 14),
                  ),
                Text(
                  p.isScreenSharing ? '${p.name} · Sharing screen' : p.name,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
          if (p.isMuted)
            Positioned(
              right: 12,
              bottom: rounded ? 10 : 130,
              child: const Icon(Icons.mic_off_rounded, color: Colors.redAccent, size: 18),
            ),
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      onDoubleTap: () {
        p.fitContain = !p.fitContain;
        setState(() {});
      },
      child: rounded ? ClipRRect(borderRadius: BorderRadius.circular(16), child: content) : content,
    );
  }

  Widget _selfTile() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _selfView(),
            const Positioned(
              left: 12,
              bottom: 10,
              child: Text('You', style: TextStyle(color: Colors.white, fontSize: 13)),
            ),
            if (_micMuted)
              const Positioned(
                right: 12,
                bottom: 10,
                child: Icon(Icons.mic_off_rounded, color: Colors.redAccent, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatBottomSheet extends StatefulWidget {
  const _ChatBottomSheet({required this.svc, required this.onSnack});
  final MeetingService svc;
  final void Function(String message, {SnackBarAction? action}) onSnack;

  @override
  State<_ChatBottomSheet> createState() => _ChatBottomSheetState();
}

class _ChatBottomSheetState extends State<_ChatBottomSheet> {
  late final TextEditingController _input;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController();
    widget.svc.setChatOpen(true);
  }

  @override
  void dispose() {
    _input.dispose();
    final svc = widget.svc;
    WidgetsBinding.instance.addPostFrameCallback((_) => svc.setChatOpen(false));
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    final err = await widget.svc.sendMessage(text);
    if (!mounted) return;
    if (err != null) {
      _input.text = text;
      widget.onSnack(err);
    }
    setState(() => _sending = false);
  }

  Widget _chatBubble(BuildContext ctx, MeetingChatMessage m) {
    final mine = m.senderId == widget.svc.userId;
    final t = m.timestamp;
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(ctx).width * 0.75),
        decoration: BoxDecoration(
          color: mine ? AppColors.primary : Colors.white10,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(
                m.senderName,
                style: const TextStyle(
                  color: AppColors.primaryLight,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            Text(m.content, style: const TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 2),
            Text(time, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.65;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            children: [
              const SizedBox(height: 16),
              const Text(
                'In-call chat',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListenableBuilder(
                  listenable: widget.svc,
                  builder: (ctx, _) {
                    final msgs = widget.svc.chat.reversed.toList();
                    if (msgs.isEmpty) {
                      return const Center(
                        child: Text('No messages yet. Say hi 👋', style: TextStyle(color: Colors.white38)),
                      );
                    }
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: msgs.length,
                      itemBuilder: (ctx, i) => _chatBubble(ctx, msgs[i]),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.send,
                        maxLength: 500,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'Message everyone',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: Colors.black26,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: _send,
                      icon: const Icon(Icons.send_rounded, color: Colors.white),
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
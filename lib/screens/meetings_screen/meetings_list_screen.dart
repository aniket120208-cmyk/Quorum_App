import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/auth_service.dart';
import 'package:quorum_app/api/meeting_history_store.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/meeting_api.dart';
import 'package:quorum_app/models/meeting_models.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_sheets.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'package:quorum_app/screens/recording_screen/meeting_recordings_screen.dart';
import 'package:quorum_app/screens/video_call_screen/meeting_launcher.dart';
import 'meeting_widgets.dart';
import 'schedule_meeting_sheet.dart';

enum MeetingsMode { upcoming, organization, team }

class MeetingsListScreen extends StatefulWidget {
  const MeetingsListScreen.upcoming({super.key})
      : mode = MeetingsMode.upcoming,
        organization = null,
        team = null;

  const MeetingsListScreen.organization({super.key, required this.organization})
      : mode = MeetingsMode.organization,
        team = null;

  const MeetingsListScreen.team({super.key, required this.organization, required this.team})
      : mode = MeetingsMode.team;

  final MeetingsMode mode;
  final Organization? organization;
  final OrgTeam? team;

  @override
  State<MeetingsListScreen> createState() => _MeetingsListScreenState();
}

class _MeetingsListScreenState extends State<MeetingsListScreen> {
  final _api = MeetingApi.instance;
  List<ScopedMeeting> _meetings = [];
  List<ScopedMeeting> _past = [];
  bool _loading = true;
  String? _error;

  String get _title {
    switch (widget.mode) {
      case MeetingsMode.upcoming:
        return 'Upcoming meetings';
      case MeetingsMode.organization:
        return '${widget.organization!.name} meetings';
      case MeetingsMode.team:
        return '${widget.team!.name} meetings';
    }
  }

  bool get _canSchedule {
    final org = widget.organization;
    switch (widget.mode) {
      case MeetingsMode.upcoming:
        return true;
      case MeetingsMode.organization:
        return org != null && (orgIsAdmin(org.role) || orgCanInvite(org.role));
      case MeetingsMode.team:
        return org != null && orgCanInvite(org.role);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<ScopedMeeting>> _fetch() {
    switch (widget.mode) {
      case MeetingsMode.upcoming:
        return _api.upcomingMeetings();
      case MeetingsMode.organization:
        return _api.organizationMeetings(widget.organization!.id);
      case MeetingsMode.team:
        return _fetchTeam();
    }
  }

  Future<List<ScopedMeeting>> _fetchTeam() async {
    final teamId = widget.team!.id;
    final direct = await _api.teamMeetings(teamId);
    var mine = <ScopedMeeting>[];
    try {
      mine = (await _api.upcomingMeetings()).where((m) => m.teamId == teamId).toList();
    } catch (_) {}
    final seen = direct.map((m) => m.code).toSet();
    return [...direct, ...mine.where((m) => !seen.contains(m.code))];
  }

  int _order(ScopedMeeting a, ScopedMeeting b) {
    if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
    final aStart = a.scheduledStartTime;
    final bStart = b.scheduledStartTime;
    if (aStart == null || bStart == null) return aStart == null ? (bStart == null ? 0 : -1) : 1;
    return aStart.compareTo(bStart);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final all = await _fetch();
      final meetings = all.where((m) => m.isOpen).toList()..sort(_order);
      final past = all.where((m) => m.status == MeetingStatus.ended).toList()
        ..sort((a, b) {
          final aStart = a.scheduledStartTime;
          final bStart = b.scheduledStartTime;
          if (aStart == null || bStart == null) return aStart == null ? (bStart == null ? 0 : 1) : -1;
          return bStart.compareTo(aStart);
        });
      if (!mounted) return;
      setState(() {
        _meetings = meetings;
        _past = past.take(30).toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _meetings.isEmpty) _error = errorText(e);
      });
    }
  }

  bool _isHost(ScopedMeeting meeting) => CurrentUser.isLoaded && meeting.hostId == CurrentUser.id;

  bool _canCancel(ScopedMeeting meeting) {
    final org = widget.organization;
    return _isHost(meeting) || (org != null && orgIsAdmin(org.role));
  }

  Future<void> _join(ScopedMeeting meeting) async {
    await MeetingLauncher.joinCode(meeting.code, title: meeting.title, isHost: _isHost(meeting));
    if (mounted) _load(silent: true);
  }

  Future<void> _copy(ScopedMeeting meeting) async {
    await Clipboard.setData(ClipboardData(text: meeting.link ?? MeetingApi.linkFor(meeting.code)));
    if (mounted) orgToast(context, 'Meeting link copied');
  }

  Future<void> _cancel(ScopedMeeting meeting) async {
    final ok = await orgConfirm(
      context,
      title: 'Cancel meeting',
      body: 'Anyone currently in "${meeting.title}" will be disconnected.',
      action: 'Cancel meeting',
    );
    if (!ok) return;
    try {
      await _api.cancelMeeting(meeting.code);
      if (!mounted) return;
      setState(() => _meetings = _meetings.where((m) => m.code != meeting.code).toList());
      orgToast(context, 'Meeting cancelled successfully');
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _schedule() async {
    final meeting = await showOrgSheet<ScopedMeeting>(
      context,
      ScheduleMeetingSheet(
        organization: widget.mode == MeetingsMode.upcoming ? null : widget.organization,
        team: widget.mode == MeetingsMode.team ? widget.team : null,
      ),
    );
    if (meeting == null || !mounted) return;
    await _saveToHistory(meeting);
    if (!mounted) return;
    if (meeting.isActive) {
      await MeetingLauncher.joinCode(meeting.code, title: meeting.title, isHost: true);
    } else {
      orgToast(context, 'Meeting scheduled');
    }
    if (mounted) _load(silent: true);
  }

  Future<void> _saveToHistory(ScopedMeeting meeting) async {
    try {
      if (!CurrentUser.isLoaded) {
        CurrentUser.setFromProfile(await AuthService.instance.getUserProfile());
      }
      if (!CurrentUser.isLoaded) return;
      await MeetingHistoryStore.instance.add(
        CurrentUser.id,
        MeetingHistoryItem.fromScoped(meeting),
        onlyIfMissing: true,
      );
    } catch (_) {}
  }

  void _openRecordings(ScopedMeeting meeting) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeetingRecordingsScreen(
          meetingCode: meeting.code,
          title: meeting.title,
          isHost: _isHost(meeting),
        ),
      ),
    );
  }

  Widget _errorBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: orgMuted, size: 42),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted, height: 1.4)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _load,
              child: const Text('Retry', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _refreshable(List<Widget> children, String empty) {
    return RefreshIndicator(
      color: orgTeal,
      backgroundColor: orgCard,
      onRefresh: () => _load(silent: true),
      child: children.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                Center(child: Text(empty, style: const TextStyle(color: orgMuted))),
              ],
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
              children: children,
            ),
    );
  }

  List<Widget> _openCards() {
    return [
      for (final meeting in _meetings)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: MeetingCard(
            meeting: meeting,
            isHost: _isHost(meeting),
            canCancel: _canCancel(meeting),
            onJoin: () => _join(meeting),
            onCopy: () => _copy(meeting),
            onCancel: () => _cancel(meeting),
            onRecordings: () => _openRecordings(meeting),
          ),
        ),
    ];
  }

  List<Widget> _pastCards() {
    return [
      for (final meeting in _past)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PastMeetingCard(
            meeting: meeting,
            onRecordings: () => _openRecordings(meeting),
          ),
        ),
    ];
  }

  Widget _combinedBody() {
    final open = _openCards();
    final past = _pastCards();
    return _refreshable(
      [
        ...open,
        if (past.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(2, open.isEmpty ? 0 : 10, 2, 10),
            child: const Text(
              'Past meetings',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          ...past,
        ],
      ],
      'No meetings yet',
    );
  }

  Widget _teamBody() {
    return TabBarView(
      children: [
        _refreshable(_openCards(), 'No scheduled meetings'),
        _refreshable(_pastCards(), 'No recent meetings'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTeam = widget.mode == MeetingsMode.team;
    final scaffold = Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(_title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        bottom: isTeam
            ? TabBar(
                indicatorColor: orgTeal,
                labelColor: Colors.white,
                unselectedLabelColor: orgMuted,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                dividerColor: orgBorder,
                tabs: [
                  Tab(text: _meetings.isEmpty ? 'Scheduled' : 'Scheduled (${_meetings.length})'),
                  const Tab(text: 'Recent'),
                ],
              )
            : null,
      ),
      floatingActionButton: _canSchedule && !_loading && _error == null
          ? FloatingActionButton.extended(
              onPressed: _schedule,
              backgroundColor: orgAccent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New meeting', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: orgTeal))
          : _error != null
              ? _errorBody()
              : (isTeam ? _teamBody() : _combinedBody()),
    );
    return isTeam ? DefaultTabController(length: 2, child: scaffold) : scaffold;
  }
}
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/meeting_api.dart';
import 'package:quorum_app/api/office_controller.dart';
import 'package:quorum_app/models/office_models.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_sheets.dart' show showOrgSheet;
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'package:quorum_app/screens/video_call_screen/meeting_launcher.dart';
import 'office_iso_floor.dart';
import 'office_widgets.dart';

class VirtualOfficeScreen extends StatefulWidget {
  const VirtualOfficeScreen({super.key, required this.organization, required this.teams, required this.initialTeam});
  final Organization organization;
  final List<OrgTeam> teams;
  final OrgTeam initialTeam;

  @override
  State<VirtualOfficeScreen> createState() => _VirtualOfficeScreenState();
}

class _VirtualOfficeScreenState extends State<VirtualOfficeScreen> {
  late OrgTeam _team = widget.initialTeam;
  late OfficeController _controller;
  StreamSubscription<OfficeKnock>? _knockSub;

  bool get _canStartHuddle => orgCanInvite(widget.organization.role);

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _controller = OfficeController(
      teamId: _team.id,
      teamName: _team.name,
      organizationId: widget.organization.id,
    );
    _knockSub = _controller.knocks.listen(_showKnock);
    _controller.init();
  }

  Future<void> _detach() async {
    await _knockSub?.cancel();
    _controller.dispose();
  }

  @override
  void dispose() {
    _knockSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _switchTeam(OrgTeam team) async {
    if (team.id == _team.id) return;
    await _detach();
    if (!mounted) return;
    setState(() {
      _team = team;
      _attach();
    });
  }

  void _toast(String? error, {String? ok}) {
    if (!mounted) return;
    if (error != null) {
      orgToast(context, error, error: true);
    } else if (ok != null) {
      orgToast(context, ok);
    }
  }

  void _showKnock(OfficeKnock knock) {
    if (!mounted) return;
    final link = knock.message == null
        ? null
        : RegExp(r'https?://\S+').allMatches(knock.message!).map((m) => m.group(0)!).firstWhere(
              MeetingApi.isQuorumLink,
              orElse: () => '',
            );
    final code = link == null || link.isEmpty ? null : MeetingApi.codeFromLink(link);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 12),
        backgroundColor: orgCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: orgBorder)),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OrgAvatar(name: knock.senderName, logo: knock.senderAvatar, size: 40, circular: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${knock.senderName} knocked on your desk!',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  if (knock.message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(knock.message!, style: const TextStyle(color: orgMuted, fontSize: 12)),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () {
                          messenger.hideCurrentSnackBar();
                          _quickCall(knock.senderId, joinCode: code);
                        },
                        icon: const Icon(Icons.videocam_rounded, size: 16),
                        label: Text(code != null ? 'Join call' : 'Quick 1:1 Call', style: const TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          backgroundColor: orgAccent,
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: messenger.hideCurrentSnackBar,
                        child: const Text('Dismiss', style: TextStyle(color: orgMuted, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _quickCall(String senderId, {String? joinCode}) async {
    var code = joinCode;
    if (code == null) {
      final result = await _controller.startQuickCall(senderId);
      if (result.$2 != null) {
        _toast(result.$2);
        return;
      }
      code = result.$1;
    }
    if (code == null || !mounted) return;
    await MeetingLauncher.joinCode(code, title: 'Quick call', isHost: joinCode == null);
  }

  Future<void> _setZone(OfficeZone zone) async {
    final error = await _controller.changeZone(zone);
    _toast(error);
  }

  Future<void> _onDeskTap(OfficeDesk desk) async {
    final state = _controller.state;
    if (state == null) return;
    if (desk.isEmpty) {
      final error = await _controller.claimDesk(desk.deskId);
      _toast(error);
      return;
    }
    if (desk.occupiedByUserId == CurrentUser.id) return;
    final member = state.members[desk.occupiedByUserId];
    if (member != null) await _openKnockSheet(member);
  }

  Future<void> _sitAtDesk() async {
    _toast(await _controller.sitAtDesk());
  }

  Future<void> _openKnockSheet(OfficeMember member) async {
    if (member.userId == CurrentUser.id) return;
    if (member.zone == OfficeZone.focusPod || member.presence == OfficePresence.doNotDisturb) {
      _toast('${member.name} is in a Focus Pod (Do Not Disturb) and cannot be knocked');
      return;
    }
    final message = await showOrgSheet<String>(context, _KnockSheet(member: member));
    if (message == null || !mounted) return;
    final error = await _controller.knock(member.userId, message: message);
    _toast(error, ok: 'You knocked on ${member.name}\'s desk');
  }

  Future<void> _startHuddle() async {
    final result = await _controller.startHuddle();
    if (result.$2 != null) {
      _toast(result.$2);
      return;
    }
    final code = result.$1;
    if (code == null || !mounted) return;
    await MeetingLauncher.joinCode(code, title: '${_team.name} Huddle', isHost: true);
  }

  Future<void> _joinHuddle(String code) async {
    await MeetingLauncher.joinCode(code, title: '${_team.name} Huddle');
  }

  Future<void> _endHuddle() async {
    final ok = await orgConfirm(
      context,
      title: 'End huddle?',
      body: 'This clears the active meeting from the War Room.',
      action: 'End',
    );
    if (!ok) return;
    _toast(await _controller.endHuddle());
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C2646), orgBg],
        ),
      ),
      child: _scaffold(),
    );
  }

  Widget _scaffold() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: _teamPicker(),
        actions: [
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final active = _controller.state?.totalActive ?? 0;
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: officeGreen.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.circle, size: 8, color: officeGreen),
                        const SizedBox(width: 6),
                        Text(
                          '$active Active',
                          style: const TextStyle(color: officeGreen, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.loading) return const Center(child: CircularProgressIndicator(color: orgTeal));
          final state = _controller.state;
          if (state == null) return _errorView();
          return RefreshIndicator(
            color: orgTeal,
            backgroundColor: orgCard,
            onRefresh: _controller.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                OfficeIsoFloor(state: state, onMemberTap: _openKnockSheet, onDeskTap: _onDeskTap),
                const SizedBox(height: 14),
                _myControls(state),
                const SizedBox(height: 14),
                _warRoom(state),
                const SizedBox(height: 14),
                _openWorkspace(state),
                const SizedBox(height: 14),
                _coffeeLounge(state),
                const SizedBox(height: 14),
                _focusPods(state),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _teamPicker() {
    if (widget.teams.length < 2) {
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(_team.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      );
    }
    return PopupMenuButton<OrgTeam>(
      color: orgCard,
      onSelected: _switchTeam,
      itemBuilder: (_) => [
        for (final t in widget.teams)
          PopupMenuItem(
            value: t,
            child: Text(
              t.name,
              style: TextStyle(color: t.id == _team.id ? orgTeal : Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _team.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
          const Icon(Icons.arrow_drop_down_rounded, color: Colors.white),
        ],
      ),
    );
  }

  Widget _myControls(OfficeState state) {
    final mine = state.members[CurrentUser.id];
    final zone = mine?.zone;
    Widget chip(String label, IconData icon, OfficeZone target, Color color) {
      final selected = zone == target;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _controller.busy || selected ? null : () => _setZone(target),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.16) : orgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? color : orgBorder),
            ),
            child: Column(
              children: [
                Icon(icon, color: selected ? color : orgMuted, size: 22),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(color: selected ? Colors.white : orgMuted, fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('Sit at Desk', Icons.desk_rounded, OfficeZone.openWorkspace, orgTeal),
        const SizedBox(width: 8),
        chip('Coffee Lounge', Icons.coffee_rounded, OfficeZone.coffeeLounge, officeAmber),
        const SizedBox(width: 8),
        chip('Focus Pod', Icons.shield_rounded, OfficeZone.focusPod, officeRed),
      ],
    );
  }

  Widget _warRoom(OfficeState state) {
    final code = state.activeMeetingCode;
    final people = state.inZone(OfficeZone.warRoom);
    Widget action;
    if (code != null) {
      action = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OfficePillButton(label: 'Join Call', icon: Icons.call_rounded, onTap: () => _joinHuddle(code)),
          if (_canStartHuddle)
            TextButton(
              onPressed: _controller.busy ? null : _endHuddle,
              child: const Text('End huddle', style: TextStyle(color: officeRed, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
        ],
      );
    } else if (_canStartHuddle) {
      action = OfficePillButton(
        label: 'Start Huddle',
        icon: Icons.rocket_launch_rounded,
        onTap: _controller.busy ? null : _startHuddle,
      );
    } else {
      action = const Text('Waiting for lead', style: TextStyle(color: orgMuted, fontSize: 12.5));
    }
    return OfficeZoneCard(
      icon: Icons.videocam_rounded,
      title: OfficeZone.warRoom.title,
      subtitle: code != null ? 'Meeting in progress · ${people.length} in call' : 'War Room available',
      accent: code != null ? officeGreen : orgMuted,
      highlight: code != null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: OfficePeopleRow(members: people, emptyText: 'Nobody is in the call yet', onTap: _openKnockSheet)),
          const SizedBox(width: 12),
          action,
        ],
      ),
    );
  }

  Widget _openWorkspace(OfficeState state) {
    final seated = state.inZone(OfficeZone.openWorkspace);
    final free = state.desks.where((d) => d.isEmpty).toList();
    final hasDesk = state.desks.any((d) => d.occupiedByUserId == CurrentUser.id);
    final canSit = !hasDesk && free.isNotEmpty;
    return OfficeZoneCard(
      icon: Icons.desk_rounded,
      title: OfficeZone.openWorkspace.title,
      subtitle: '${free.length} available',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: OfficePeopleRow(members: seated, emptyText: 'Nobody is at a desk', onTap: _openKnockSheet)),
          if (canSit) ...[
            const SizedBox(width: 12),
            OfficePillButton(
              label: 'Sit at desk',
              icon: Icons.desk_rounded,
              onTap: _controller.busy ? null : _sitAtDesk,
            ),
          ],
        ],
      ),
    );
  }

  Widget _coffeeLounge(OfficeState state) {
    final people = state.inZone(OfficeZone.coffeeLounge);
    return OfficeZoneCard(
      icon: Icons.coffee_rounded,
      title: OfficeZone.coffeeLounge.title,
      subtitle: 'Casual breaks · sets you to Be right back',
      accent: officeAmber,
      child: OfficePeopleRow(members: people, emptyText: 'The lounge is quiet', onTap: _openKnockSheet),
    );
  }

  Widget _focusPods(OfficeState state) {
    final people = state.inZone(OfficeZone.focusPod);
    return OfficeZoneCard(
      icon: Icons.shield_rounded,
      title: OfficeZone.focusPod.title,
      subtitle: 'Deep focus · Do not disturb · knocks muted',
      accent: officeRed,
      child: OfficePeopleRow(members: people, emptyText: 'All pods are free', onTap: _openKnockSheet),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: orgMuted, size: 42),
            const SizedBox(height: 12),
            Text(_controller.error ?? 'Could not load the office', textAlign: TextAlign.center, style: const TextStyle(color: orgMuted)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                setState(() => _controller.loading = true);
                _controller.refresh();
              },
              child: const Text('Retry', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _KnockSheet extends StatefulWidget {
  const _KnockSheet({required this.member});
  final OfficeMember member;

  @override
  State<_KnockSheet> createState() => _KnockSheetState();
}

class _KnockSheetState extends State<_KnockSheet> {
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OfficeAvatar(member: m, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(
                      m.statusMessage ?? (m.isInMeeting ? 'In a meeting' : m.presence.label),
                      style: const TextStyle(color: orgMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _message,
            style: const TextStyle(color: Colors.white),
            maxLength: 140,
            textCapitalization: TextCapitalization.sentences,
            decoration: orgInputDecoration('Message (optional)', hint: 'Got 2 mins for a quick check?'),
          ),
          const SizedBox(height: 10),
          OrgPrimaryButton(
            label: 'Knock on desk',
            onPressed: () => Navigator.pop(context, _message.text.trim()),
          ),
        ],
      ),
    );
  }
}
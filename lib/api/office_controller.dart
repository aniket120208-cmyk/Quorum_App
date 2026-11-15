import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/meeting_api.dart';
import 'package:quorum_app/api/office_repository.dart';
import 'package:quorum_app/api/presence_service.dart';
import 'package:quorum_app/api/socket_service.dart';
import 'package:quorum_app/models/meeting_models.dart';
import 'package:quorum_app/models/office_models.dart';

class OfficeController extends ChangeNotifier {
  OfficeController({required this.teamId, required this.teamName, required this.organizationId});

  final String teamId;
  final String teamName;
  final String organizationId;

  final OfficeRepository _repo = OfficeRepository.instance;
  final SocketService _socket = SocketService.instance;
  final StreamController<OfficeKnock> _knocks = StreamController<OfficeKnock>.broadcast();

  OfficeState? state;
  bool loading = true;
  String? error;
  bool busy = false;
  bool _disposed = false;
  bool _joined = false;

  Stream<OfficeKnock> get knocks => _knocks.stream;

  OfficeMember? get me => state?.members[CurrentUser.id];

  late final Map<String, SocketHandler> _handlers = {
    'office:zone-changed': (d) => _onZoneChanged(asMap(d)),
    'office:knocked': (d) => _onKnocked(asMap(d)),
    'office:meeting-started': (d) => _onMeetingStarted(asMap(d)),
    'office:meeting-ended': (d) => _onMeetingEnded(asMap(d)),
    'office:user-joined': (d) => _onUserJoined(asMap(d)),
    'office:user-left': (d) => _onUserLeft(asMap(d)),
  };

  late final void Function(bool) _connectionListener = (connected) {
    if (connected && _joined) _emitJoin();
  };

  void _update() {
    if (!_disposed) notifyListeners();
  }

  Future<void> init() async {
    await _socket.ensureConnected();
    if (_disposed) return;
    _handlers.forEach(_socket.on);
    _socket.addConnectionListener(_connectionListener);
    await refresh();
    _joined = true;
    _emitJoin();
  }

  void _emitJoin() {
    _socket.emitAck('office:join', {'teamId': teamId}, (res) {
      if (_disposed) return;
      final data = res?['data'];
      if (res != null && res['success'] == true && data is Map && data['state'] is Map) {
        state = OfficeState.fromJson(Map<String, dynamic>.from(data['state'] as Map), fallbackTeamId: teamId);
        loading = false;
        error = null;
        _update();
        return;
      }
      if (res == null) unawaited(_restJoin());
    });
  }

  Future<void> _restJoin() async {
    try {
      final s = await _repo.join(teamId);
      if (_disposed) return;
      state = s;
      loading = false;
      error = null;
      _update();
    } catch (_) {}
  }

  Future<void> refresh() async {
    try {
      final s = await _repo.snapshot(teamId);
      if (_disposed) return;
      state = s;
      loading = false;
      error = null;
    } catch (e) {
      if (_disposed) return;
      loading = false;
      if (state == null) error = errorText(e);
    }
    _update();
  }

  void _onZoneChanged(Map<String, dynamic>? m) {
    final s = state;
    if (m == null || s == null || (m['teamId'] ?? teamId).toString() != teamId) return;
    final id = (m['userId'] ?? '').toString();
    if (id.isEmpty) return;
    state = s.withMember(OfficeMember.fromZoneEvent(m, previous: s.members[id]));
    _update();
  }

  void _onKnocked(Map<String, dynamic>? m) {
    if (m == null) return;
    final knock = OfficeKnock.fromJson(m);
    if (knock.teamId.isNotEmpty && knock.teamId != teamId) return;
    if (!PresenceService.instance.isDnd) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.mediumImpact();
    }
    if (!_knocks.isClosed) _knocks.add(knock);
  }

  void _onMeetingStarted(Map<String, dynamic>? m) {
    final s = state;
    if (m == null || s == null || (m['teamId'] ?? teamId).toString() != teamId) return;
    final code = (m['meetingCode'] ?? '').toString();
    if (code.isEmpty) return;
    state = s.copyWith(activeMeetingCode: code);
    _update();
  }

  void _onMeetingEnded(Map<String, dynamic>? m) {
    final s = state;
    if (s == null || (m?['teamId'] ?? teamId).toString() != teamId) return;
    state = s.copyWith(clearMeeting: true);
    _update();
  }

  void _onUserJoined(Map<String, dynamic>? m) {
    final s = state;
    if (m == null || s == null || (m['teamId'] ?? teamId).toString() != teamId) return;
    final raw = m['member'];
    if (raw is! Map) return;
    state = s.withMember(OfficeMember.fromJson(Map<String, dynamic>.from(raw)));
    _update();
  }

  void _onUserLeft(Map<String, dynamic>? m) {
    final s = state;
    if (m == null || s == null || (m['teamId'] ?? teamId).toString() != teamId) return;
    final id = (m['userId'] ?? '').toString();
    if (id.isEmpty || id == CurrentUser.id) return;
    state = s.withoutMember(id);
    _update();
  }

  Future<String?> _run(Future<void> Function() action, {bool reload = false}) async {
    if (busy) return null;
    busy = true;
    _update();
    try {
      await action();
      if (reload) await refresh();
      return null;
    } catch (e) {
      return errorText(e);
    } finally {
      busy = false;
      _update();
    }
  }

  Future<String?> changeZone(OfficeZone zone) => _run(() async {
        final completer = Completer<String?>();
        _socket.emitAck('office:change-zone', {'teamId': teamId, 'newZoneId': zone.apiValue}, (res) {
          if (res == null) {
            completer.complete('fallback');
          } else if (res['success'] == true) {
            final data = res['data'];
            if (data is Map) _onZoneChanged(Map<String, dynamic>.from(data));
            completer.complete(null);
          } else {
            completer.complete((res['message'] ?? 'Could not change zone').toString());
          }
        });
        final result = await completer.future;
        if (result == 'fallback') {
          await _repo.changeZone(teamId, zone);
          await refresh();
        } else if (result != null) {
          throw ApiException(result);
        }
      });

  Future<String?> sitAtDesk() async {
    if (busy) return null;
    busy = true;
    _update();
    try {
      await refresh();
      final s = state;
      if (s == null) return 'Office is not loaded yet';
      final me = s.members[CurrentUser.id];
      final inOpen = me?.zone == OfficeZone.openWorkspace;
      if (inOpen && s.desks.any((d) => d.occupiedByUserId == CurrentUser.id)) return null;
      final free = s.desks.where((d) => d.isEmpty).toList();
      if (free.isEmpty) return 'No free desks right now';
      String? last;
      for (final d in free) {
        try {
          if (inOpen) {
            await _repo.claimDesk(teamId, d.deskId);
          } else {
            await _repo.changeZone(teamId, OfficeZone.openWorkspace, deskId: d.deskId);
          }
          await refresh();
          return null;
        } catch (e) {
          last = errorText(e);
          if (!last.toLowerCase().contains('occupied')) return last;
        }
      }
      await refresh();
      return last ?? 'No free desks right now';
    } finally {
      busy = false;
      _update();
    }
  }

  Future<String?> claimDesk(String deskId) => _run(() => _repo.claimDesk(teamId, deskId), reload: true);

  Future<String?> knock(String targetUserId, {String? message}) =>
      _run(() => _repo.knock(teamId, targetUserId, message: message));

  Future<String?> endHuddle() => _run(() async {
        await _repo.endMeeting(teamId);
        final s = state;
        if (s != null) state = s.copyWith(clearMeeting: true);
      });

  Future<(String?, String?)> startHuddle() async {
    if (busy) return (null, null);
    busy = true;
    _update();
    try {
      final meeting = await MeetingApi.instance.createScopedMeeting(
        title: '$teamName Huddle',
        scope: MeetingScope.team,
        organizationId: organizationId,
        teamId: teamId,
      );
      await _repo.startMeeting(teamId, meeting.code);
      final s = state;
      if (s != null) state = s.copyWith(activeMeetingCode: meeting.code);
      return (meeting.code, null);
    } catch (e) {
      return (null, errorText(e));
    } finally {
      busy = false;
      _update();
    }
  }

  Future<(String?, String?)> startQuickCall(String targetUserId) async {
    try {
      final created = await MeetingApi.instance.createMeeting();
      await _repo.knock(teamId, targetUserId, message: 'Join me for a quick call: ${created.link}');
      return (created.code, null);
    } catch (e) {
      return (null, errorText(e));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _handlers.forEach(_socket.off);
    _socket.removeConnectionListener(_connectionListener);
    if (_joined) _socket.emit('office:leave', {'teamId': teamId});
    _knocks.close();
    super.dispose();
  }
}
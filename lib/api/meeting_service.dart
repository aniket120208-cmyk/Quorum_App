import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:quorum_app/api/api_client.dart';
import 'package:quorum_app/api/current_user.dart' show avatarFromJson;
import 'package:quorum_app/api/meeting_api.dart';
import 'package:quorum_app/api/recording_mixer.dart';
import 'package:quorum_app/api/recording_repository.dart';
import 'package:quorum_app/api/recording_uploader.dart';
import 'package:quorum_app/api/screen_share_foreground.dart';
import 'package:quorum_app/api/socket_service.dart' show asMap;
import 'package:quorum_app/models/chat_models.dart' show ChatUser;
import 'package:quorum_app/models/meeting_models.dart';
import 'package:quorum_app/models/poll_models.dart';
import 'package:quorum_app/models/recording_models.dart';

enum MeetingPhase { idle, connecting, waitingRoom, inCall, failed, rejected, ended }

class _Subscription {
  _Subscription({
    required this.trackId,
    required this.peerId,
    required this.kind,
    required this.pc,
  });

  final String trackId;
  final String peerId;
  final String kind;
  final RTCPeerConnection pc;
  MediaStreamTrack? audioTrack;
  bool remoteSet = false;
  final List<RTCIceCandidate> pending = [];
}

class MeetingService extends ChangeNotifier {
  MeetingService({
    required this.meetingCode,
    required this.userId,
    required this.userName,
    this.userAvatar,
    this.isHost = false,
  });

  static const String _socketUrl = 'https://api.newquorum.me';
  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  final String meetingCode;
  final String userId;
  final String userName;
  final String? userAvatar;
  bool isHost;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final StreamController<String> _notices = StreamController<String>.broadcast();
  final StreamController<MeetingReaction> _reactions = StreamController<MeetingReaction>.broadcast();
  io.Socket? _socket;
  MediaStream? _localStream;
  MediaStreamTrack? _cameraTrack;
  RTCRtpSender? _videoSender;
  RTCRtpSender? _audioSender;
  MediaStream? _recordDisplayStream;
  MediaStream? _screenStream;
  MediaStreamTrack? _screenTrack;
  RTCPeerConnection? _publisher;
  Timer? _joinTimeout;
  Timer? _sfuRetryTimer;
  Map<String, dynamic>? _offerPayload;
  final List<Map<String, dynamic>> _sentPublisherCandidates = [];
  bool _sfuJoined = false;
  int _sfuAttempts = 0;
  int _connectAttempts = 0;
  static const int _maxConnectAttempts = 3;

  final Map<String, RemotePeer> _peers = {};
  final Map<String, _Subscription> _subs = {};
  final List<RTCIceCandidate> _pendingPublisherCandidates = [];
  final List<MeetingChatMessage> _chat = [];
  final List<Poll> _polls = [];
  final Set<String> _votingPolls = {};
  final List<WaitingGuest> _waiting = [];
  MeetingDocument? _activeDocument;

  MeetingPhase _phase = MeetingPhase.idle;
  String? _message;
  bool _rendererReady = false;
  bool _publisherRemoteSet = false;
  bool _inCall = false;
  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isScreenSharing = false;
  bool _screenShareBusy = false;
  bool _hasLocalVideo = false;
  bool _hasLocalAudio = false;
  bool _frontCamera = true;
  bool _soundOn = true;
  bool _chatOpen = false;
  bool _tornDown = false;
  bool _disposed = false;
  bool _handRaised = false;
  int _selfReactionAcked = 0;
  int _selfReactionEchoed = 0;
  int _unreadChat = 0;
  RecordingStatusEvent? _recording;
  bool _recordingBusy = false;
  bool _capturing = false;
  MediaRecorder? _recorder;
  String? _recordPath;
  String? _captureId;
  MediaRecorder? _micRecorder;
  final List<MicSegment> _micSegments = [];
  Future<void> _micChain = Future<void>.value();
  final Stopwatch _recordWatch = Stopwatch();
  Future<void>? _finalizing;
  int _previewEpoch = 0;

  Stream<String> get notices => _notices.stream;
  Stream<MeetingReaction> get reactions => _reactions.stream;
  bool get isHandRaised => _handRaised;
  MeetingPhase get phase => _phase;
  String? get message => _message;
  bool get isMuted => _isMuted;
  bool get isVideoOff => _isVideoOff;
  bool get hasLocalVideo => _hasLocalVideo;
  bool get isScreenSharing => _isScreenSharing;
  int get previewEpoch => _previewEpoch;
  bool get isFrontCamera => _frontCamera;
  bool get soundOn => _soundOn;
  bool get isRecording => _recording?.isRecording == true;
  bool get recordingBusy => _recordingBusy;
  bool get isCapturingRecording => _capturing;
  RecordingStatusEvent? get recording => _recording;
  int get unreadChat => _unreadChat;
  List<RemotePeer> get participants => _peers.values.toList(growable: false);

  RemotePeer? get remoteSharer {
    for (final p in _peers.values) {
      if (p.isScreenSharing) return p;
    }
    return null;
  }
  List<MeetingChatMessage> get chat => List.unmodifiable(_chat);
  List<Poll> get polls => List.unmodifiable(_polls);
  int get openPollCount => _polls.where((p) => !p.isClosed).length;
  List<WaitingGuest> get waitingList => List.unmodifiable(_waiting);
  MeetingDocument? get activeDocument => _activeDocument;
  bool get canCloseDocument {
    final doc = _activeDocument;
    if (doc == null) return false;
    return isHost || doc.openedBy.isEmpty || doc.openedBy == userId;
  }
  bool get _connected => _socket?.connected ?? false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _notice(String text) {
    if (!_disposed && !_notices.isClosed) _notices.add(text);
  }

  void _setPhase(MeetingPhase phase, {String? message}) {
    _phase = phase;
    _message = message;
    _notify();
  }

  Future<void> initLocalMedia({required bool audio, required bool video}) async {
    if (_tornDown) return;
    if (!_rendererReady) {
      await localRenderer.initialize();
      _rendererReady = true;
    }
    if (!audio && !video) {
      _isMuted = true;
      _isVideoOff = true;
      _notify();
      return;
    }

    MediaStream? stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': audio,
        'video': video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
                'frameRate': {'ideal': 24},
              }
            : false,
      });
    } catch (_) {
      if (video && audio) {
        try {
          stream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
        } catch (_) {
          stream = null;
        }
      }
    }

    if (stream != null && _tornDown) {
      for (final t in stream.getTracks()) {
        await t.stop();
      }
      await stream.dispose();
      return;
    }

    if (stream == null) {
      _isMuted = true;
      _isVideoOff = true;
      _notify();
      return;
    }

    _localStream = stream;
    localRenderer.srcObject = stream;
    final videoTracks = stream.getVideoTracks();
    _cameraTrack = videoTracks.isNotEmpty ? videoTracks.first : null;
    _hasLocalVideo = _cameraTrack != null;
    _hasLocalAudio = stream.getAudioTracks().isNotEmpty;
    _isMuted = !_hasLocalAudio;
    _isVideoOff = !_hasLocalVideo;

    try {
      await Helper.setSpeakerphoneOn(true);
    } catch (_) {}
    _notify();
  }

  void toggleMic() {
    if (!_hasLocalAudio) {
      _notice('Microphone is unavailable');
      return;
    }
    _isMuted = !_isMuted;
    for (final t in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !_isMuted;
    }
    if (_inCall) _emitMic(_isMuted);
    _syncMicSegment();
    _notify();
  }

  void toggleCamera() {
    if (!_hasLocalVideo) return;
    _isVideoOff = !_isVideoOff;
    _cameraTrack?.enabled = !_isVideoOff;
    if (_inCall && !_isScreenSharing) _emitCam(_isVideoOff);
    _notify();
  }

  Future<void> startScreenShare() async {
    if (_isScreenSharing || _screenShareBusy || !_inCall || _tornDown) return;
    final other = remoteSharer;
    if (other != null) {
      final who = other.name.trim().isEmpty ? 'Someone' : other.name;
      _notice('$who is already sharing their screen');
      return;
    }
    final sender = _videoSender;
    if (sender == null) {
      _notice('Screen sharing needs your camera to be available');
      return;
    }
    _screenShareBusy = true;
    MediaStream? stream;
    try {
      stream = _recordDisplayStream;
      if (stream == null) {
        if (!await ScreenShareForeground.start()) {
          _notice('Screen sharing permission was denied');
          return;
        }
        stream = await _captureDisplay();
      }
      final tracks = stream.getVideoTracks();
      final taken = remoteSharer;
      if (taken != null) {
        await _discardScreenStream(stream);
        await _stopForeground();
        final who = taken.name.trim().isEmpty ? 'Someone' : taken.name;
        _notice('$who is already sharing their screen');
        return;
      }
      if (tracks.isEmpty || _tornDown || !_inCall || _videoSender == null) {
        await _discardScreenStream(stream);
        await _stopForeground();
        return;
      }
      final track = tracks.first;
      await sender.replaceTrack(track);
      track.onEnded = () => unawaited(stopScreenShare());
      _screenStream = stream;
      _screenTrack = track;
      _isScreenSharing = true;
      if (_isVideoOff) _emitCam(false);
      _emitScreenShare(true);
      _notify();
      unawaited(_refreshMic());
    } catch (_) {
      if (stream != null) await _discardScreenStream(stream);
      await _stopForeground();
      _notice('Unable to start screen sharing');
    } finally {
      _screenShareBusy = false;
    }
  }

  Future<MediaStream> _captureDisplay() async {
    final iOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final constraints = <String, dynamic>{
      'video': iOS ? {'deviceId': 'broadcast'} : true,
      'audio': false,
    };
    return navigator.mediaDevices.getDisplayMedia(constraints);
  }

  Future<void> stopScreenShare() async {
    if (!_isScreenSharing) return;
    _isScreenSharing = false;
    final track = _screenTrack;
    final stream = _screenStream;
    _screenTrack = null;
    _screenStream = null;
    track?.onEnded = null;
    final camera = _cameraTrack;
    final sender = _videoSender;
    if (camera != null && sender != null && !_tornDown) {
      try {
        await sender.replaceTrack(camera);
      } catch (_) {}
    }
    if (stream != null) await _discardScreenStream(stream);
    await _stopForeground();
    await _restoreLocalPreview();
    if (_inCall) {
      _emitScreenShare(false);
      if (_isVideoOff) _emitCam(true);
    }
    _notify();
  }

  Future<void> _restoreLocalPreview() async {
    if (_tornDown || !_rendererReady) return;
    final stream = _localStream;
    if (stream == null) return;
    _cameraTrack?.enabled = !_isVideoOff;
    localRenderer.srcObject = null;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (_tornDown || !_rendererReady || _localStream == null) return;
    localRenderer.srcObject = _localStream;
    _previewEpoch++;
  }

  Future<void> _stopForeground() async {
    if (_recordDisplayStream != null) return;
    await ScreenShareForeground.stop();
  }

  Future<void> _refreshMic() async {
    if (!_hasLocalAudio) return;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final sender = _audioSender;
    final local = _localStream;
    if (sender == null || local == null || _tornDown || !_inCall) return;
    try {
      final fresh = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
      final tracks = fresh.getAudioTracks();
      if (tracks.isEmpty) return;
      final track = tracks.first;
      track.enabled = !_isMuted;
      final old = List<MediaStreamTrack>.of(local.getAudioTracks());
      await sender.replaceTrack(track);
      for (final t in old) {
        try {
          await local.removeTrack(t);
          await t.stop();
        } catch (_) {}
      }
      await local.addTrack(track);
    } catch (_) {}
  }

  Future<void> _releaseRecordDisplay() async {
    final stream = _recordDisplayStream;
    _recordDisplayStream = null;
    if (stream == null) return;
    if (!(_isScreenSharing && identical(_screenStream, stream))) {
      await _discardScreenStream(stream);
      await ScreenShareForeground.stop();
    }
  }

  Future<void> _discardScreenStream(MediaStream stream) async {
    if (identical(stream, _recordDisplayStream)) return;
    for (final t in stream.getTracks()) {
      try {
        await t.stop();
      } catch (_) {}
    }
    try {
      await stream.dispose();
    } catch (_) {}
  }

  Future<void> _disposeScreenShare() async {
    final stream = _screenStream;
    final wasSharing = _isScreenSharing;
    _screenTrack?.onEnded = null;
    _isScreenSharing = false;
    _screenTrack = null;
    _screenStream = null;
    _videoSender = null;
    if (stream != null) await _discardScreenStream(stream);
    if (wasSharing) {
      _emitScreenShare(false);
      await _stopForeground();
    }
  }

  Future<void> switchCamera() async {
    final track = _cameraTrack;
    if (track == null) return;
    try {
      await Helper.switchCamera(track);
      _frontCamera = !_frontCamera;
      _notify();
    } catch (_) {
      _notice('Unable to switch camera');
    }
  }

  Future<void> toggleSound() async {
    _soundOn = !_soundOn;
    for (final sub in _subs.values) {
      final t = sub.audioTrack;
      if (t != null) await _applySound(t);
    }
    _notify();
  }

  Future<void> _applySound(MediaStreamTrack track) async {
    try {
      track.enabled = _soundOn;
    } catch (_) {}
    try {
      await Helper.setVolume(_soundOn ? 1.0 : 0.0, track);
    } catch (_) {}
  }

  Future<void> join() async {
    if (_phase == MeetingPhase.connecting ||
        _phase == MeetingPhase.waitingRoom ||
        _phase == MeetingPhase.inCall) {
      return;
    }
    _connectAttempts = 0;
    _setPhase(MeetingPhase.connecting);
    await _connect();
  }

  Future<void> _connect({bool forceRefresh = false}) async {
    _closeSocket();
    _joinTimeout?.cancel();
    String? token;
    try {
      token = await ApiClient.instance.freshAccessToken(force: forceRefresh);
    } catch (_) {
      token = await ApiClient.instance.tokenStorage.getAccessToken();
    }
    if (_tornDown || _phase != MeetingPhase.connecting) return;

    final socket = io.io(
      _socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setAuth({
            if (token != null && token.isNotEmpty) 'token': token,
            'userId': userId,
            'name': userName,
            'role': isHost ? 'host' : 'participant',
          })
          .enableForceNew()
          .disableAutoConnect()
          .disableReconnection()
          .build(),
    );
    _socket = socket;
    _bindSocket(socket);
    _joinTimeout = Timer(const Duration(seconds: 15), () {
      if (identical(_socket, socket) && _phase == MeetingPhase.connecting) {
        _retryConnect();
      }
    });
    socket.connect();
  }

  void _retryConnect() {
    if (_tornDown || _phase != MeetingPhase.connecting) return;
    _joinTimeout?.cancel();
    _connectAttempts++;
    if (_connectAttempts >= _maxConnectAttempts) {
      _fail('Could not reach the meeting server. Check your connection and try again.');
      return;
    }
    _closeSocket();
    Timer(Duration(milliseconds: 700 * _connectAttempts), () {
      if (!_tornDown && _phase == MeetingPhase.connecting) {
        _connect(forceRefresh: true);
      }
    });
  }

  void _bindSocket(io.Socket s) {
    s.onConnect((_) => _emitJoin(s));
    s.onConnectError((_) {
      if (!identical(_socket, s)) return;
      if (_phase == MeetingPhase.connecting) _retryConnect();
    });
    s.onDisconnect((_) {
      if (_tornDown || _phase == MeetingPhase.ended || _phase == MeetingPhase.failed) return;
      if (_inCall || _phase == MeetingPhase.waitingRoom) {
        _finish(MeetingPhase.ended, 'Connection to the meeting was lost');
      }
    });

    s.on('meeting:joined', (d) {
      final m = asMap(d);
      if (m == null) return;
      if (m['role'] == 'host') isHost = true;
      _applyWaitingList(m['waitingRoom'] ?? m['waitingList'] ?? m['waiting']);
      _enterCall(m['participants']);
    });
    s.on('meeting:waiting-room', (_) {
      if (_phase == MeetingPhase.connecting) _setPhase(MeetingPhase.waitingRoom);
    });
    s.on('meeting:admitted', (_) {
      if (_phase == MeetingPhase.waitingRoom || _phase == MeetingPhase.connecting) {
        _enterCall(null);
      }
    });
    s.on('meeting:rejected', (d) {
      final text = asMap(d)?['message']?.toString() ?? 'The host declined your request';
      _finish(MeetingPhase.rejected, text);
    });
    s.on('meeting:guest-waiting', (d) {
      final m = asMap(d);
      if (m == null) return;
      _addWaitingGuest(m['user'] is Map ? m['user'] : m);
      _notify();
    });
    s.on('meeting:participant-joined', (d) {
      _applyRoster(asMap(d)?['participants']);
      _notify();
    });
    s.on('meeting:participant-left', (d) {
      final m = asMap(d);
      if (m == null) return;
      final id = (m['userId'] ?? '').toString();
      if (id.isNotEmpty) _removePeer(id);
      _applyRoster(m['participants'], prune: true);
      _notify();
    });
    s.on('meeting:participant-mic-status', (d) {
      final m = asMap(d);
      if (m == null) return;
      final peer = _peers[(m['userId'] ?? '').toString()];
      if (peer == null) return;
      peer.isMuted = m['isMuted'] == true;
      _notify();
    });
    s.on('meeting:participant-cam-status', (d) {
      final m = asMap(d);
      if (m == null) return;
      final peer = _peers[(m['userId'] ?? '').toString()];
      if (peer == null) return;
      peer.isVideoOff = m['isVideoOff'] == true;
      _notify();
    });
    s.on('meeting:participant-screen-share-status', (d) {
      final m = asMap(d);
      if (m == null) return;
      final peer = _peers[(m['userId'] ?? '').toString()];
      if (peer == null) return;
      final sharing = m['isSharing'] == true;
      if (peer.isScreenSharing != sharing) {
        peer.isScreenSharing = sharing;
        peer.fitContain = sharing;
        if (sharing && _isScreenSharing && userId.compareTo(peer.userId) > 0) {
          final who = peer.name.trim().isEmpty ? 'Someone' : peer.name;
          _notice('$who started sharing their screen');
          unawaited(stopScreenShare());
        }
        _notify();
      }
    });
    s.on('meeting:muted-by-host', (d) {
      if (_hasLocalAudio && !_isMuted) {
        _isMuted = true;
        for (final t in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
          t.enabled = false;
        }
        _syncMicSegment();
        _notify();
      }
      _notice(asMap(d)?['message']?.toString() ?? 'You have been muted by the host');
    });
    s.on('meeting:new-message', (d) {
      final m = asMap(d);
      if (m == null) return;
      _addChat(MeetingChatMessage.fromJson(m));
    });
    s.on('meeting:reaction', (d) {
      final m = asMap(d);
      if (m == null) return;
      final reaction = MeetingReaction.fromJson(m);
      if (reaction.emoji.isEmpty) return;
      if (reaction.userId == userId) {
        if (_selfReactionAcked > 0) {
          _selfReactionAcked--;
          return;
        }
        _selfReactionEchoed++;
      }
      _pushReaction(reaction);
    });
    s.on('meeting:hand-raise-status', (d) {
      final m = asMap(d);
      if (m == null) return;
      final id = (m['userId'] ?? '').toString();
      final raised = m['isHandRaised'] == true;
      if (id == userId) {
        if (_handRaised != raised) {
          _handRaised = raised;
          _notify();
        }
        return;
      }
      final peer = _peers[id];
      if (peer == null || peer.isHandRaised == raised) return;
      peer.isHandRaised = raised;
      if (raised) {
        final name = (m['userName'] ?? '').toString();
        _notice('${name.isEmpty ? peer.name : name} raised their hand');
      }
      _notify();
    });
    s.on('meeting:poll-created', (d) {
      final m = asMap(d);
      final poll = Poll.tryParse(m);
      if (poll == null) {
        unawaited(loadPolls());
        return;
      }
      final isNew = !_polls.any((p) => p.id == poll.id);
      final creator = (m?['createdBy'] ?? m?['creatorId'] ?? m?['userId'] ?? '').toString();
      _upsertPoll(poll, broadcast: true);
      if (isNew && creator != userId) _notice('New poll: ${poll.question}');
    });
    s.on('meeting:poll-updated', (d) {
      final poll = Poll.tryParse(asMap(d));
      if (poll == null) return;
      _upsertPoll(poll, broadcast: true);
    });
    s.on('meeting:poll-closed', (d) {
      final m = asMap(d);
      final parsed = Poll.tryParse(m);
      final id = parsed?.id ?? (m?['pollId'] ?? m?['id'] ?? '').toString();
      if (id.isEmpty) return;
      if (parsed != null) {
        _upsertPoll(parsed.copyWith(isClosed: true), broadcast: true);
        return;
      }
      final i = _polls.indexWhere((p) => p.id == id);
      if (i == -1) return;
      _polls[i] = _polls[i].copyWith(isClosed: true);
      _notify();
    });
    for (final name in const ['meeting:document_opened', 'meeting:document-opened']) {
      s.on(name, (d) => _onDocumentOpened(asMap(d)));
    }
    for (final name in const ['meeting:document_closed', 'meeting:document-closed']) {
      s.on(name, (d) => _onDocumentClosed(asMap(d)));
    }
    s.on('meeting:recording-status', (d) => _onRecordingStatus(asMap(d)));
    s.on('meeting:ended', (d) {
      final text = asMap(d)?['message']?.toString() ?? 'The meeting has been ended by the host';
      _finish(MeetingPhase.ended, text);
    });

    s.on('sfu:joined', (d) {
      _sfuJoined = true;
      _sfuRetryTimer?.cancel();
      final tracks = asMap(d)?['existingTracks'];
      if (tracks is! List) return;
      for (final t in tracks) {
        if (t is Map) {
          _subscribe(
            (t['trackId'] ?? '').toString(),
            (t['kind'] ?? 'video').toString(),
            (t['peerId'] ?? '').toString(),
          );
        }
      }
    });
    s.on('sfu:peer-joined', (d) {
      final m = asMap(d);
      if (m == null) return;
      final id = (m['peerId'] ?? '').toString();
      if (id.isEmpty || id == userId) return;
      final name = (m['name'] ?? '').toString();
      final peer = _peerFor(id, name: name);
      if (name.isNotEmpty) peer.name = name;
      final avatar = avatarFromJson(m) ?? (m['user'] is Map ? avatarFromJson(m['user'] as Map) : null);
      if (avatar != null) peer.avatarUrl = avatar;
      _notify();
    });
    s.on('sfu:peer-left', (d) {
      final id = (asMap(d)?['peerId'] ?? '').toString();
      if (id.isEmpty || id == userId) return;
      _removePeer(id);
      _notify();
    });
    s.on('sfu:new-producer', (d) {
      final m = asMap(d);
      if (m == null) return;
      _subscribe(
        (m['trackId'] ?? '').toString(),
        (m['kind'] ?? 'video').toString(),
        (m['peerId'] ?? '').toString(),
      );
    });
    s.on('sfu:track-unpublished', (d) => _onTrackUnpublished(asMap(d)));
    s.on('sfu:answer', (d) => _onPublisherAnswer(asMap(d)));
    s.on('sfu:subscribed', (d) => _onSubscribed(asMap(d)));
    s.on('sfu:ice-candidate', (d) => _onRemoteCandidate(asMap(d)));
    s.on('sfu:subscribe-ice-candidate', (d) => _onSubscriberCandidate(asMap(d)));
    s.on('meeting:error', (d) {
      final text = asMap(d)?['message']?.toString() ?? 'Unable to join the meeting';
      if (_phase == MeetingPhase.connecting || _phase == MeetingPhase.waitingRoom) {
        _fail(text);
        return;
      }
      _notice(text);
    });
    s.on('sfu:error', (d) {
      final payload = asMap(d);
      final text = payload?['message']?.toString() ?? 'Media server error';
      final forbidden = payload?['code']?.toString() == 'FORBIDDEN' || payload?['statusCode'] == 403;
      if (forbidden) {
        _fail(text);
        return;
      }
      final lower = text.toLowerCase();
      final unauthorized = lower.contains('unauthor') || lower.contains('not authorized');
      if (unauthorized && !_sfuJoined && _inCall && _sfuAttempts < 5) {
        _scheduleSfuRetry();
        return;
      }
      _notice(text);
    });
  }

  void _emitJoin(io.Socket s) {
    s.emitWithAck('meeting:join', {'meetingCode': meetingCode}, ack: (raw) {
      _joinTimeout?.cancel();
      final res = asMap(raw);
      if (res == null || res['success'] != true) {
        final text = (res?['message'] ?? 'Unable to join the meeting').toString();
        final lower = text.toLowerCase();
        final authIssue = lower.contains('unauthor') || lower.contains('token') || lower.contains('jwt');
        if (authIssue && _phase == MeetingPhase.connecting && _connectAttempts < _maxConnectAttempts - 1) {
          _retryConnect();
          return;
        }
        _fail(text);
        return;
      }
      final data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};
      if (data['status'] == 'waiting_room') {
        if (_phase == MeetingPhase.connecting) _setPhase(MeetingPhase.waitingRoom);
        return;
      }
      if (data['role'] == 'host') isHost = true;
      _applyWaitingList(data['waitingRoom'] ?? data['waitingList'] ?? data['waiting']);
      _enterCall(data['participants']);
    });
  }

  void _addWaitingGuest(dynamic raw) {
    if (raw is! Map) return;
    final id = (raw['userId'] ?? raw['id'] ?? '').toString();
    if (id.isEmpty || id == userId) return;
    _waiting.removeWhere((g) => g.userId == id);
    _waiting.add(WaitingGuest(userId: id, name: (raw['name'] ?? 'Guest').toString()));
  }

  void _scheduleSfuRetry() {
    if (_sfuRetryTimer?.isActive ?? false) return;
    _sfuAttempts++;
    _sfuRetryTimer = Timer(Duration(milliseconds: 600 * _sfuAttempts), _resendSfu);
  }

  void _resendSfu() {
    final socket = _socket;
    if (socket == null || !socket.connected || _tornDown || _sfuJoined) return;
    socket.emit('sfu:join', {
      'roomCode': meetingCode,
      'peerId': userId,
      'name': userName,
      if (userAvatar != null) 'avatar': userAvatar,
    });
    final offer = _offerPayload;
    if (offer != null) {
      socket.emit('sfu:offer', offer);
      for (final candidate in _sentPublisherCandidates) {
        socket.emit('sfu:ice-candidate', candidate);
      }
    }
  }

  void _applyWaitingList(dynamic raw) {
    if (raw is! List) return;
    for (final item in raw) {
      _addWaitingGuest(item);
    }
  }

  void _enterCall(dynamic rawParticipants) {
    _joinTimeout?.cancel();
    _applyRoster(rawParticipants);
    if (_inCall || _tornDown) {
      _notify();
      return;
    }
    _inCall = true;
    _setPhase(MeetingPhase.inCall);
    unawaited(loadPolls());
    unawaited(loadRecordingStatus());
    if (_isMuted && _hasLocalAudio) _emitMic(true);
    if (_isVideoOff && _hasLocalVideo) _emitCam(true);
    unawaited(_startPublishing());
  }

  void _applyRoster(dynamic raw, {bool prune = false}) {
    if (raw is! List) return;
    final seen = <String>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final id = (item['userId'] ?? item['id'] ?? '').toString();
      if (id.isEmpty || id == userId) continue;
      seen.add(id);
      final name = (item['name'] ?? '').toString();
      final peer = _peerFor(id, name: name);
      if (name.isNotEmpty) peer.name = name;
      final avatar = avatarFromJson(item) ?? (item['user'] is Map ? avatarFromJson(item['user'] as Map) : null);
      if (avatar != null) peer.avatarUrl = avatar;
      if (item.containsKey('isMuted')) peer.isMuted = item['isMuted'] == true;
      if (item.containsKey('isVideoOff')) peer.isVideoOff = item['isVideoOff'] == true;
      if (item.containsKey('isHandRaised')) peer.isHandRaised = item['isHandRaised'] == true;
      if (item.containsKey('isScreenSharing')) {
        final sharing = item['isScreenSharing'] == true;
        if (peer.isScreenSharing != sharing) {
          peer.isScreenSharing = sharing;
          peer.fitContain = sharing;
        }
      }
    }
    if (prune) {
      for (final id in _peers.keys.where((k) => !seen.contains(k)).toList()) {
        _removePeer(id);
      }
    }
  }

  RemotePeer _peerFor(String id, {String name = ''}) {
    return _peers.putIfAbsent(
      id,
      () => RemotePeer(userId: id, name: name.isNotEmpty ? name : 'Participant'),
    );
  }

  void _removePeer(String id) {
    final peer = _peers.remove(id);
    final owned = _subs.values.where((s) => s.peerId == id).map((s) => s.trackId).toList();
    for (final trackId in owned) {
      final sub = _subs.remove(trackId);
      if (sub != null) unawaited(_closePc(sub.pc));
    }
    if (peer != null) unawaited(peer.dispose());
  }

  Future<void> _startPublishing() async {
    final socket = _socket;
    if (socket == null) return;
    _sfuJoined = false;
    _sfuAttempts = 0;
    _offerPayload = null;
    _sentPublisherCandidates.clear();
    _sfuRetryTimer?.cancel();
    try {
      final stream = _localStream;
      RTCPeerConnection? pc;
      if (stream != null && stream.getTracks().isNotEmpty) {
        pc = await createPeerConnection(_iceConfig);
        if (_tornDown) {
          await _closePc(pc);
          return;
        }
        _publisher = pc;
        pc.onIceCandidate = (c) => _emitCandidate(c);
        _videoSender = null;
        _audioSender = null;
        for (final track in stream.getTracks()) {
          final sender = await pc.addTrack(track, stream);
          if (track.kind == 'video') _videoSender = sender;
          if (track.kind == 'audio') _audioSender = sender;
        }
        final screenTrack = _screenTrack;
        if (_isScreenSharing && screenTrack != null && _videoSender != null) {
          await _videoSender!.replaceTrack(screenTrack);
        }
      }

      socket.emit('sfu:join', {
      'roomCode': meetingCode,
      'peerId': userId,
      'name': userName,
      if (userAvatar != null) 'avatar': userAvatar,
    });

      if (pc != null) {
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        final payload = {
          'roomCode': meetingCode,
          'peerId': userId,
          'sdp': {'type': offer.type, 'sdp': offer.sdp},
        };
        _offerPayload = payload;
        socket.emit('sfu:offer', payload);
      }
    } catch (_) {
      _notice('Unable to start your camera and microphone stream');
    }
  }

  Future<void> _onPublisherAnswer(Map<String, dynamic>? m) async {
    final pc = _publisher;
    final sdp = m?['sdp'];
    if (pc == null || sdp is! Map) return;
    try {
      await pc.setRemoteDescription(
        RTCSessionDescription(sdp['sdp']?.toString(), sdp['type']?.toString()),
      );
      _publisherRemoteSet = true;
      for (final c in _pendingPublisherCandidates) {
        await pc.addCandidate(c);
      }
      _pendingPublisherCandidates.clear();
    } catch (_) {
      _notice('Media negotiation failed');
    }
  }

  Future<void> _subscribe(String trackId, String kind, String peerId) async {
    if (kind.isEmpty) kind = 'video';
    if (trackId.isEmpty || peerId.isEmpty || peerId == userId) return;
    if (_subs.containsKey(trackId) || (kind != 'video' && kind != 'audio')) return;
    final socket = _socket;
    if (socket == null) return;
    final peer = _peerFor(peerId);
    try {
      final pc = await createPeerConnection(_iceConfig);
      if (_tornDown || !_peers.containsKey(peerId) || _subs.containsKey(trackId)) {
        await _closePc(pc);
        return;
      }
      final sub = _Subscription(trackId: trackId, peerId: peerId, kind: kind, pc: pc);
      _subs[trackId] = sub;

      pc.onIceCandidate = (c) => _emitCandidate(c, trackId: trackId);
      pc.onTrack = (RTCTrackEvent e) async {
        if (e.track.kind == 'audio') {
          sub.audioTrack = e.track;
          await _applySound(e.track);
          return;
        }
        if (e.track.kind != 'video') return;
        MediaStream stream;
        if (e.streams.isNotEmpty) {
          stream = e.streams.first;
        } else {
          stream = await createLocalMediaStream('remote-$peerId');
          await stream.addTrack(e.track);
        }
        await peer.attachVideo(stream);
        _notify();
        _requestKeyframe(peerId, trackId);
      };

      await pc.addTransceiver(
        kind: kind == 'video' ? RTCRtpMediaType.RTCRtpMediaTypeVideo : RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      socket.emit('sfu:subscribe', {
        'roomCode': meetingCode,
        'subscriberPeerId': userId,
        'trackId': trackId,
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
    } catch (_) {
      _subs.remove(trackId);
    }
  }

  Future<void> _onSubscribed(Map<String, dynamic>? m) async {
    if (m == null) return;
    final sub = _subs[(m['trackId'] ?? '').toString()];
    final sdp = m['sdp'];
    if (sub == null || sdp is! Map) return;
    try {
      await sub.pc.setRemoteDescription(
        RTCSessionDescription(sdp['sdp']?.toString(), sdp['type']?.toString()),
      );
      sub.remoteSet = true;
      for (final c in sub.pending) {
        await sub.pc.addCandidate(c);
      }
      sub.pending.clear();
    } catch (_) {
      _subs.remove(sub.trackId);
      unawaited(_closePc(sub.pc));
    }
  }

  void _emitCandidate(RTCIceCandidate c, {String? trackId}) {
    if (c.candidate == null || !_connected) return;
    final candidate = {
      'candidate': c.candidate,
      'sdpMid': c.sdpMid,
      'sdpMLineIndex': c.sdpMLineIndex,
    };
    if (trackId == null) {
      final payload = {
        'roomCode': meetingCode,
        'peerId': userId,
        'candidate': candidate,
        'target': 'publisher',
      };
      _sentPublisherCandidates.add(payload);
      _socket!.emit('sfu:ice-candidate', payload);
    } else {
      _socket!.emit('sfu:subscribe-ice-candidate', {
        'roomCode': meetingCode,
        'peerId': userId,
        'trackId': trackId,
        'candidate': candidate,
      });
    }
  }

  void _requestKeyframe(String publisherPeerId, String trackId) {
    if (!_connected) return;
    _socket!.emit('sfu:request-keyframe', {
      'roomCode': meetingCode,
      'publisherPeerId': publisherPeerId,
      'trackId': trackId,
    });
  }

  Future<void> _onTrackUnpublished(Map<String, dynamic>? m) async {
    if (m == null) return;
    final trackId = (m['trackId'] ?? '').toString();
    final sub = _subs.remove(trackId);
    if (sub == null) return;
    await _closePc(sub.pc);
    if (sub.kind == 'video') {
      final stillHasVideo = _subs.values.any((s) => s.peerId == sub.peerId && s.kind == 'video');
      if (!stillHasVideo) {
        await _peers[sub.peerId]?.detachVideo();
      }
    }
    _notify();
  }

  Future<void> _addSubscriberCandidate(_Subscription sub, RTCIceCandidate candidate) async {
    try {
      if (sub.remoteSet) {
        await sub.pc.addCandidate(candidate);
      } else {
        sub.pending.add(candidate);
      }
    } catch (_) {}
  }

  RTCIceCandidate? _parseCandidate(dynamic raw) {
    if (raw is! Map || raw['candidate'] == null) return null;
    return RTCIceCandidate(
      raw['candidate'].toString(),
      raw['sdpMid']?.toString(),
      (raw['sdpMLineIndex'] as num?)?.toInt(),
    );
  }

  Future<void> _onSubscriberCandidate(Map<String, dynamic>? m) async {
    final candidate = _parseCandidate(m?['candidate']);
    final sub = _subs[(m?['trackId'] ?? '').toString()];
    if (candidate == null || sub == null) return;
    await _addSubscriberCandidate(sub, candidate);
  }

  Future<void> _onRemoteCandidate(Map<String, dynamic>? m) async {
    final candidate = _parseCandidate(m?['candidate']);
    if (candidate == null) return;
    final trackId = m?['trackId']?.toString();
    final target = m?['target']?.toString();
    if (trackId != null && trackId.isNotEmpty && target != 'publisher') {
      final sub = _subs[trackId];
      if (sub != null) {
        await _addSubscriberCandidate(sub, candidate);
        return;
      }
    }
    final pc = _publisher;
    if (pc == null) return;
    try {
      if (_publisherRemoteSet) {
        await pc.addCandidate(candidate);
      } else {
        _pendingPublisherCandidates.add(candidate);
      }
    } catch (_) {}
  }

  void _emitMic(bool muted) {
    if (_connected) {
      _socket!.emit('meeting:toggle-mic', {'meetingCode': meetingCode, 'isMuted': muted});
    }
  }

  void _emitScreenShare(bool sharing) {
    if (_connected) {
      _socket!.emit('meeting:toggle-screen-share', {'meetingCode': meetingCode, 'isSharing': sharing});
      _socket!.emit('meeting:screen-share', {'meetingCode': meetingCode, 'isSharing': sharing});
    }
  }

  void _emitCam(bool off) {
    if (_connected) {
      _socket!.emit('meeting:toggle-cam', {'meetingCode': meetingCode, 'isVideoOff': off});
    }
  }

  void _pushReaction(MeetingReaction reaction) {
    if (!_disposed && !_reactions.isClosed) _reactions.add(reaction);
  }

  void sendReaction(String emoji) {
    final socket = _socket;
    if (!_inCall || socket == null || !socket.connected) {
      _notice('Not connected to the meeting');
      return;
    }
    socket.emitWithAck('meeting:reaction', {'meetingCode': meetingCode, 'emoji': emoji}, ack: (raw) {
      final res = asMap(raw);
      if (res != null && res['success'] != true) {
        _notice((res['message'] ?? 'Reaction could not be sent').toString());
        return;
      }
      if (_selfReactionEchoed > 0) {
        _selfReactionEchoed--;
        return;
      }
      _selfReactionAcked++;
      _pushReaction(MeetingReaction(
        userId: userId,
        userName: userName,
        emoji: emoji,
        timestamp: DateTime.now(),
      ));
    });
  }

  void toggleHand() {
    final socket = _socket;
    if (!_inCall || socket == null || !socket.connected) return;
    final next = !_handRaised;
    _handRaised = next;
    _notify();
    socket.emit('meeting:toggle-hand', {'meetingCode': meetingCode, 'isHandRaised': next});
  }

  void _addChat(MeetingChatMessage msg) {
    if (msg.senderId == userId) {
      final duplicate = _chat.any((c) =>
          c.senderId == userId &&
          c.content == msg.content &&
          msg.timestamp.difference(c.timestamp).inSeconds.abs() < 5);
      if (duplicate) return;
    } else if (!_chatOpen) {
      _unreadChat++;
    }
    _chat.add(msg);
    _notify();
  }

  void setChatOpen(bool open) {
    _chatOpen = open;
    if (open) _unreadChat = 0;
    _notify();
  }

  Future<String?> sendMessage(String content) {
    final completer = Completer<String?>();
    final socket = _socket;
    if (socket == null || !socket.connected) {
      return Future.value('Not connected to the meeting');
    }
    final timer = Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) completer.complete('Message timed out');
    });
    socket.emitWithAck('meeting:send-message', {'meetingCode': meetingCode, 'content': content},
        ack: (raw) {
      timer.cancel();
      if (completer.isCompleted) return;
      final res = asMap(raw);
      if (res != null && res['success'] == true) {
        _addChat(MeetingChatMessage(
          senderId: userId,
          senderName: userName,
          content: content,
          timestamp: DateTime.now(),
        ));
        completer.complete(null);
      } else {
        completer.complete((res?['message'] ?? 'Message could not be sent').toString());
      }
    });
    return completer.future;
  }

  void _upsertPoll(Poll incoming, {bool broadcast = false}) {
    final i = _polls.indexWhere((p) => p.id == incoming.id);
    final previous = i == -1 ? null : _polls[i];
    final next = broadcast ? incoming.resolvedFor(userId, previous) : incoming;
    if (i == -1) {
      _polls.add(next);
    } else {
      _polls[i] = next;
    }
    _notify();
  }

  Future<void> loadPolls() async {
    final socket = _socket;
    List<Poll>? fetched;
    if (socket != null && socket.connected) {
      final completer = Completer<List<Poll>?>();
      final timer = Timer(const Duration(seconds: 8), () {
        if (!completer.isCompleted) completer.complete(null);
      });
      socket.emitWithAck('meeting:get-polls', {'meetingCode': meetingCode}, ack: (raw) {
        timer.cancel();
        if (completer.isCompleted) return;
        final res = asMap(raw);
        completer.complete(res != null && res['success'] == true ? Poll.listFrom(res['data']) : null);
      });
      fetched = await completer.future;
    }
    if (fetched == null) {
      try {
        fetched = await MeetingApi.instance.polls(meetingCode);
      } catch (_) {}
    }
    if (fetched == null || _disposed || _tornDown) return;
    _polls
      ..clear()
      ..addAll(fetched);
    _notify();
  }

  Future<String?> createPoll(PollDraft draft) {
    final socket = _socket;
    if (!_inCall || socket == null || !socket.connected) {
      return Future.value('Not connected to the meeting');
    }
    final completer = Completer<String?>();
    final timer = Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) completer.complete('Poll timed out');
    });
    socket.emitWithAck('meeting:create-poll', {'meetingCode': meetingCode, ...draft.toJson()}, ack: (raw) {
      timer.cancel();
      if (completer.isCompleted) return;
      final res = asMap(raw);
      if (res == null || res['success'] != true) {
        completer.complete((res?['message'] ?? 'Poll could not be created').toString());
        return;
      }
      final created = Poll.tryParse(res['data']);
      if (created != null) {
        _upsertPoll(created);
      } else {
        unawaited(loadPolls());
      }
      completer.complete(null);
    });
    return completer.future;
  }

  void votePoll(String pollId, String optionId) {
    final socket = _socket;
    final i = _polls.indexWhere((p) => p.id == pollId);
    if (i == -1) return;
    final before = _polls[i];
    if (before.isClosed) {
      _notice('This poll is closed');
      return;
    }
    if (!_inCall || socket == null || !socket.connected) {
      _notice('Not connected to the meeting');
      return;
    }
    if (!_votingPolls.add(pollId)) return;
    final release = Timer(const Duration(seconds: 10), () => _votingPolls.remove(pollId));
    _polls[i] = before.toggledVote(ChatUser(id: userId, name: userName), optionId);
    _notify();
    socket.emitWithAck(
      'meeting:vote-poll',
      {'meetingCode': meetingCode, 'pollId': pollId, 'optionIds': [optionId]},
      ack: (raw) {
        release.cancel();
        _votingPolls.remove(pollId);
        final res = asMap(raw);
        final idx = _polls.indexWhere((p) => p.id == pollId);
        if (idx == -1) return;
        if (res == null || res['success'] != true) {
          _polls[idx] = before;
          _notify();
          _notice((res?['message'] ?? 'Vote could not be recorded').toString());
          return;
        }
        final updated = Poll.tryParse(res['data']);
        if (updated != null) {
          _polls[idx] = updated;
          _notify();
        }
      },
    );
  }

  Future<String?> closePoll(String pollId) {
    final socket = _socket;
    if (!_inCall || socket == null || !socket.connected) {
      return Future.value('Not connected to the meeting');
    }
    final completer = Completer<String?>();
    final timer = Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) completer.complete('Request timed out');
    });
    socket.emitWithAck('meeting:close-poll', {'meetingCode': meetingCode, 'pollId': pollId}, ack: (raw) {
      timer.cancel();
      if (completer.isCompleted) return;
      final res = asMap(raw);
      if (res == null || res['success'] != true) {
        completer.complete((res?['message'] ?? 'Poll could not be closed').toString());
        return;
      }
      final i = _polls.indexWhere((p) => p.id == pollId);
      if (i != -1) {
        _polls[i] = _polls[i].copyWith(isClosed: true);
        _notify();
      }
      completer.complete(null);
    });
    return completer.future;
  }

  void admit(String guestId) {
    final socket = _socket;
    if (socket == null || !socket.connected) return;
    socket.emitWithAck(
        'meeting:admit-participant',
        {'meetingCode': meetingCode, 'targetUserId': guestId, 'userId': guestId},
        ack: (raw) {
      final res = asMap(raw);
      if (res != null && res['success'] == false) {
        _notice((res['message'] ?? 'Unable to admit participant').toString());
        return;
      }
      _waiting.removeWhere((g) => g.userId == guestId);
      _notify();
    });
  }

  void reject(String guestId) {
    if (_connected) {
      _socket!.emit('meeting:reject-participant', {
        'meetingCode': meetingCode,
        'targetUserId': guestId,
        'userId': guestId,
      });
    }
    _waiting.removeWhere((g) => g.userId == guestId);
    _notify();
  }

  void muteParticipant(String targetUserId) {
    if (_connected) {
      _socket!.emit('meeting:mute-participant', {'meetingCode': meetingCode, 'targetUserId': targetUserId});
    }
  }

  void _onDocumentOpened(Map<String, dynamic>? m) {
    if (m == null || _tornDown) return;
    final code = (m['meetingCode'] ?? '').toString();
    if (code.isNotEmpty && code != meetingCode) return;
    final id = (m['documentId'] ?? m['id'] ?? '').toString();
    if (id.isEmpty) return;
    final title = (m['title'] ?? m['documentTitle'] ?? '').toString();
    final reported = (m['openedBy'] ?? '').toString();
    final changed = _activeDocument?.documentId != id;
    final self = reported == userId || (userName.isNotEmpty && reported == userName);
    final keepOwner = !changed && _activeDocument?.openedBy == userId;
    final openedBy = self || keepOwner ? userId : reported;
    _activeDocument = MeetingDocument(
      documentId: id,
      title: title.isEmpty ? (_activeDocument?.title ?? 'Meeting notes') : title,
      openedBy: openedBy,
    );
    if (changed && !self) {
      String who = '';
      for (final peer in _peers.values) {
        if (peer.userId == openedBy) who = peer.name;
      }
      if (who.isEmpty && openedBy.isNotEmpty && !_looksLikeId(openedBy)) who = openedBy;
      _notice(who.isEmpty ? 'A document was opened' : '$who opened a document');
    }
    _notify();
  }

  bool _looksLikeId(String value) => value.length >= 20 && !value.contains(' ');

  void _onDocumentClosed(Map<String, dynamic>? m) {
    if (_activeDocument == null) return;
    final code = (m?['meetingCode'] ?? '').toString();
    if (code.isNotEmpty && code != meetingCode) return;
    final id = (m?['documentId'] ?? '').toString();
    if (id.isNotEmpty && id != _activeDocument!.documentId) return;
    _activeDocument = null;
    _notify();
  }

  void openDocument(String documentId, String title) {
    final socket = _socket;
    if (!_inCall || socket == null || !socket.connected) {
      _notice('Not connected to the meeting');
      return;
    }
    socket.emit('meeting:document_opened', {
      'meetingCodeOrId': meetingCode,
      'documentId': documentId,
      'documentTitle': title,
    });
    _activeDocument = MeetingDocument(documentId: documentId, title: title, openedBy: userId);
    _notify();
  }

  void closeDocument() {
    final doc = _activeDocument;
    if (doc == null) return;
    final socket = _socket;
    if (socket != null && socket.connected) {
      socket.emit('meeting:document_closed', {
        'meetingCodeOrId': meetingCode,
        'documentId': doc.documentId,
      });
    }
    _activeDocument = null;
    _notify();
  }

  void _fail(String text) {
    _finish(MeetingPhase.failed, text);
  }

  void _finish(MeetingPhase phase, String text) {
    _joinTimeout?.cancel();
    _inCall = false;
    _closeSocket();
    unawaited(_releaseMedia(keepLocal: phase == MeetingPhase.failed));
    _setPhase(phase, message: text);
  }

  Future<void> leave({bool endForAll = false}) async {
    if (_capturing) {
      await stopRecording();
    } else if (endForAll && isHost && isRecording) {
      await stopRecording();
    }
    final socket = _socket;
    if (socket != null && socket.connected) {
      socket.emit('sfu:leave', {'roomCode': meetingCode});
      if (endForAll && isHost) {
        socket.emit('meeting:end', {'meetingCode': meetingCode});
      } else {
        socket.emit('meeting:leave', {'meetingCode': meetingCode});
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await _teardown();
  }

  void _closeSocket() {
    _sfuRetryTimer?.cancel();
    _activeDocument = null;
    final s = _socket;
    _socket = null;
    s?.dispose();
  }

  Future<void> _closePc(RTCPeerConnection pc) async {
    try {
      await pc.close();
      await pc.dispose();
    } catch (_) {}
  }

  Future<void> _releaseMedia({bool keepLocal = false}) async {
    await _disposeScreenShare();
    for (final sub in _subs.values.toList()) {
      await _closePc(sub.pc);
    }
    _subs.clear();
    final pub = _publisher;
    _publisher = null;
    _publisherRemoteSet = false;
    _pendingPublisherCandidates.clear();
    if (pub != null) await _closePc(pub);
    for (final peer in _peers.values.toList()) {
      await peer.dispose();
    }
    _peers.clear();

    if (!keepLocal) {
      final local = _localStream;
      _localStream = null;
      _cameraTrack = null;
      if (local != null) {
        for (final t in local.getTracks()) {
          await t.stop();
        }
        await local.dispose();
      }
      if (_rendererReady) localRenderer.srcObject = null;
    }
  }

  Future<void> _teardown() async {
    if (_tornDown) return;
    _tornDown = true;
    _joinTimeout?.cancel();
    _inCall = false;
    if (_capturing) await _abortCapture();
    _closeSocket();
    await _releaseMedia();
    if (_rendererReady) {
      _rendererReady = false;
      try {
        await localRenderer.dispose();
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>?> _ackRequest(
    String event,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 12),
  }) {
    final socket = _socket;
    if (socket == null || !socket.connected) return Future.value(null);
    final completer = Completer<Map<String, dynamic>?>();
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(null);
    });
    socket.emitWithAck(event, payload, ack: (raw) {
      timer.cancel();
      if (!completer.isCompleted) completer.complete(asMap(raw));
    });
    return completer.future;
  }

  Future<void> loadRecordingStatus() async {
    final res = await _ackRequest('meeting:get-recording-status', {'meetingCode': meetingCode});
    if (res == null || _disposed || _tornDown) return;
    final data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : res;
    if (data['isRecording'] == null && data['status'] == null) return;
    final event = RecordingStatusEvent.fromJson(data);
    if (event.isRecording) {
      _recording = event;
      _notify();
    } else if (_recording != null && !_capturing) {
      _recording = null;
      _notify();
    }
  }

  void _onRecordingStatus(Map<String, dynamic>? m) {
    if (m == null || _disposed) return;
    final event = RecordingStatusEvent.fromJson(m);
    final wasRecording = isRecording;
    if (event.isRecording) {
      _recording = event;
      if (!wasRecording && event.startedBy?.id != userId) {
        final who = event.startedBy?.name ?? 'The host';
        _notice('$who started recording this meeting.');
        SystemSound.play(SystemSoundType.alert);
      }
    } else {
      _recording = null;
      if (wasRecording) {
        if (_capturing && event.stoppedBy?.id != userId) {
          unawaited(_finalizeCapture(event.recordingId));
        }
        if (event.stoppedBy?.id != userId) _notice('Recording stopped. Processing video...');
      }
    }
    _notify();
  }

  Future<MediaStreamTrack?> _recordingVideoTrack() async {
    if (_recordDisplayStream == null && _isScreenSharing && _screenStream != null) {
      _recordDisplayStream = _screenStream;
    }
    if (_recordDisplayStream == null) {
      if (!await ScreenShareForeground.start()) return null;
      try {
        _recordDisplayStream = await _captureDisplay();
      } catch (_) {
        await ScreenShareForeground.stop();
        return null;
      }
    }
    final tracks = _recordDisplayStream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) {
      await _releaseRecordDisplay();
      return null;
    }
    return tracks.first;
  }

  void _syncMicSegment() {
    _micChain = _micChain.then((_) async {
      final want = _capturing && !_isMuted && _hasLocalAudio;
      if (want && _micRecorder == null) {
        final path = '${Directory.systemTemp.path}/quorum-mic-$meetingCode-${DateTime.now().microsecondsSinceEpoch}.mp4';
        final rec = MediaRecorder();
        try {
          await rec.start(path, audioChannel: RecorderAudioChannel.INPUT);
          _micRecorder = rec;
          _micSegments.add(MicSegment(path, _recordWatch.elapsedMilliseconds));
        } catch (_) {}
      } else if (!want && _micRecorder != null) {
        final rec = _micRecorder;
        _micRecorder = null;
        try {
          await rec!.stop().timeout(const Duration(seconds: 8));
        } catch (_) {}
      }
    }).catchError((_) {});
  }

  Future<String?> startRecording() async {
    if (!isHost) return 'Only the host can record this meeting';
    if (_recordingBusy || isRecording || _capturing) return null;
    if (!_inCall || !_connected) return 'Not connected to the meeting';
    _recordingBusy = true;
    _notify();
    MediaRecorder? recorder;
    String? path;
    try {
      final track = await _recordingVideoTrack();
      if (track == null) return 'Screen recording permission is required to record this meeting.';
      path = '${Directory.systemTemp.path}/quorum-rec-$meetingCode-${DateTime.now().millisecondsSinceEpoch}.mp4';
      recorder = MediaRecorder();
      try {
        await recorder.start(path, videoTrack: track, audioChannel: RecorderAudioChannel.OUTPUT);
      } catch (_) {
        recorder = null;
        await _releaseRecordDisplay();
        return 'Recording is not supported on this device.';
      }
      _recordWatch
        ..reset()
        ..start();
      final res = await _ackRequest('meeting:start-recording', {'meetingCode': meetingCode});
      if (res == null || res['success'] != true) {
        _recordWatch.stop();
        try {
          await recorder.stop();
        } catch (_) {}
        recorder = null;
        await _releaseRecordDisplay();
        await _deleteQuietly(path);
        return (res?['message'] ?? res?['error'] ?? 'Could not start the recording').toString();
      }
      final data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};
      _recorder = recorder;
      _recordPath = path;
      _captureId = data['id']?.toString();
      _capturing = true;
      _micSegments.clear();
      _syncMicSegment();
      final event = RecordingStatusEvent.fromJson({
        'isRecording': true,
        'status': 'RECORDING',
        'recordingId': data['id'],
        'meetingCode': meetingCode,
        'startedBy': {'id': userId, 'name': userName},
        'startedAt': data['startedAt'],
      });
      _recording = RecordingStatusEvent(
        isRecording: true,
        status: RecordingStatus.recording,
        recordingId: event.recordingId,
        meetingCode: meetingCode,
        startedBy: event.startedBy,
        startedAt: event.startedAt ?? DateTime.now(),
      );
      return null;
    } finally {
      _recordingBusy = false;
      _notify();
    }
  }

  Future<String?> stopRecording() async {
    if (!isRecording && !_capturing) return null;
    if (_recordingBusy) return null;
    _recordingBusy = true;
    _notify();
    try {
      final id = _recording?.recordingId;
      String? failure;
      if (_connected) {
        final res = await _ackRequest('meeting:stop-recording', {'meetingCode': meetingCode});
        if (res == null || res['success'] != true) {
          failure = (res?['message'] ?? res?['error'] ?? 'Could not stop the recording').toString();
        }
      } else {
        try {
          await RecordingRepository.instance.stop(meetingCode);
        } catch (e) {
          failure = e.toString();
        }
      }
      if (failure != null) return failure;
      _recording = null;
      unawaited(_finalizeInBackground(id));
      _notice('Recording stopped. Processing video...');
      return null;
    } finally {
      _recordingBusy = false;
      _notify();
    }
  }

  Future<void> _awaitStableFile(String path) async {
    var last = -1;
    var stable = 0;
    for (var i = 0; i < 50; i++) {
      var size = 0;
      try {
        final f = File(path);
        if (await f.exists()) size = await f.length();
      } catch (_) {}
      if (size > 0 && size == last) {
        stable++;
        if (stable >= 3) return;
      } else {
        stable = 0;
      }
      last = size;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<void> _finalizeInBackground(String? recordingId) {
    final f = _finalizeCapture(recordingId).catchError((_) {});
    _finalizing = f;
    f.whenComplete(() {
      if (identical(_finalizing, f)) _finalizing = null;
    });
    return f;
  }

  Future<void> _finalizeCapture(String? recordingId) async {
    final recorder = _recorder;
    final path = _recordPath;
    if (recorder == null || path == null) {
      await _releaseRecordDisplay();
      return;
    }
    final id = (recordingId != null && recordingId.isNotEmpty) ? recordingId : _captureId;
    _recorder = null;
    _recordPath = null;
    _captureId = null;
    _capturing = false;
    _recordWatch.stop();
    final seconds = _recordWatch.elapsed.inSeconds < 1 ? 1 : _recordWatch.elapsed.inSeconds;
    _syncMicSegment();
    await _micChain.timeout(const Duration(seconds: 8), onTimeout: () {});
    try {
      await recorder.stop().timeout(const Duration(seconds: 8));
    } catch (_) {}
    await _releaseRecordDisplay();
    final segments = List<MicSegment>.of(_micSegments);
    _micSegments.clear();
    if (id == null || id.isEmpty) {
      await _deleteQuietly(path);
      for (final s in segments) {
        await _deleteQuietly(s.path);
      }
      return;
    }
    await _awaitStableFile(path);
    for (final s in segments) {
      await _awaitStableFile(s.path);
    }
    final finalPath = await RecordingMixer.mix(path, segments);
    RecordingUploader.instance.enqueue(
      meetingCode: meetingCode,
      recordingId: id,
      path: finalPath,
      durationSeconds: seconds,
    );
    _notice('Uploading recording...');
    _notify();
  }

  Future<void> _abortCapture() async {
    final id = _recording?.recordingId;
    try {
      await RecordingRepository.instance.stop(meetingCode);
    } catch (_) {}
    _recording = null;
    await _finalizeCapture(id);
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_teardown());
    _notices.close();
    _reactions.close();
    super.dispose();
  }
}